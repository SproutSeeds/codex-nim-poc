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
: "${POC_CODEX_BIN:=codex}"
: "${POC_CODEX_HOME:=/tmp/codex-nim-poc-home}"
: "${POC_CODEX_MINIMAL_PROFILE:=0}"
: "${POC_CODEX_RUN_ROOT:=}"
: "${POC_CODEX_EPHEMERAL:=0}"
: "${SHIM_SKIP_TUNNEL_SETUP:=0}"
: "${SHIM_PREWARM_TOOL_PATH:=0}"
: "${SHIM_PREWARM_REQUEST_JSON:=}"
: "${SHIM_PREWARM_REQUEST_MAX_TIME_SECONDS:=300}"
: "${SHIM_RESTART_REMOTE_NIM:=0}"
: "${SHIM_REMOTE_CONTAINER_NAME:=nim-nano-8b-vllm}"
: "${SHIM_READY_TIMEOUT_SECONDS:=180}"

STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-codex-shim}"
mkdir -p "$ARTIFACT_DIR"

if [[ "${POC_CODEX_MINIMAL_PROFILE}" =~ ^(1|true|yes|on)$ ]]; then
  if [[ -z "${CODEX_HOME:-}" ]] && [[ "${POC_CODEX_HOME}" == "/tmp/codex-nim-poc-home" ]]; then
    POC_CODEX_HOME="$ARTIFACT_DIR/codex-home"
  fi
  if [[ -z "${POC_CODEX_RUN_ROOT}" ]]; then
    POC_CODEX_RUN_ROOT="$ARTIFACT_DIR/minimal-root"
  fi
  POC_CODEX_EPHEMERAL=1
fi

mkdir -p "$POC_CODEX_HOME"
export CODEX_HOME="${CODEX_HOME:-$POC_CODEX_HOME}"

CODEX_RUN_ROOT="${POC_CODEX_RUN_ROOT:-$ROOT_DIR}"
mkdir -p "$CODEX_RUN_ROOT"

EPHEMERAL_ARG=()
if [[ "${POC_CODEX_EPHEMERAL}" =~ ^(1|true|yes|on)$ ]]; then
  EPHEMERAL_ARG+=(--ephemeral)
fi

TUNNEL_PORT="${SHIM_TUNNEL_PORT:-8001}"
SHIM_PORT="${SHIM_PORT:-8011}"
UPSTREAM_BASE_URL="${SHIM_UPSTREAM_BASE_URL:-http://127.0.0.1:${TUNNEL_PORT}/v1}"
OUT_JSON="$ARTIFACT_DIR/codex-exec.jsonl"
OUT_LAST="$ARTIFACT_DIR/last-message.txt"
SHIM_LOG="$ARTIFACT_DIR/nim-responses-shim.log"
RUN_INFO="$ARTIFACT_DIR/codex-run-info.txt"

{
  printf 'codex_home=%s\n' "$CODEX_HOME"
  printf 'codex_run_root=%s\n' "$CODEX_RUN_ROOT"
  printf 'codex_minimal_profile=%s\n' "$POC_CODEX_MINIMAL_PROFILE"
  printf 'codex_ephemeral=%s\n' "$POC_CODEX_EPHEMERAL"
  printf 'shim_prewarm_request_json=%s\n' "$SHIM_PREWARM_REQUEST_JSON"
  printf 'shim_prewarm_request_max_time_seconds=%s\n' "$SHIM_PREWARM_REQUEST_MAX_TIME_SECONDS"
  printf 'shim_restart_remote_nim=%s\n' "$SHIM_RESTART_REMOTE_NIM"
  printf 'shim_remote_container_name=%s\n' "$SHIM_REMOTE_CONTAINER_NAME"
} >"$RUN_INFO"

wait_for_ready() {
  local url="$1"
  local label="$2"
  local timeout_seconds="${3:-180}"
  local waited=0

  until curl --fail --silent --show-error "$url" >/dev/null 2>&1; do
    if (( waited >= timeout_seconds )); then
      printf '%s did not become ready within %ss\n' "$label" "$timeout_seconds" >&2
      return 1
    fi
    sleep 2
    waited=$(( waited + 2 ))
  done
}

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

if [[ ! "${SHIM_SKIP_TUNNEL_SETUP}" =~ ^(1|true|yes|on)$ ]]; then
  ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/tmp/umbra_known_hosts \
    -i ~/.ssh/collab_umbra \
    -L "${TUNNEL_PORT}:127.0.0.1:8000" \
    -N \
    codyr@192.168.1.162 &
  TUNNEL_PID=$!

  sleep 1
fi

if [[ "${SHIM_RESTART_REMOTE_NIM}" =~ ^(1|true|yes|on)$ ]]; then
  ssh -o UpdateHostKeys=no \
    -i /Users/codymitchell/.ssh/collab_umbra \
    codyr@192.168.1.162 \
    "wsl.exe -u root -e sh -lc \"docker restart ${SHIM_REMOTE_CONTAINER_NAME} >/dev/null\""
