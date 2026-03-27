#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

: "${PREWARM_BASE_URL:=http://127.0.0.1:8000/v1}"
: "${PREWARM_MODEL:=meta/llama-3.1-8b-instruct}"
: "${PREWARM_TOOL_NAME:=exec_command}"
: "${PREWARM_TOOL_CMD_A:=printf shim-tool-a}"
: "${PREWARM_TOOL_CMD_B:=printf shim-tool-b}"
: "${PREWARM_EXTRA_BODY_JSON:=${NIM_CHAT_EXTRA_BODY_JSON:-}}"

STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${PREWARM_ARTIFACT_DIR:-$ROOT_DIR/artifacts/$STAMP-prewarm-tool-path}"
mkdir -p "$ARTIFACT_DIR"

REQ1="$ARTIFACT_DIR/0001-request.json"
REQ2="$ARTIFACT_DIR/0002-request.json"
RESP1="$ARTIFACT_DIR/0001-response.json"
RESP2="$ARTIFACT_DIR/0002-response.json"
HEAD1="$ARTIFACT_DIR/0001-headers.txt"
HEAD2="$ARTIFACT_DIR/0002-headers.txt"

node - "$REQ1" "$REQ2" <<'NODE'
const fs = require("node:fs");

const [req1Path, req2Path] = process.argv.slice(2);
const model = process.env.PREWARM_MODEL || "meta/llama-3.1-8b-instruct";
const toolName = process.env.PREWARM_TOOL_NAME || "exec_command";
const cmdA = process.env.PREWARM_TOOL_CMD_A || "printf shim-tool-a";
const cmdB = process.env.PREWARM_TOOL_CMD_B || "printf shim-tool-b";
const extraBodyJson = process.env.PREWARM_EXTRA_BODY_JSON || "";

function mergeObject(target, extra) {
  if (!extra || typeof extra !== "object" || Array.isArray(extra)) {
    return target;
  }
  for (const [key, value] of Object.entries(extra)) {
    if (
      value &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      target[key] &&
      typeof target[key] === "object" &&
      !Array.isArray(target[key])
    ) {
      mergeObject(target[key], value);
    } else {
      target[key] = value;
    }
  }
  return target;
}

const tool = {
  type: "function",
  function: {
    name: toolName,
    description: "Shell command to execute.",
    parameters: {
      type: "object",
      properties: {
        cmd: {
          type: "string",
          description: "Shell command to execute.",
        },
      },
      required: ["cmd"],
      additionalProperties: false,
    },
  },
};

const firstRequest = {
  model,
  messages: [
    {
      role: "user",
      content: `Call the ${toolName} tool exactly once. Run \`${cmdA}\`. Do not answer in plain text.`,
    },
  ],
  stream: false,
  tools: [tool],
  tool_choice: {
    type: "function",
    function: {
      name: toolName,
    },
  },
  parallel_tool_calls: false,
};

const secondRequest = {
  model,
  messages: [
    {
      role: "user",
      content: `Call the ${toolName} tool exactly once. Run \`${cmdA}\`. Do not answer in plain text.`,
    },
    {
      role: "assistant",
      content: null,
      tool_calls: [
        {
          id: "prewarm_tool_call_a",
          type: "function",
          function: {
            name: toolName,
            arguments: JSON.stringify({ cmd: cmdA }),
          },
        },
      ],
    },
    {
      role: "tool",
      tool_call_id: "prewarm_tool_call_a",
      content: cmdA.replace(/^printf /, ""),
    },
    {
      role: "user",
      content: `Now call the ${toolName} tool exactly once with \`${cmdB}\`. Do not answer in plain text.`,
    },
  ],
  stream: false,
  tools: [tool],
  parallel_tool_calls: false,
};

if (extraBodyJson.trim()) {
  const extra = JSON.parse(extraBodyJson);
  mergeObject(firstRequest, extra);
  mergeObject(secondRequest, extra);
}

fs.writeFileSync(req1Path, JSON.stringify(firstRequest, null, 2));
fs.writeFileSync(req2Path, JSON.stringify(secondRequest, null, 2));
NODE

status1="$(curl -sS -o "$RESP1" -D "$HEAD1" -w '%{http_code}' -H 'content-type: application/json' --data @"$REQ1" "$PREWARM_BASE_URL/chat/completions")"
status2="$(curl -sS -o "$RESP2" -D "$HEAD2" -w '%{http_code}' -H 'content-type: application/json' --data @"$REQ2" "$PREWARM_BASE_URL/chat/completions")"

node - "$RESP1" "$RESP2" "$status1" "$status2" <<'NODE'
const fs = require("node:fs");

const [resp1Path, resp2Path, status1, status2] = process.argv.slice(2);

function parse(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

const resp1 = parse(resp1Path);
const resp2 = parse(resp2Path);
assert(status1 === "200", `first prewarm request returned ${status1}`);
assert(status2 === "200", `second prewarm request returned ${status2}`);

const toolCall1 = resp1?.choices?.[0]?.message?.tool_calls?.[0];
assert(toolCall1?.function?.name === "exec_command", "first prewarm response did not return exec_command tool call");
assert((toolCall1?.function?.arguments || "").includes("shim-tool-a"), "first prewarm response did not request shim-tool-a");

const toolCall2 = resp2?.choices?.[0]?.message?.tool_calls?.[0];
const content2 = resp2?.choices?.[0]?.message?.content || "";
const secondTurnOk =
  ((toolCall2?.function?.name === "exec_command") &&
    (toolCall2?.function?.arguments || "").includes("shim-tool-b")) ||
  (typeof content2 === "string" &&
    content2.includes("\"name\": \"exec_command\"") &&
    content2.includes("shim-tool-b"));
assert(secondTurnOk, "second prewarm response did not request shim-tool-b in tool-call or pseudo-tool-call form");
NODE

printf 'prewarm_artifacts=%s\n' "$ARTIFACT_DIR"
