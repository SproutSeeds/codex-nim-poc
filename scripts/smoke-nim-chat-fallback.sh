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
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-chat}"
mkdir -p "$ARTIFACT_DIR"

base_request="$ARTIFACT_DIR/chat-request.json"
extra_request="$ARTIFACT_DIR/chat-request-force-nonempty.json"

jq -n \
  --arg model "$NIM_MODEL" \
  --arg prompt "$PROMPT" \
  '{
    model: $model,
    messages: [{ role: "user", content: $prompt }],
    max_tokens: 32,
    stream: false
  }' > "$base_request"

jq '. + { chat_template_kwargs: { force_nonempty_content: true } }' \
  "$base_request" > "$extra_request"

base_status="$(
  curl -sS \
    -D "$ARTIFACT_DIR/chat.headers.txt" \
    -o "$ARTIFACT_DIR/chat.body.json" \
    -w '%{http_code}' \
    -H "Authorization: Bearer $NVIDIA_API_KEY" \
    -H 'Content-Type: application/json' \
    -d @"$base_request" \
    "$BASE_URL/chat/completions"
)"

extra_status="$(
  curl -sS \
    -D "$ARTIFACT_DIR/chat-extra.headers.txt" \
    -o "$ARTIFACT_DIR/chat-extra.body.json" \
    -w '%{http_code}' \
    -H "Authorization: Bearer $NVIDIA_API_KEY" \
    -H 'Content-Type: application/json' \
    -d @"$extra_request" \
    "$BASE_URL/chat/completions"
)"

base_content_null="$(jq -r '.choices[0].message.content == null' "$ARTIFACT_DIR/chat.body.json" 2>/dev/null || echo unknown)"
extra_content_null="$(jq -r '.choices[0].message.content == null' "$ARTIFACT_DIR/chat-extra.body.json" 2>/dev/null || echo unknown)"

{
  printf 'chat_status=%s\n' "$base_status"
  printf 'chat_content_null=%s\n' "$base_content_null"
  printf 'chat_extra_status=%s\n' "$extra_status"
  printf 'chat_extra_content_null=%s\n' "$extra_content_null"
  printf 'artifacts=%s\n' "$ARTIFACT_DIR"
} | tee "$ARTIFACT_DIR/summary.txt"

if [[ "$base_status" -lt 200 || "$base_status" -ge 300 ]]; then
  echo "Base chat/completions request failed." >&2
  exit 1
fi

if [[ "$extra_status" -lt 200 || "$extra_status" -ge 300 ]]; then
  echo "force_nonempty_content chat/completions request failed." >&2
  exit 1
fi

echo "Chat fallback smoke passed."