fi

wait_for_ready "$UPSTREAM_BASE_URL/health/ready" "upstream NIM" "$SHIM_READY_TIMEOUT_SECONDS"

if [[ "${SHIM_PREWARM_TOOL_PATH}" =~ ^(1|true|yes|on)$ ]]; then
  PREWARM_BASE_URL="$UPSTREAM_BASE_URL" \
  PREWARM_MODEL="$SELF_HOSTED_NIM_MODEL" \
  PREWARM_EXTRA_BODY_JSON="${NIM_CHAT_EXTRA_BODY_JSON:-}" \
  PREWARM_ARTIFACT_DIR="$ARTIFACT_DIR/prewarm-tool-path" \
  bash "$ROOT_DIR/scripts/prewarm-self-hosted-tool-path.sh"
fi

if [[ -n "${SHIM_PREWARM_REQUEST_JSON}" ]]; then
  if [[ ! -f "${SHIM_PREWARM_REQUEST_JSON}" ]]; then
    printf 'prewarm request json not found: %s\n' "${SHIM_PREWARM_REQUEST_JSON}" >&2
    exit 1
  fi

  PREWARM_REQUEST_DIR="$ARTIFACT_DIR/prewarm-exact-request"
  mkdir -p "$PREWARM_REQUEST_DIR"
  PREWARM_REQUEST_HEADERS="$PREWARM_REQUEST_DIR/response-headers.txt"
  PREWARM_REQUEST_RESPONSE="$PREWARM_REQUEST_DIR/response.json"
  PREWARM_REQUEST_STDERR="$PREWARM_REQUEST_DIR/curl-stderr.txt"
  PREWARM_REQUEST_SUMMARY="$PREWARM_REQUEST_DIR/summary.txt"

  set +e
  PREWARM_REQUEST_WRITEOUT="$(
    curl -sS \
      --max-time "$SHIM_PREWARM_REQUEST_MAX_TIME_SECONDS" \
      -o "$PREWARM_REQUEST_RESPONSE" \
      -D "$PREWARM_REQUEST_HEADERS" \
      -w '%{http_code} %{time_total}' \
      -H 'content-type: application/json' \
      --data @"$SHIM_PREWARM_REQUEST_JSON" \
      "$UPSTREAM_BASE_URL/chat/completions" \
      2>"$PREWARM_REQUEST_STDERR"
  )"
  PREWARM_REQUEST_EXIT=$?
  set -e

  PREWARM_REQUEST_HTTP_CODE=""
  PREWARM_REQUEST_TIME_TOTAL=""
  if [[ -n "$PREWARM_REQUEST_WRITEOUT" ]]; then
    PREWARM_REQUEST_HTTP_CODE="${PREWARM_REQUEST_WRITEOUT%% *}"
    PREWARM_REQUEST_TIME_TOTAL="${PREWARM_REQUEST_WRITEOUT#* }"
  fi

  {
    printf 'request_json=%s\n' "$SHIM_PREWARM_REQUEST_JSON"
    printf 'max_time_seconds=%s\n' "$SHIM_PREWARM_REQUEST_MAX_TIME_SECONDS"
    printf 'prewarm_request_exit=%s\n' "$PREWARM_REQUEST_EXIT"
    printf 'prewarm_request_http_code=%s\n' "$PREWARM_REQUEST_HTTP_CODE"
    printf 'prewarm_request_time_total=%s\n' "$PREWARM_REQUEST_TIME_TOTAL"
    printf 'response_headers=%s\n' "$PREWARM_REQUEST_HEADERS"
    printf 'response_body=%s\n' "$PREWARM_REQUEST_RESPONSE"
    printf 'stderr=%s\n' "$PREWARM_REQUEST_STDERR"
  } >"$PREWARM_REQUEST_SUMMARY"

  if [[ "$PREWARM_REQUEST_EXIT" -ne 0 ]]; then
    cat "$PREWARM_REQUEST_SUMMARY" >&2
    exit "$PREWARM_REQUEST_EXIT"
  fi
fi

ARTIFACT_DIR="$ARTIFACT_DIR" \
SHIM_PORT="$SHIM_PORT" \
SHIM_UPSTREAM_BASE_URL="$UPSTREAM_BASE_URL" \
SHIM_MODEL="$SELF_HOSTED_NIM_MODEL" \
node "$ROOT_DIR/scripts/nim-responses-shim.mjs" >"$SHIM_LOG" 2>&1 &
SHIM_PID=$!

sleep 1

wait_for_ready "http://127.0.0.1:${SHIM_PORT}/v1/health/ready" "local shim" "$SHIM_READY_TIMEOUT_SECONDS"

"$POC_CODEX_BIN" exec \
  --skip-git-repo-check \
  --json \
  "${EPHEMERAL_ARG[@]}" \
  --output-last-message "$OUT_LAST" \
  --sandbox "$POC_CODEX_SANDBOX" \
  -C "$CODEX_RUN_ROOT" \
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
printf 'run_info_file=%s\n' "$RUN_INFO"
