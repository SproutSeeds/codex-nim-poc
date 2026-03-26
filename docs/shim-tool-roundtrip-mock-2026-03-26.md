# Shim Tool Round Trip Mock Proof

Date: March 26, 2026

## Goal

Finish the shim's narrow function-tool implementation without depending on
real NVIDIA tool support.

The question here is:

- can Codex emit a function call through the shim,
- execute the real local tool,
- send back `function_call_output`,
- and receive a final assistant answer through the shim?

## Topology

- Codex custom provider:
  - local shim at `http://127.0.0.1:<shim-port>/v1`
- shim upstream:
  - local mock `chat/completions` server
- mock behavior:
  - first request returns one `exec_command` tool call for
    `printf shim-tool-ok`
  - second request reads the tool output and returns assistant text

## Exact Result

The full narrow tool round trip succeeded.

- smoke script:
  - `POC_CODEX_SANDBOX=danger-full-access ./scripts/smoke-codex-shim-mock-tool-call.sh`
- artifact dir:
  - `artifacts/20260326-013459-codex-shim-mock-tool-call`
- real tool invocation observed by Codex:
  - `/bin/zsh -lc 'printf shim-tool-ok'`
- tool execution result:
  - exit code `0`
  - aggregated output `shim-tool-ok`
- final assistant output:
  - `shim-tool-ok`

## What This Proved

The shim now handles the narrow function-tool slice it was meant to test:

- translate Codex Responses function tools into chat tool definitions
- emit a Responses-style `function_call` item back to Codex
- accept follow-up `function_call_output`
- map the follow-up back into chat messages for the upstream
- emit the final assistant answer as Responses SSE

## Important Scope Limit

This proof is about shim correctness, not NVIDIA tool support.

It uses a local mock `chat/completions` upstream precisely because the tested
real self-hosted NIM route currently goes unhealthy on the first tool-bearing
chat request.

So the clean separation is now:

- shim tool round trip: proven locally
- real self-hosted NVIDIA tool-bearing route: still blocked upstream
