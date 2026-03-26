#!/usr/bin/env node

import http from "node:http";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const port = Number(process.env.SHIM_PORT || 8011);
const upstreamBaseUrl = (process.env.SHIM_UPSTREAM_BASE_URL || "http://127.0.0.1:8001/v1").replace(/\/$/, "");
const artifactDir = process.env.ARTIFACT_DIR || process.cwd();
const serverInfoPath = process.env.SHIM_SERVER_INFO_PATH || "";
const forcedModel = process.env.SHIM_MODEL || "";
const chatExtraBodyJson = process.env.NIM_CHAT_EXTRA_BODY_JSON || "";
const allowedToolNames = new Set(
  (process.env.SHIM_TOOL_ALLOWLIST || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
);
const forceSingleToolChoice = /^(1|true|yes|on)$/i.test(
  process.env.SHIM_FORCE_SINGLE_TOOL_CHOICE || "",
);

mkdirSync(artifactDir, { recursive: true });

let requestCounter = 0;
const rememberedToolCalls = new Map();

function jsonHeaders(status = 200) {
  return {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
    },
  };
}

function eventStreamHeaders() {
  return {
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    connection: "keep-alive",
    "access-control-allow-origin": "*",
  };
}

function writeArtifact(name, value) {
  const file = join(artifactDir, name);
  const serialized = typeof value === "string" ? value : JSON.stringify(value, null, 2);
  writeFileSync(file, serialized);
}

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

function extractTextSegments(content = []) {
  if (!Array.isArray(content)) {
    return [];
  }
  const texts = [];
  for (const item of content) {
    if (!item || typeof item !== "object") {
      continue;
    }
    if (typeof item.text === "string" && item.text.length > 0) {
      texts.push(item.text);
    }
  }
  return texts;
}

function extractInputTextContent(value) {
  if (typeof value === "string") {
    return value;
  }
  if (!Array.isArray(value)) {
    return "";
  }
  const texts = [];
  for (const item of value) {
    if (!item || typeof item !== "object") {
      continue;
    }
    if (item.type === "input_text" && typeof item.text === "string" && item.text.length > 0) {
      texts.push(item.text);
    }
  }
  return texts.join("\n");
}

function normalizeExecCommandTranscript(output) {
  if (typeof output !== "string" || !output.startsWith("Command: ")) {
    return null;
  }

  const exitCodeMatch = output.match(/Process exited with code (\d+)/);
  const outputMatch = output.match(/\nOutput:\n([\s\S]*)$/);
  if (!exitCodeMatch) {
    return null;
  }

  const exitCode = Number(exitCodeMatch[1]);
  const commandOutput = (outputMatch?.[1] || "").replace(/\s+$/, "");
  if (exitCode === 0) {
    return commandOutput || "(command succeeded with no output)";
  }

  if (commandOutput) {
    return `command failed (exit ${exitCode})\n${commandOutput}`;
  }

  return `command failed (exit ${exitCode})`;
}

function serializeToolOutput(output) {
  if (typeof output === "string") {
    return normalizeExecCommandTranscript(output) || output;
  }

  const extractedText = extractInputTextContent(output);
  if (extractedText) {
    return extractedText;
  }

  if (output && typeof output === "object" && typeof output.content === "string") {
    return output.content;
  }

  return JSON.stringify(output ?? null);
}

function hasPriorToolTurn(requestBody) {
  return (requestBody?.input || []).some(
    (item) =>
      item &&
      typeof item === "object" &&
      (item.type === "function_call" || item.type === "function_call_output"),
  );
}

function makeAssistantToolCallMessage(toolCalls) {
  return {
    role: "assistant",
    content: null,
    tool_calls: toolCalls.map((toolCall) => ({
      id: toolCall.id,
      type: "function",
      function: {
        name: toolCall.name,
        arguments: toolCall.arguments,
      },
    })),
  };
}

function normalizeStoredToolCall(toolCall) {
  if (!toolCall || typeof toolCall !== "object") {
    return null;
  }

  const id = typeof toolCall.id === "string" ? toolCall.id : "";
  const name = typeof toolCall.name === "string" ? toolCall.name : "";
  const argumentsText = typeof toolCall.arguments === "string" ? toolCall.arguments : "";
  if (!id || !name) {
    return null;
  }

  return {
    id,
    name,
    arguments: argumentsText,
  };
}

