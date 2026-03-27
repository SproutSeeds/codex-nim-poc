# Self-Hosted Two-Step Rerun

Date: March 26, 2026

## Goal

Push the shim beyond:

- the real single-tool NVIDIA-backed proof, and
- the mock-backed sequential multi-step proof

by rerunning a real NVIDIA-backed two-step tool chain after teaching the shim
to promote a narrow class of plain-text pseudo-tool calls back into structured
Responses `function_call` items.

## What Changed First

The shim added one conservative recovery path:

- if an upstream assistant turn contains no `tool_calls`,
- but its assistant text begins with a parseable JSON object of the form
  `{ "name": "...", "parameters": ... }`,
- and the tool name is still in the currently exposed tool set,

then the shim now promotes that leading JSON blob into a structured
Responses-style `function_call`.

This was added because the earlier strongest real two-step attempt produced:

- a first real tool call for `printf shim-tool-a`
- then a second-turn assistant text payload shaped like:
  - `{"name": "exec_command", "parameters": {"cmd": "printf shim-tool-b"}}`
  - followed by plain text

So the second call looked semantically right, but it came back as assistant text
instead of a structured tool call.

## Exact Local Guardrails

Before the real rerun:

- `node --check scripts/nim-responses-shim.mjs` passed
- `bash ./scripts/smoke-codex-shim-mock-multi-tool-call.sh` still passed
- newest mock artifact:
  - `artifacts/20260326-025806-codex-shim-mock-multi-tool-call`
- mock-backed final assistant output stayed exact:
  - `shim-tool-a`
  - `shim-tool-b`

## Real Rerun Attempt

- smoke:
  - `POC_CODEX_SANDBOX=danger-full-access ./scripts/smoke-codex-shim-tool-call.sh`
- prompt:
  - ask for exactly two `exec_command` calls:
    - `printf shim-tool-a`
    - then `printf shim-tool-b`
- artifact dir:
  - `artifacts/20260326-030427-codex-shim`

## Exact Results

The rerun did not reach a usable broader proof because the blocker moved out to
the real self-hosted NIM runtime:

- the first upstream response artifacts were written
- the first upstream NIM response in
  `artifacts/20260326-030427-codex-shim/0001-nim-chat-response.json`
  returned:
  - `500`
  - `Engine loop is not running`
- Codex then failed the turn with a temporary high-demand error on its own
  side before any clean second-step proof could be recorded
- remote direct health on `umbra` dropped to:
  - `503`
- remote container logs confirmed:
  - `MQEngineDeadError`
  - `RuntimeError('Engine loop has died')`

So this rerun does **not** disprove the shim promotion change. It proves that
the immediate blocker for the broader real NVIDIA-backed path is now runtime
stability on the self-hosted NIM route.

## Recovery Work Done In The Same Session

After the engine died:

- WSL root access on `umbra` was recovered via:
  - `wsl.exe -u root -e bash -lc ...`
- the live NIM container was identified:
  - `nim-nano-8b-vllm`
- the container was restarted successfully
- post-restart logs showed:
  - normal model-weight reload
  - then a long/sticky CUDA-graph capture phase

At first the service did not return to ready:

- repeated direct health probes saw connection resets while the model was
  coming back up
- the cold-start logs stalled at the CUDA-graph capture stage rather than at
  the earlier dead-engine stacktrace

Later in the same session, the route did recover to ready and a second clean
two-step rerun was attempted.

That second rerun exposed a different fibrous edge:

- the route stayed healthy
- remote logs showed one live request plus a long guided-decoding /
  FSM-compilation phase
- but the local artifact bundle for
  `artifacts/20260326-031558-codex-shim`
  still never received a first complete upstream `chat/completions` response
  artifact during the observed window
- the local smoke parent was then stopped deliberately so the lane ended in a
  clean state instead of leaving a phantom request in flight

## Strongest Current Read

After the new promotion logic:

- the shim itself is broader than before
- the broader mock-backed sequential chain still passes
- the next unresolved edge is no longer just "second tool call comes back as
  text"

The stronger current blocker is:

- self-hosted NIM engine stability during the broader real NVIDIA-backed
  multi-step rerun
- and, after recovery, very long first-turn guided-decoding latency before the
  first complete upstream response lands

## Next Useful Move

If we keep pushing locally, the next honest technical tranche is:

1. relaunch the self-hosted NIM route into a more stable startup mode
2. rerun the two-step real NVIDIA-backed smoke after readiness is truly back
3. only then decide whether the pseudo-tool-call promotion closes the broader
   real path cleanly
