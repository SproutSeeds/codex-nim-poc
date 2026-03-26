# Shim Multi-Step Tool Chain Proof

Date: March 26, 2026

## Goal

Broaden the shim proof beyond a single function call without depending on
same-turn parallel multi-tool behavior.

The question here is:

- can the shim carry a multi-step tool chain across multiple turns,
- with Codex executing one tool, then the next, then receiving a final answer,
- while still staying inside the Responses-to-chat bridge?

## Topology

- Codex custom provider:
  - local shim at `http://127.0.0.1:<shim-port>/v1`
- shim upstream:
  - local mock `chat/completions` server
- mock behavior:
  - first request returns one `exec_command` tool call for
    `printf shim-tool-a`
  - second request returns one `exec_command` tool call for
    `printf shim-tool-b`
  - third request reads both tool outputs and returns assistant text

## Exact Result

The multi-step sequential tool chain succeeded end-to-end.

- smoke script:
  - `bash ./scripts/smoke-codex-shim-mock-multi-tool-call.sh`
- artifact dir:
  - `artifacts/20260326-024557-codex-shim-mock-multi-tool-call`
- real tool invocations observed by Codex:
  - `/bin/zsh -lc 'printf shim-tool-a'`
  - `/bin/zsh -lc 'printf shim-tool-b'`
- tool execution results:
  - first aggregated output: `shim-tool-a`
  - second aggregated output: `shim-tool-b`
- final assistant output:
  - `shim-tool-a`
  - `shim-tool-b`

## What This Proved

The shim now covers a broader tool shape than the original single-function
proof:

- one tool-bearing turn can hand off into another tool-bearing turn
- Codex can execute the first requested tool, send the result back through the
  shim, receive a second tool call, execute that second tool, and then finish
- the shim can reconstruct the chat conversation cleanly across multiple
  Responses rounds, not just a single tool-output handoff

## Important Scope Limit

This proof is about sequential multi-step tool chaining, not fully parallel
multi-tool behavior in a single model turn.

We explicitly avoided relying on same-turn parallel tool behavior because the
current local experiments showed a fibrous edge there under
`parallel_tool_calls:false`. The sequential chain is the stronger claim we can
support cleanly today.
