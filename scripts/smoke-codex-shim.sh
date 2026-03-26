#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

: "${SELF_HOSTED_NIM_MODEL:=meta/llama-3.1-8b-instruct}"
: "${NIM_PROMPT:=Reply with the single word OK.}"
: "${POC_CODEX_SANDBOX:=read-only}"

STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-codex-shim}"
mkdir -p "$ARTIFACT_DIR"

TUNNEL_PORT="${SHIM_TUNNEL_PORT:-8001}"
SHIM_PORT="${SHIM_PORT:-8011}"
UPSTREAM_BASE_URL="${SHIM_UPSTREAM_BASE_URL:-http://127.0.0.1:${TUNNEL_PORT}/v1}"
OUT_JSON="$ARTIFACT_DIR/codex-exec.jsonl"
OUT_LAST="$ARTIFACT_DIR/last-message.txt"
SHIM_LOG="$ARTIFACT_DIR/nim-responses-shim.log"

cleanup() {
  if [[ -n "${SHIM_PID:-}" ]] && kill -0 "$SHIM_PID" >/dev/null 2>&1; then
    kill "$SHIM_PID" >/dev/null 2>&1 || true
    wait "$SHIM_PID" 2>/dev/null || true
  fi
  if [[ -n "${TUNNEL_PID:-}" ]] && kill -0 "$TUNNEL_PID" >/dev/null 2>&1; then
    kill "$TUNNEL_PID" >/dev/null 2>&1 || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

ssh -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/tmp/umbra_known_hosts \
  -i ~/.ssh/collab_umbra \
  -L "${TUNNEL_PORT}:127.0.0.1:8000" \
  -N \
  codyr@192.168.1.162 &
TUNNEL_PID=$!

sleep 1

ARTIFACT_DIR="$ARTIFACT_DIR" \
SHIM_PORT="$SHIM_PORT" \
SHIM_UPSTREAM_BASE_URL="$UPSTREAM_BASE_URL" \
SHIM_MODEL="$SELF_HOSTED_NIM_MODEL" \
node "$ROOT_DIR/scripts/nim-responses-shim.mjs" >"$SHIM_LOG" 2>&1 &
SHIM_PID=$!

sleep 1

curl --fail --silent --show-error "http://127.0.0.1:${SHIM_PORT}/v1/health/ready" >/dev/null

codex exec \
  --skip-git-repo-check \
  --json \
  --output-last-message "$OUT_LAST" \
  --sandbox "$POC_CODEX_SANDBOX" \
  -C "$ROOT_DIR" \
  -c "model=\"$SELF_HOSTED_NIM_MODEL\"" \
  -c 'model_provider="nvidia_nim_shim"' \
  -c 'model_providers.nvidia_nim_shim.name="NVIDIA NIM Shim"' \
  -c "model_providers.nvidia_nim_shim.base_url=\"http://127.0.0.1:${SHIM_PORT}/v1\"" \
  -c 'model_providers.nvidia_nim_shim.env_key="PATH"' \
  -c 'model_providers.nvidia_nim_shim.wire_api="responses"' \
  -c 'model_providers.nvidia_nim_shim.supports_websockets=false' \
  -c 'model_providers.nvidia_nim_shim.request_max_retries=1' \
  -c 'model_providers.nvidia_nim_shim.stream_max_retries=1' \
  -c 'model_providers.nvidia_nim_shim.stream_idle_timeout_ms=600000' \
  "$NIM_PROMPT" | tee "$OUT_JSON"

printf 'artifacts=%s\n' "$ARTIFACT_DIR"
printf 'last_message_file=%s\n' "$OUT_LAST"
