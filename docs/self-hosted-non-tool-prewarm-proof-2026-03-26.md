# Self-Hosted Non-Tool Prewarm Proof

Date: March 26, 2026

## Goal

Check whether the existing direct function-calling prewarm materially helps the
slow non-tool self-hosted Codex shim path after the local provider-metadata
patch and writable-`CODEX_HOME` harness hardening.

## Command

```bash
SHIM_PREWARM_TOOL_PATH=1 \
PATH="/Volumes/Code_2TB/code/collaboration/codex/.worktrees/issue-5458-provider-model-metadata/codex-rs/target/debug:$PATH" \
./scripts/smoke-codex-shim.sh
```

Important harness defaults during this run:

- `POC_CODEX_HOME=/tmp/codex-nim-poc-home`
- `CODEX_HOME` exported from that writable path by `scripts/smoke-codex-shim.sh`
- upstream model: `meta/llama-3.1-8b-instruct`
- upstream route: self-hosted NIM on `umbra` through the local SSH tunnel

## Artifact

- artifact dir:
  `artifacts/20260326-044926-codex-shim`

## Exact Results

- prewarm completed and wrote:
  - `prewarm-tool-path/0001-request.json`
  - `prewarm-tool-path/0001-response.json`
  - `prewarm-tool-path/0002-request.json`
  - `prewarm-tool-path/0002-response.json`
- the main self-hosted non-tool Codex shim run completed successfully
- `codex-exec.jsonl` ended with:
  - `item.completed` agent message text `OK`
  - `turn.completed`
- `last-message.txt` contains:
  - `OK`
- upstream chat artifact:
  - `0001-nim-chat-response.json`
  - `finish_reason: "stop"`
  - assistant content: `OK`
- usage reported by the upstream response:
  - `prompt_tokens: 6327`
  - `completion_tokens: 2`
  - `total_tokens: 6329`

## Interpretation

This does not prove the cold-start path is fast.

It does prove the current function-calling prewarm is useful beyond the narrow
tool-bearing lane: on the tested self-hosted NIM route, it was enough to carry
the patched non-tool Codex shim smoke through to a clean `OK` response.

The remaining question is optimization, not basic reachability:

- how much latency remains without prewarm
- how much latency remains with prewarm
- whether a smaller or more targeted prewarm can preserve the same success
  without paying as much startup cost
