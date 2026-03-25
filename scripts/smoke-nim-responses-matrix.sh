#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

: "${NVIDIA_API_KEY:?set NVIDIA_API_KEY}"

BASE_URL="${NIM_BASE_URL:-https://integrate.api.nvidia.com/v1}"
PROMPT="${NIM_PROMPT:-Reply with the single word OK.}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-responses-matrix}"
mkdir -p "$ARTIFACT_DIR"

MODELS_CSV="${NIM_MODELS_CSV:-nvidia/nemotron-3-super-120b-a12b,nvidia/llama-3.3-nemotron-super-49b-v1}"

IFS=',' read -r -a models <<< "$MODELS_CSV"

summary="$ARTIFACT_DIR/summary.txt"
: > "$summary"

for model in "${models[@]}"; do
  safe_model="$(printf '%s' "$model" | tr '/:.' '___')"
  request_json="$ARTIFACT_DIR/${safe_model}.request.json"
  headers_txt="$ARTIFACT_DIR/${safe_model}.headers.txt"
  body_json="$ARTIFACT_DIR/${safe_model}.body.json"

  jq -n \
    --arg model "$model" \
    --arg input "$PROMPT" \
    '{
      model: $model,
      input: $input,
      max_output_tokens: 64,
      stream: false
    }' > "$request_json"

  status="$(
    curl -sS \
      -D "$headers_txt" \
      -o "$body_json" \
      -w '%{http_code}' \
      -H "Authorization: Bearer $NVIDIA_API_KEY" \
      -H 'Content-Type: application/json' \
      -d @"$request_json" \
      "$BASE_URL/responses"
  )"

  printf '%s responses_status=%s\n' "$model" "$status" | tee -a "$summary"
done

printf 'artifacts=%s\n' "$ARTIFACT_DIR" | tee -a "$summary"
