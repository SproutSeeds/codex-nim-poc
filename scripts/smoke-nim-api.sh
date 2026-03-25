#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

: "${NVIDIA_API_KEY:?set NVIDIA_API_KEY}"
: "${NIM_MODEL:=nvidia/nemotron-3-super-120b-a12b}"

BASE_URL="${NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}"
PROMPT="${NIM_PROMPT:-Reply with the single word OK.}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP}"
mkdir -p "$ARTIFACT_DIR"

MODELS_BODY="$ARTIFACT_DIR/models.body.json"
MODELS_HEADERS="$ARTIFACT_DIR/models.headers.txt"
RESPONSES_HEADERS="$ARTIFACT_DIR/responses.headers.txt"
RESPONSES_BODY="$ARTIFACT_DIR/responses.body.json"
REQUEST_JSON="$ARTIFACT_DIR/request.json"

jq -n \
  --arg model "$NIM_MODEL" \
  --arg input "$PROMPT" \
  '{
    model: $model,
    input: $input,
    max_output_tokens: 128,
    stream: false
  }' > "$REQUEST_JSON"

if [[ -n "${NIM_EXTRA_BODY_JSON:-}" ]]; then
  printf '%s\n' "$NIM_EXTRA_BODY_JSON" > "$ARTIFACT_DIR/extra-body.json"
  jq -s '.[0] * .[1]' "$REQUEST_JSON" "$ARTIFACT_DIR/extra-body.json" > "$ARTIFACT_DIR/request.merged.json"
  mv "$ARTIFACT_DIR/request.merged.json" "$REQUEST_JSON"
fi

models_status="$(
  curl -sS \
    -D "$MODELS_HEADERS" \
    -o "$MODELS_BODY" \
    -w '%{http_code}' \
    -H "Authorization: Bearer $NVIDIA_API_KEY" \
    "$BASE_URL/models"
)"

printf 'models_status=%s\n' "$models_status" | tee "$ARTIFACT_DIR/summary.txt"

responses_status="$(
  curl -sS \
    -D "$RESPONSES_HEADERS" \
    -o "$RESPONSES_BODY" \
    -w '%{http_code}' \
    -H "Authorization: Bearer $NVIDIA_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$REQUEST_JSON" \
    "$BASE_URL/responses"
)"

printf 'responses_status=%s\n' "$responses_status" | tee -a "$ARTIFACT_DIR/summary.txt"
printf 'artifacts=%s\n' "$ARTIFACT_DIR" | tee -a "$ARTIFACT_DIR/summary.txt"

if [[ "$models_status" -lt 200 || "$models_status" -ge 300 ]]; then
  echo "GET /models failed; see $MODELS_BODY and $MODELS_HEADERS" >&2
  exit 1
fi

if [[ "$responses_status" -lt 200 || "$responses_status" -ge 300 ]]; then
  echo "POST /responses failed; see $RESPONSES_BODY and $RESPONSES_HEADERS" >&2
  exit 1
fi

echo "Direct NIM smoke passed."
