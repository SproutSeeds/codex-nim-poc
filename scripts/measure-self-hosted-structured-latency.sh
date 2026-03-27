#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

REQUEST_JSON="${1:-${MEASURE_REQUEST_JSON:-}}"
if [[ -z "$REQUEST_JSON" ]]; then
  printf 'usage: %s <request-json>\n' "$0" >&2
  printf 'or set MEASURE_REQUEST_JSON=/abs/path/to/request.json\n' >&2
  exit 1
fi

if [[ ! -f "$REQUEST_JSON" ]]; then
  printf 'request json not found: %s\n' "$REQUEST_JSON" >&2
  exit 1
fi

: "${MEASURE_TUNNEL_PORT:=8001}"
: "${MEASURE_SKIP_TUNNEL_SETUP:=0}"
: "${MEASURE_BASE_URL:=http://127.0.0.1:${MEASURE_TUNNEL_PORT}/v1}"
: "${MEASURE_READY_TIMEOUT_SECONDS:=180}"
: "${MEASURE_MAX_TIME_SECONDS:=120}"
: "${MEASURE_RESTART_REMOTE_NIM:=0}"
: "${MEASURE_REMOTE_CONTAINER_NAME:=nim-nano-8b-vllm}"
: "${MEASURE_PREWARM_TOOL_PATH:=0}"
: "${MEASURE_PREWARM_EXACT_REQUEST:=0}"
: "${MEASURE_PREWARM_MAX_TIME_SECONDS:=300}"
: "${SELF_HOSTED_NIM_MODEL:=meta/llama-3.1-8b-instruct}"

STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${MEASURE_ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-structured-latency}"
mkdir -p "$ARTIFACT_DIR"

HEADERS_FILE="$ARTIFACT_DIR/response-headers.txt"
RESPONSE_FILE="$ARTIFACT_DIR/response.json"
STDERR_FILE="$ARTIFACT_DIR/curl-stderr.txt"
SUMMARY_FILE="$ARTIFACT_DIR/summary.txt"

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
  if [[ -n "${TUNNEL_PID:-}" ]] && kill -0 "$TUNNEL_PID" >/dev/null 2>&1; then
    kill "$TUNNEL_PID" >/dev/null 2>&1 || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! "${MEASURE_SKIP_TUNNEL_SETUP}" =~ ^(1|true|yes|on)$ ]]; then
  ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/tmp/umbra_known_hosts \
    -i ~/.ssh/collab_umbra \
    -L "${MEASURE_TUNNEL_PORT}:127.0.0.1:8000" \
    -N \
    codyr@192.168.1.162 &
  TUNNEL_PID=$!
  sleep 1
fi

if [[ "${MEASURE_RESTART_REMOTE_NIM}" =~ ^(1|true|yes|on)$ ]]; then
  ssh -o UpdateHostKeys=no \
    -i /Users/codymitchell/.ssh/collab_umbra \
    codyr@192.168.1.162 \
    "wsl.exe -u root -e sh -lc \"docker restart ${MEASURE_REMOTE_CONTAINER_NAME} >/dev/null\""
fi

wait_for_ready "$MEASURE_BASE_URL/health/ready" "upstream NIM" "$MEASURE_READY_TIMEOUT_SECONDS"

if [[ "${MEASURE_PREWARM_TOOL_PATH}" =~ ^(1|true|yes|on)$ ]]; then
  PREWARM_BASE_URL="$MEASURE_BASE_URL" \
  PREWARM_MODEL="$SELF_HOSTED_NIM_MODEL" \
  PREWARM_EXTRA_BODY_JSON="${NIM_CHAT_EXTRA_BODY_JSON:-}" \
  PREWARM_ARTIFACT_DIR="$ARTIFACT_DIR/prewarm-tool-path" \
  bash "$ROOT_DIR/scripts/prewarm-self-hosted-tool-path.sh"
fi

PREWARM_REQUEST_EXIT=""
PREWARM_REQUEST_HTTP_CODE=""
PREWARM_REQUEST_TIME_TOTAL=""

