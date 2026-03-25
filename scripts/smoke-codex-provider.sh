#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

: "${NVIDIA_API_KEY:?set NVIDIA_API_KEY}"
: "${NIM_MODEL:=nvidia/nemotron-3-super}"

BASE_URL="${NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}"
PROMPT="${NIM_PROMPT:-Reply with the single word OK.}"
SANDBOX_MODE="${CODEX_SANDBOX:-read-only}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-codex}"
mkdir -p "$ARTIFACT_DIR"

OUT_JSON="$ARTIFACT_DIR/codex-exec.jsonl"
OUT_LAST="$ARTIFACT_DIR/last-message.txt"

codex exec \
  --skip-git-repo-check \
  --json \
  --output-last-message "$OUT_LAST" \
  --sandbox "$SANDBOX_MODE" \
  -C "$ROOT_DIR" \
  -c "model=\"$NIM_MODEL\"" \
  -c 'model_provider="nvidia_nim"' \
  -c 'model_providers.nvidia_nim.name="NVIDIA NIM"' \
  -c "model_providers.nvidia_nim.base_url=\"$BASE_URL\"" \
  -c 'model_providers.nvidia_nim.env_key="NVIDIA_API_KEY"' \
  -c 'model_providers.nvidia_nim.wire_api="responses"' \
  -c 'model_providers.nvidia_nim.supports_websockets=false' \
  -c 'model_providers.nvidia_nim.request_max_retries=2' \
  -c 'model_providers.nvidia_nim.stream_max_retries=4' \
  -c 'model_providers.nvidia_nim.stream_idle_timeout_ms=600000' \
  "$PROMPT" | tee "$OUT_JSON"

printf 'artifacts=%s\n' "$ARTIFACT_DIR"
printf 'last_message_file=%s\n' "$OUT_LAST"