function normalizeResponseFunctionCall(item) {
  if (!item || typeof item !== "object") {
    return null;
  }
  const callId = typeof item.call_id === "string" ? item.call_id : "";
  const name = typeof item.name === "string" ? item.name : "";
  const argumentsText = typeof item.arguments === "string" ? item.arguments : "";
  if (!callId || !name) {
    return null;
  }
  return {
    id: callId,
    name,
    arguments: argumentsText,
  };
}

function normalizeUpstreamToolCall(toolCall) {
  if (!toolCall || typeof toolCall !== "object") {
    return null;
  }

  const id = typeof toolCall.id === "string" && toolCall.id.length > 0
    ? toolCall.id
    : `nim_tool_call_${Date.now()}_${Math.random().toString(16).slice(2, 10)}`;
  const name = typeof toolCall.function?.name === "string" ? toolCall.function.name : "";
  if (!name) {
    return null;
  }

  let argumentsText = toolCall.function?.arguments;
  if (typeof argumentsText !== "string") {
    argumentsText = JSON.stringify(argumentsText ?? {});
  }

  return {
    id,
    name,
    arguments: argumentsText,
  };
}

function toChatFunctionTool(tool) {
  if (!tool || typeof tool !== "object" || tool.type !== "function") {
    return null;
  }
  if (typeof tool.name !== "string" || tool.name.length === 0) {
    return null;
  }
  if (allowedToolNames.size > 0 && !allowedToolNames.has(tool.name)) {
    return null;
  }

  const chatTool = {
    type: "function",
    function: {
      name: tool.name,
      parameters: tool.parameters ?? {
        type: "object",
        properties: {},
        additionalProperties: true,
      },
    },
  };

  if (typeof tool.description === "string" && tool.description.length > 0) {
    chatTool.function.description = tool.description;
  }

  return chatTool;
}

function buildChatMessages(requestBody) {
  const messages = [];
  const unsupportedItems = [];
  const seenToolCallIds = new Set();
  let pendingAssistantToolCalls = [];

  function enqueueAssistantToolCall(toolCall) {
    if (!toolCall || seenToolCallIds.has(toolCall.id)) {
      return;
    }
    if (pendingAssistantToolCalls.some((pendingToolCall) => pendingToolCall.id === toolCall.id)) {
      return;
    }
    pendingAssistantToolCalls.push(toolCall);
  }

  function flushPendingAssistantToolCalls() {
    if (pendingAssistantToolCalls.length === 0) {
      return;
    }
    messages.push(makeAssistantToolCallMessage(pendingAssistantToolCalls));
    for (const toolCall of pendingAssistantToolCalls) {
      seenToolCallIds.add(toolCall.id);
    }
    pendingAssistantToolCalls = [];
  }

  if (typeof requestBody.instructions === "string" && requestBody.instructions.trim()) {
    messages.push({ role: "system", content: requestBody.instructions });
  }

  for (const item of requestBody.input || []) {
    if (!item || typeof item !== "object") {
      continue;
    }

    if (item.type === "message") {
      flushPendingAssistantToolCalls();
      const text = extractTextSegments(item.content).join("\n");
      if (text.trim()) {
        const role = normalizeChatRole(item.role);
        messages.push({ role, content: text });
      }
      continue;
    }

    if (item.type === "function_call") {
      const toolCall = normalizeResponseFunctionCall(item);
      if (!toolCall) {
        unsupportedItems.push("function_call");
        continue;
      }
      enqueueAssistantToolCall(toolCall);
      continue;
    }

    if (item.type === "function_call_output") {
      const callId = typeof item.call_id === "string" ? item.call_id : "";
      if (!callId) {
        unsupportedItems.push("function_call_output");
        continue;
      }

      if (!seenToolCallIds.has(callId)) {
        const rememberedToolCall = normalizeStoredToolCall(rememberedToolCalls.get(callId));
        if (rememberedToolCall) {
          enqueueAssistantToolCall(rememberedToolCall);
        }
      }

      flushPendingAssistantToolCalls();
      messages.push({
        role: "tool",
        tool_call_id: callId,
        content: serializeToolOutput(item.output),
      });
      continue;
    }

    unsupportedItems.push(item.type || "unknown");
  }

  flushPendingAssistantToolCalls();
  return { messages, unsupportedItems };
}

