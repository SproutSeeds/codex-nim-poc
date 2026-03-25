#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

: "${SELF_HOSTED_NIM_BASE_URL:=http://127.0.0.1:8000/v1}"
: "${SELF_HOSTED_NIM_PROMPT:=Reply with the single word OK.}"

STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-self-hosted}"
mkdir -p "$ARTIFACT_DIR"

READY_URL="${SELF_HOSTED_NIM_BASE_URL%/v1}/v1/health/ready"

ready_status="$(
  curl -sS \
    -D "$ARTIFACT_DIR/ready.headers.txt" \
    -o "$ARTIFACT_DIR/ready.body.txt" \
    -w '%{http_code}' \
    "$READY_URL"
)"

models_status="$(
  curl -sS \
    -D "$ARTIFACT_DIR/models.headers.txt" \
    -o "$ARTIFACT_DIR/models.body.json" \
    -w '%{http_code}' \
    "$SELF_HOSTED_NIM_BASE_URL/models"
)"

model_id="$(
  jq -r '.data[0].id // empty' "$ARTIFACT_DIR/models.body.json" 2>/dev/null || true
)"

if [[ -z "$model_id" ]]; then
  model_id="${SELF_HOSTED_NIM_MODEL:-}"
fi

if [[ -z "$model_id" ]]; then
  echo "Could not determine a model id from /v1/models and SELF_HOSTED_NIM_MODEL is unset." >&2
  exit 1
fi

jq -n \
  --arg model "$model_id" \
  --arg input "$SELF_HOSTED_NIM_PROMPT" \
  '{
    model: $model,
    input: $input,
    max_output_tokens: 64,
    stream: false
  }' > "$ARTIFACT_DIR/responses.request.json"

responses_status="$(
  curl -sS \
    -D "$ARTIFACT_DIR/responses.headers.txt" \
    -o "$ARTIFACT_DIR/responses.body.json" \
    -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d @"$ARTIFACT_DIR/responses.request.json" \
    "$SELF_HOSTED_NIM_BASE_URL/responses"
)"

{
  printf 'ready_status=%s\n' "$ready_status"
  printf 'models_status=%s\n' "$models_status"
  printf 'model_id=%s\n' "$model_id"
  printf 'responses_status=%s\n' "$responses_status"
  printf 'artifacts=%s\n' "$ARTIFACT_DIR"
} | tee "$ARTIFACT_DIR/summary.txt"

if [[ "$ready_status" -lt 200 || "$ready_status" -ge 300 ]]; then
  echo "Self-hosted NIM readiness check failed." >&2
  exit 1
fi

if [[ "$models_status" -lt 200 || "$models_status" -ge 300 ]]; then
  echo "Self-hosted /v1/models check failed." >&2
  exit 1
fi

if [[ "$responses_status" -lt 200 || "$responses_status" -ge 300 ]]; then
  echo "Self-hosted /v1/responses check failed." >&2
  exit 1
fi

echo "Self-hosted NIM smoke passed."