if [[ "${MEASURE_PREWARM_EXACT_REQUEST}" =~ ^(1|true|yes|on)$ ]]; then
  PREWARM_REQUEST_DIR="$ARTIFACT_DIR/prewarm-exact-request"
  mkdir -p "$PREWARM_REQUEST_DIR"
  PREWARM_REQUEST_HEADERS="$PREWARM_REQUEST_DIR/response-headers.txt"
  PREWARM_REQUEST_RESPONSE="$PREWARM_REQUEST_DIR/response.json"
  PREWARM_REQUEST_STDERR="$PREWARM_REQUEST_DIR/curl-stderr.txt"

  set +e
  PREWARM_REQUEST_WRITEOUT="$(
    curl -sS \
      --max-time "$MEASURE_PREWARM_MAX_TIME_SECONDS" \
      -o "$PREWARM_REQUEST_RESPONSE" \
      -D "$PREWARM_REQUEST_HEADERS" \
      -w '%{http_code} %{time_total}' \
      -H 'content-type: application/json' \
      --data @"$REQUEST_JSON" \
      "$MEASURE_BASE_URL/chat/completions" \
      2>"$PREWARM_REQUEST_STDERR"
  )"
  PREWARM_REQUEST_EXIT=$?
  set -e

  if [[ -n "$PREWARM_REQUEST_WRITEOUT" ]]; then
    PREWARM_REQUEST_HTTP_CODE="${PREWARM_REQUEST_WRITEOUT%% *}"
    PREWARM_REQUEST_TIME_TOTAL="${PREWARM_REQUEST_WRITEOUT#* }"
  fi
fi

START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
CURL_WRITEOUT="$(
  curl -sS \
    --max-time "$MEASURE_MAX_TIME_SECONDS" \
    -o "$RESPONSE_FILE" \
    -D "$HEADERS_FILE" \
    -w '%{http_code} %{time_total}' \
    -H 'content-type: application/json' \
    --data @"$REQUEST_JSON" \
    "$MEASURE_BASE_URL/chat/completions" \
    2>"$STDERR_FILE"
)"
CURL_EXIT=$?
set -e
END_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

HTTP_CODE=""
TIME_TOTAL=""
if [[ -n "$CURL_WRITEOUT" ]]; then
  HTTP_CODE="${CURL_WRITEOUT%% *}"
  TIME_TOTAL="${CURL_WRITEOUT#* }"
fi

{
  printf 'request_json=%s\n' "$REQUEST_JSON"
  printf 'measure_base_url=%s\n' "$MEASURE_BASE_URL"
  printf 'restart_remote_nim=%s\n' "$MEASURE_RESTART_REMOTE_NIM"
  printf 'prewarm_tool_path=%s\n' "$MEASURE_PREWARM_TOOL_PATH"
  printf 'prewarm_exact_request=%s\n' "$MEASURE_PREWARM_EXACT_REQUEST"
  printf 'prewarm_max_time_seconds=%s\n' "$MEASURE_PREWARM_MAX_TIME_SECONDS"
  printf 'prewarm_request_exit=%s\n' "$PREWARM_REQUEST_EXIT"
  printf 'prewarm_request_http_code=%s\n' "$PREWARM_REQUEST_HTTP_CODE"
  printf 'prewarm_request_time_total=%s\n' "$PREWARM_REQUEST_TIME_TOTAL"
  printf 'max_time_seconds=%s\n' "$MEASURE_MAX_TIME_SECONDS"
  printf 'curl_exit=%s\n' "$CURL_EXIT"
  printf 'http_code=%s\n' "$HTTP_CODE"
  printf 'time_total=%s\n' "$TIME_TOTAL"
  printf 'start_utc=%s\n' "$START_TS"
  printf 'end_utc=%s\n' "$END_TS"
  printf 'response_headers=%s\n' "$HEADERS_FILE"
  printf 'response_body=%s\n' "$RESPONSE_FILE"
  printf 'stderr=%s\n' "$STDERR_FILE"
} >"$SUMMARY_FILE"

printf 'artifacts=%s\n' "$ARTIFACT_DIR"
cat "$SUMMARY_FILE"