function normalizeChatRole(role) {
  if (role === "developer") {
    return "system";
  }
  if (role === "assistant" || role === "system" || role === "tool" || role === "function") {
    return role;
  }
  return "user";
}

function normalizeAssistantContent(message) {
  if (!message || typeof message !== "object") {
    return "";
  }

  if (typeof message.content === "string") {
    return message.content;
  }

  if (Array.isArray(message.content)) {
    return message.content
      .map((item) => {
        if (typeof item === "string") {
          return item;
        }
        if (item && typeof item.text === "string") {
          return item.text;
        }
        return "";
      })
      .filter(Boolean)
      .join("\n");
  }

  if (typeof message.refusal === "string" && message.refusal.length > 0) {
    return message.refusal;
  }

  return "";
}

function toSse(events) {
  return events
    .map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`)
    .join("");
}

function makeResponsesEvents({ responseId, messageId, text, toolCalls, usage }) {
  const events = [
    {
      type: "response.created",
      response: { id: responseId },
    },
  ];

  if (typeof text === "string" && text.length > 0) {
    events.push({
      type: "response.output_item.done",
      item: {
        type: "message",
        role: "assistant",
        id: messageId,
        content: [{ type: "output_text", text }],
      },
    });
  }

  for (const toolCall of toolCalls || []) {
    events.push({
      type: "response.output_item.done",
      item: {
        type: "function_call",
        call_id: toolCall.id,
        name: toolCall.name,
        arguments: toolCall.arguments,
      },
    });
  }

  events.push({
    type: "response.completed",
    response: {
      id: responseId,
      usage: {
        input_tokens: usage?.prompt_tokens ?? 0,
        input_tokens_details: null,
        output_tokens: usage?.completion_tokens ?? 0,
        output_tokens_details: null,
        total_tokens: usage?.total_tokens ?? 0,
      },
    },
  });

  return events;
}

function nextRequestId() {
  requestCounter += 1;
  return String(requestCounter).padStart(4, "0");
}

async function proxyJson(url, init = {}) {
  const response = await fetch(url, init);
  const text = await response.text();
  return { response, text };
}

const server = http.createServer(async (req, res) => {
  if (!req.url) {
    res.writeHead(400, eventStreamHeaders());
    res.end();
    return;
  }

  if (req.method === "GET" && req.url === "/shutdown") {
    res.writeHead(200, jsonHeaders().headers);
    res.end(JSON.stringify({ ok: true }));
    setTimeout(() => server.close(() => process.exit(0)), 50);
    return;
  }

  if (req.method === "GET" && req.url === "/v1/health/ready") {
    try {
      const { response, text } = await proxyJson(`${upstreamBaseUrl}/health/ready`);
      res.writeHead(response.status, Object.fromEntries(response.headers.entries()));
      res.end(text);
    } catch (error) {
      res.writeHead(502, jsonHeaders(502).headers);
      res.end(JSON.stringify({ error: String(error) }));
    }
    return;
  }

  if (req.method === "GET" && req.url === "/v1/models") {
    try {
      const { response, text } = await proxyJson(`${upstreamBaseUrl}/models`);
      res.writeHead(response.status, Object.fromEntries(response.headers.entries()));
      res.end(text);
    } catch (error) {
      res.writeHead(502, jsonHeaders(502).headers);
      res.end(JSON.stringify({ error: String(error) }));
    }
    return;
  }

  if (req.method !== "POST" || req.url !== "/v1/responses") {
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
  writeArtifact(`${requestId}-codex-responses-request.json`, rawBody);

  let requestBody;
  try {
    requestBody = JSON.parse(rawBody);
  } catch (error) {
    res.writeHead(400, jsonHeaders(400).headers);
    res.end(JSON.stringify({ error: `invalid JSON: ${String(error)}` }));
    return;
  }

  const { messages, unsupportedItems } = buildChatMessages(requestBody);
  if (unsupportedItems.length > 0) {
    res.writeHead(400, jsonHeaders(400).headers);
    res.end(
      JSON.stringify({
        error: "unsupported input item types for first-pass shim",
        unsupportedItems,
      }),
    );
    return;
  }

  const upstreamBody = {
    model: forcedModel || requestBody.model,
    messages,
    stream: false,
  };

  const chatTools = (requestBody.tools || []).map(toChatFunctionTool).filter(Boolean);
  if (chatTools.length > 0) {
    const priorToolTurn = hasPriorToolTurn(requestBody);
    upstreamBody.tools = chatTools;
    if (
      forceSingleToolChoice &&
      !priorToolTurn &&
      chatTools.length === 1 &&
      (requestBody.tool_choice == null || requestBody.tool_choice === "auto")
    ) {
      upstreamBody.tool_choice = {
        type: "function",
        function: {
          name: chatTools[0].function.name,
        },
      };
    } else if (requestBody.tool_choice != null) {
      upstreamBody.tool_choice = requestBody.tool_choice;
    }
    if (typeof requestBody.parallel_tool_calls === "boolean") {
      upstreamBody.parallel_tool_calls = requestBody.parallel_tool_calls;
    }
  }

  if (chatExtraBodyJson.trim()) {
    try {
      mergeObject(upstreamBody, JSON.parse(chatExtraBodyJson));
    } catch (error) {
      res.writeHead(500, jsonHeaders(500).headers);
      res.end(JSON.stringify({ error: `invalid NIM_CHAT_EXTRA_BODY_JSON: ${String(error)}` }));
      return;
    }
  }

  writeArtifact(`${requestId}-nim-chat-request.json`, upstreamBody);

  try {
    const { response, text } = await proxyJson(`${upstreamBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(upstreamBody),
    });

    const upstreamArtifactName = `${requestId}-nim-chat-response.json`;
    writeArtifact(upstreamArtifactName, text);

    if (!response.ok) {
      res.writeHead(response.status, jsonHeaders(response.status).headers);
      res.end(text);
      return;
    }

    const upstreamJson = JSON.parse(text);
    const assistantMessage = upstreamJson?.choices?.[0]?.message;
    const assistantText = normalizeAssistantContent(assistantMessage);
    const assistantToolCalls = (assistantMessage?.tool_calls || [])
      .map(normalizeUpstreamToolCall)
      .filter(Boolean);

    for (const toolCall of assistantToolCalls) {
      rememberedToolCalls.set(toolCall.id, toolCall);
    }

    if (!assistantText && assistantToolCalls.length === 0) {
      res.writeHead(502, jsonHeaders(502).headers);
      res.end(
        JSON.stringify({
          error: "upstream chat completion returned neither assistant text nor tool calls",
          hint: "set NIM_CHAT_EXTRA_BODY_JSON if the upstream requires additional request shaping",
        }),
      );
      return;
    }

    const now = Date.now();
    const responseId = `nim_shim_resp_${now}`;
    const messageId = `nim_shim_msg_${now}`;
    const sseBody = toSse(
      makeResponsesEvents({
        responseId,
        messageId,
        text: assistantText,
        toolCalls: assistantToolCalls,
        usage: upstreamJson?.usage,
      }),
    );
    writeArtifact(`${requestId}-codex-responses-sse.txt`, sseBody);

    res.writeHead(200, eventStreamHeaders());
    res.end(sseBody);
  } catch (error) {
    res.writeHead(502, jsonHeaders(502).headers);
    res.end(JSON.stringify({ error: `upstream fetch failed: ${String(error)}` }));
  }
});

server.listen(port, "127.0.0.1", () => {
  const info = { port, pid: process.pid, upstreamBaseUrl };
  if (serverInfoPath) {
    writeArtifact(serverInfoPath, info);
  }
  writeArtifact("nim-responses-shim-server-info.json", info);
  console.error(`nim-responses-shim listening on 127.0.0.1:${port}`);
});
