# Self-Hosted Real Tool Round Trip

- Date: March 26, 2026
- Repo: `/Volumes/Code_2TB/code/collaboration/codex-nim-poc`
- Branch: `cody/codex-nim-poc-first-pass`

## Goal

Prove that the local `/v1/responses` shim can carry a real tool-bearing Codex
turn all the way through the tested self-hosted NVIDIA NIM route, not just the
tool-free path and not just the mock upstream path.

## Exact Setup

- Self-hosted NIM served on `umbra`
- SSH tunnel from local `127.0.0.1:8001` to remote `127.0.0.1:8000`
- local shim on `127.0.0.1:8011`
- model id used by the shim:
  - `meta/llama-3.1-8b-instruct`
- Codex run:
  - `POC_CODEX_SANDBOX=danger-full-access`
  - upstream chat extra body:
    - `{"temperature":0}`
- artifact directory:
  - `/Volumes/Code_2TB/code/collaboration/codex-nim-poc/artifacts/20260326-021709-codex-shim`

## Exact Results

- first-turn shim request reached the self-hosted NIM route successfully
- upstream `chat/completions` returned a real tool call, not plain-text pseudo
  tool syntax
- upstream tool call arguments were exact:
  - `{"cmd":"printf shim-tool-ok"}`
- the shim translated that into a real Responses-style `function_call` item
- real `codex exec` invoked `exec_command`
- tool execution succeeded
- Codex reported aggregated output:
  - `shim-tool-ok`
- the shim folded that tool result back into the next chat turn
- second-turn upstream `chat/completions` returned `200`
- second-turn shim SSE completed cleanly
- final assistant message was:
  - `I have followed your instructions and called the exec_command tool exactly once with the command \`printf shim-tool-ok\`. The output of this command is "shim-tool-ok", which I have included in the response as specified.`

## Key Artifacts

- first-turn upstream request:
  - `artifacts/20260326-021709-codex-shim/0001-nim-chat-request.json`
- first-turn upstream response:
  - `artifacts/20260326-021709-codex-shim/0001-nim-chat-response.json`
- first-turn shim SSE:
  - `artifacts/20260326-021709-codex-shim/0001-codex-responses-sse.txt`
- Codex execution stream:
  - `artifacts/20260326-021709-codex-shim/codex-exec.jsonl`
- second-turn request back into the shim:
  - `artifacts/20260326-021709-codex-shim/0002-codex-responses-request.json`
- second-turn upstream response:
  - `artifacts/20260326-021709-codex-shim/0002-nim-chat-response.json`
- second-turn shim SSE:
  - `artifacts/20260326-021709-codex-shim/0002-codex-responses-sse.txt`
- final message:
  - `artifacts/20260326-021709-codex-shim/last-message.txt`

## Interpretation

This is a materially stronger result than the earlier crash-only tool repro.

The real self-hosted NVIDIA-backed path now proves:

- the shim can translate Responses tools into NVIDIA `chat/completions` tools
- the tested self-hosted route can emit real upstream tool calls
- Codex can execute the translated tool successfully
- the shim can translate the tool output back into the next turn
- the real self-hosted route can complete the post-tool assistant turn too

So the remaining gap is no longer "tool calls do not work at all."

The remaining caveats are narrower:

- stability was best with `{"temperature":0}` merged into the shim's upstream
  chat request
- the final assistant wording is still verbose, not the exact literal
  `shim-tool-ok`
- Codex emitted several `failed to record rollout items: channel closed` log
  lines during the run, even though the turn completed successfully

## Strongest Supported Claim

On the tested self-hosted NVIDIA route, the shim now carries a real tool-bearing
Codex turn end-to-end. That means the workaround is no longer limited to
tool-free traffic or a mock upstream.
