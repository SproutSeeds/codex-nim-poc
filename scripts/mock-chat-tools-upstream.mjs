#!/usr/bin/env node

import http from "node:http";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const port = Number(process.env.MOCK_UPSTREAM_PORT || 8021);
const artifactDir = process.env.ARTIFACT_DIR || process.cwd();
const modelId = process.env.MOCK_MODEL || "mock-nvidia-nim";
const callId = process.env.MOCK_TOOL_CALL_ID || "mock-call-1";
const command = process.env.MOCK_TOOL_COMMAND || "printf shim-tool-ok";

mkdirSync(artifactDir, { recursive: true });

let requestCounter = 0;

function writeArtifact(name, value) {
  const file = join(artifactDir, name);
  const serialized = typeof value === "string" ? value : JSON.stringify(value, null, 2);
  writeFileSync(file, serialized);
}

function nextRequestId() {
  requestCounter += 1;
  return String(requestCounter).padStart(4, "0");
}

function jsonHeaders(status = 200) {
  return {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
    },
  };
}

function extractTextContent(value) {
  if (typeof value === "string") {
    return value;
  }
  if (!Array.isArray(value)) {
    return "";
  }
  return value
    .map((item) => {
      if (!item || typeof item !== "object") {
        return "";
      }
      if (typeof item.text === "string") {
        return item.text;
      }
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function normalizeToolResultContent(value) {
  const text = extractTextContent(value).trim();
  if (!text) {
    return "shim-tool-ok";
  }

  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object" && typeof parsed.output === "string") {
      return parsed.output.trim() || "shim-tool-ok";
    }
  } catch {
    // Fall through to plain-text heuristics.
  }

  const outputMarker = "\nOutput:\n";
  const outputIndex = text.lastIndexOf(outputMarker);
  if (outputIndex !== -1) {
    const outputText = text.slice(outputIndex + outputMarker.length).trim();
    if (outputText) {
      return outputText;
    }
  }

  const lines = text.split("\n").map((line) => line.trim()).filter(Boolean);
  return lines.at(-1) || "shim-tool-ok";
}

const server = http.createServer(async (req, res) => {
  if (!req.url) {
    res.writeHead(400, jsonHeaders(400).headers);
    res.end(JSON.stringify({ error: "missing url" }));
    return;
  }

  if (req.method === "GET" && req.url === "/v1/health/ready") {
    res.writeHead(200, jsonHeaders(200).headers);
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  if (req.method === "GET" && req.url === "/v1/models") {
    res.writeHead(200, jsonHeaders(200).headers);
    res.end(JSON.stringify({ object: "list", data: [{ id: modelId, object: "model" }] }));
    return;
  }

  if (req.method === "GET" && req.url === "/shutdown") {
    res.writeHead(200, jsonHeaders(200).headers);
    res.end(JSON.stringify({ ok: true }));
    setTimeout(() => server.close(() => process.exit(0)), 50);
    return;
  }

  if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
    res.writeHead(404, jsonHeaders(404).headers);
    res.end(JSON.stringify({ detail: "Not Found" }));
    return;
  }

  const bodyChunks = [];
  for await (const chunk of req) {
    bodyChunks.push(chunk);
  }

  const requestId = nextRequestId();
  const rawBody = Buffer.concat(bodyChunks).toString("utf8");
  writeArtifact(`${requestId}-mock-chat-request.json`, rawBody);

  let body;
  try {
    body = JSON.parse(rawBody);
  } catch (error) {
    res.writeHead(400, jsonHeaders(400).headers);
    res.end(JSON.stringify({ error: `invalid JSON: ${String(error)}` }));
    return;
  }

  const toolMessage = (body.messages || []).find(
    (message) => message?.role === "tool" && message?.tool_call_id === callId,
  );

  let responseBody;
  if (toolMessage) {
    responseBody = {
      id: `mock-chat-${requestId}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: body.model || modelId,
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: normalizeToolResultContent(toolMessage.content),
          },
          finish_reason: "stop",
        },
      ],
      usage: {
        prompt_tokens: 100,
        completion_tokens: 3,
        total_tokens: 103,
      },
    };
  } else {
    responseBody = {
      id: `mock-chat-${requestId}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: body.model || modelId,
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: null,
            tool_calls: [
              {
                id: callId,
                type: "function",
                function: {
                  name: "exec_command",
                  arguments: JSON.stringify({ cmd: command }),
                },
              },
            ],
          },
          finish_reason: "tool_calls",
        },
      ],
      usage: {
        prompt_tokens: 100,
        completion_tokens: 10,
        total_tokens: 110,
      },
    };
  }

  writeArtifact(`${requestId}-mock-chat-response.json`, responseBody);
  res.writeHead(200, jsonHeaders(200).headers);
  res.end(JSON.stringify(responseBody));
});

server.listen(port, "127.0.0.1", () => {
  writeArtifact("mock-chat-tools-server-info.json", { port, modelId, callId, command });
  console.error(`mock-chat-tools-upstream listening on 127.0.0.1:${port}`);
});
