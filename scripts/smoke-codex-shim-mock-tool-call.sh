#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

: "${MOCK_MODEL:=mock-nvidia-nim}"
: "${MOCK_UPSTREAM_PORT:=$((18021 + (RANDOM % 2000)))}"
: "${SHIM_PORT:=$((MOCK_UPSTREAM_PORT + 1))}"
: "${NIM_PROMPT:=You must call the exec_command tool exactly once. Run the command \`printf shim-tool-ok\` and then reply with exactly shim-tool-ok.}"
: "${POC_CODEX_SANDBOX:=workspace-write}"

STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-codex-shim-mock-tool-call}"
mkdir -p "$ARTIFACT_DIR"

OUT_JSON="$ARTIFACT_DIR/codex-exec.jsonl"
OUT_LAST="$ARTIFACT_DIR/last-message.txt"
SHIM_LOG="$ARTIFACT_DIR/nim-responses-shim.log"
MOCK_LOG="$ARTIFACT_DIR/mock-chat-tools-upstream.log"

cleanup() {
  if [[ -n "${SHIM_PID:-}" ]] && kill -0 "$SHIM_PID" >/dev/null 2>&1; then
    kill "$SHIM_PID" >/dev/null 2>&1 || true
    wait "$SHIM_PID" 2>/dev/null || true
  fi
  if [[ -n "${MOCK_PID:-}" ]] && kill -0 "$MOCK_PID" >/dev/null 2>&1; then
    kill "$MOCK_PID" >/dev/null 2>&1 || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

ARTIFACT_DIR="$ARTIFACT_DIR" \
MOCK_UPSTREAM_PORT="$MOCK_UPSTREAM_PORT" \
MOCK_MODEL="$MOCK_MODEL" \
node "$ROOT_DIR/scripts/mock-chat-tools-upstream.mjs" >"$MOCK_LOG" 2>&1 &
MOCK_PID=$!

sleep 1

ARTIFACT_DIR="$ARTIFACT_DIR" \
SHIM_PORT="$SHIM_PORT" \
SHIM_UPSTREAM_BASE_URL="http://127.0.0.1:${MOCK_UPSTREAM_PORT}/v1" \
SHIM_MODEL="$MOCK_MODEL" \
SHIM_TOOL_ALLOWLIST="exec_command" \
node "$ROOT_DIR/scripts/nim-responses-shim.mjs" >"$SHIM_LOG" 2>&1 &
SHIM_PID=$!

sleep 1

curl --fail --silent --show-error "http://127.0.0.1:${MOCK_UPSTREAM_PORT}/v1/health/ready" >/dev/null
curl --fail --silent --show-error "http://127.0.0.1:${SHIM_PORT}/v1/health/ready" >/dev/null

codex exec \
  --skip-git-repo-check \
  --json \
  --output-last-message "$OUT_LAST" \
  --sandbox "$POC_CODEX_SANDBOX" \
  -C "$ROOT_DIR" \
  -c "model=\"$MOCK_MODEL\"" \
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
