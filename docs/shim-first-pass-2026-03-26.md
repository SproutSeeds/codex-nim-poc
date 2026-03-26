# Shim First Pass

Date: March 26, 2026

## Goal

Test whether a thin local `/v1/responses` shim can bridge Codex to NVIDIA when
the tested hosted and self-hosted NVIDIA routes do not expose a working native
`/v1/responses` surface.

## Topology

- Codex custom provider:
  - local base URL: `http://127.0.0.1:8011/v1`
- local shim:
  - `scripts/nim-responses-shim.mjs`
- SSH tunnel:
  - local `127.0.0.1:8001` -> `umbra:127.0.0.1:8000`
- self-hosted upstream:
  - `umbra`
  - `RTX 4090`
  - driver `595.79`
  - served model: `meta/llama-3.1-8b-instruct`

## Exact Result

Real `codex exec` succeeded through the shim.

- smoke script:
  - `./scripts/smoke-codex-shim.sh`
- artifact dir:
  - `artifacts/20260326-005229-codex-shim`
- final assistant output:
  - `OK`

The shim emitted a minimal Responses-style SSE stream:

- `response.created`
- `response.output_item.done`
- `response.completed`

with the assistant text:

- `OK`

## First Narrow Compatibility Fix

The first shim run reached NVIDIA but failed because Codex supplied a
Responses-style `message` item with role `developer`, and the tested NVIDIA
`chat/completions` route only accepted:

- `assistant`
- `user`
- `system`
- `tool`
- `function`

The first narrow compatibility fix was:

- normalize `developer` -> `system` in the bridge

After that change, the same end-to-end `codex exec` smoke succeeded.

## Current Scope

This started as a tool-free bridge, but the local shim is now one step beyond
that first pass.

Supported now:

- tool-free Codex turns that can be reduced to chat-style messages
- `instructions` mapped to a system message
- `message` input items reduced to plain text
- minimal Responses-style SSE output for assistant text
- narrow `function_call` / `function_call_output` bridging for standard
  function tools
- tool allow-listing through `SHIM_TOOL_ALLOWLIST`

Still not covered end-to-end on the real NVIDIA route:

- real self-hosted NIM tool-call turns
- custom tool calls or non-function tool types
- broader non-message input item translation
- streaming deltas from NVIDIA upstream
- native hosted-NVIDIA proof through the shim

## Strongest Current Read

This changes the lane materially:

- native NVIDIA routes still stop short of a working `/v1/responses` surface
- a thin local bridge can already make Codex work against the tested
  self-hosted NIM route for tool-free turns
- the bridge itself can now also round-trip a narrow function tool flow against
  a mock chat-completions upstream
- the real self-hosted NIM route still fails earlier on tool-bearing chat
  requests, before the shim can finish a real NVIDIA-backed tool turn

So the path forward is no longer just "wait for native `/v1/responses`." There
is now a concrete compatibility-workaround lane we can continue to harden
locally before deciding what to publish.
