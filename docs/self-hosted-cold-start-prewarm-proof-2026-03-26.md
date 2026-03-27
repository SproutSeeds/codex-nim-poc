# Self-Hosted Cold-Start Prewarm Proof

Date: March 26, 2026

## Summary

The broader real NVIDIA-backed two-step shim path now completes end-to-end
after a fresh self-hosted NIM restart on `umbra`.

The key local harness changes were:

- explicit readiness polling in `scripts/smoke-codex-shim.sh`
- a direct function-calling prewarm in
  `scripts/prewarm-self-hosted-tool-path.sh`
- default prewarm enablement for `scripts/smoke-codex-shim-tool-call.sh`

## Exact Results

- restart command:
  - `docker restart nim-nano-8b-vllm`
- full cold-start artifact dir:
  - `artifacts/20260326-033920-codex-shim`
- prewarm artifact dir:
  - `artifacts/20260326-033920-codex-shim/prewarm-tool-path`
- final assistant output:
  - `shim-tool-a`
  - `shim-tool-b`

Remote NIM log checkpoints:

- `/v1/health/ready` first returned `200` at `08:40:14`
- prewarm `chat/completions` calls returned `200` at:
  - `08:40:21`
  - `08:40:26`
- first real Codex-driven `chat/completions` turn returned `200` at:
  - `08:42:11`
- second real Codex-driven `chat/completions` turn returned `200` at:
  - `08:43:59`
- final real Codex-driven `chat/completions` turn returned `200` at:
  - `08:45:38`

## Interpretation

The path is no longer blocked on the earlier runtime failure mode alone.

What is now supported:

- the self-hosted NIM route still lacks native `/v1/responses`
- the local shim can bridge that gap
- the broader real two-step Codex tool flow can complete end-to-end after a
  fresh restart if the harness first waits for readiness and prewarms the
  function-calling path

What is still not solved:

- cold-start parity with the already-warm path
- the `meta/llama-3.1-8b-instruct` fallback-metadata warning
- the `failed to record rollout items: channel closed` Codex log noise
- same-turn parallel multi-tool behavior

## Important Caveats

- this does not erase the earlier runtime-instability evidence:
  - `artifacts/20260326-030427-codex-shim`
  - `artifacts/20260326-031558-codex-shim`
- the fresh-restart path is materially slower than the already-warm path
- the successful broader path still relies on:
  - `{"temperature":0}` in the upstream chat request shaping
  - the shim's pseudo-tool-call promotion for the second turn
