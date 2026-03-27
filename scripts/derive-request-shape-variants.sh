#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'usage: %s <heavy-request.json> <small-request.json> <out-dir>\n' "$0" >&2
  exit 1
fi

HEAVY_REQUEST="$1"
SMALL_REQUEST="$2"
OUT_DIR="$3"

if [[ ! -f "$HEAVY_REQUEST" ]]; then
  printf 'heavy request not found: %s\n' "$HEAVY_REQUEST" >&2
  exit 1
fi

if [[ ! -f "$SMALL_REQUEST" ]]; then
  printf 'small request not found: %s\n' "$SMALL_REQUEST" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

cp "$HEAVY_REQUEST" "$OUT_DIR/heavy-baseline.json"

jq --slurpfile small "$SMALL_REQUEST" \
  '.messages[2].content = $small[0].messages[2].content' \
  "$HEAVY_REQUEST" >"$OUT_DIR/heavy-small-user.json"

jq --slurpfile small "$SMALL_REQUEST" '
  ($small[0].tools | map(.function.name)) as $keep
  | .tools |= map(select(.function.name as $name | $keep | index($name)))
' "$HEAVY_REQUEST" >"$OUT_DIR/heavy-small-tools.json"

jq --slurpfile small "$SMALL_REQUEST" '
  ($small[0].tools | map(.function.name)) as $keep
  | .messages[2].content = $small[0].messages[2].content
  | .tools |= map(select(.function.name as $name | $keep | index($name)))
' "$HEAVY_REQUEST" >"$OUT_DIR/heavy-small-user-small-tools.json"

for file in \
  "$OUT_DIR/heavy-baseline.json" \
  "$OUT_DIR/heavy-small-user.json" \
  "$OUT_DIR/heavy-small-tools.json" \
  "$OUT_DIR/heavy-small-user-small-tools.json"; do
  printf '== %s ==\n' "$(basename "$file")"
  jq '{
    messages_len:(.messages|length),
    tools_len:(.tools|length),
    message_lengths:(.messages|map({role, content_len:(.content|tostring|length)})),
    messages_chars:(.messages|tojson|length),
    tools_chars:(.tools|tojson|length)
  }' "$file"
done
