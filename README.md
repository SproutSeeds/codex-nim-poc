# Codex NVIDIA NIM POC

This repo is a narrow proof-of-concept for one question:

- can `openai/codex` talk directly to NVIDIA-hosted NIM endpoints through
  Codex custom model providers, or
- do we hit a request-shape gap that needs a Codex-side primitive such as
  provider-configured extra request-body fields?

The current best public fit on the Codex side is:

- `openai/codex#5458`
  - https://github.com/openai/codex/issues/5458

The current strongest recorded proof is here:

- `docs/first-live-run-2026-03-25.md`
- `docs/hosted-responses-matrix-2026-03-25.md`

## Current Strongest Read

The strongest current read is:

- hosted NVIDIA NIM at `https://integrate.api.nvidia.com/v1` works for
  `GET /v1/models`
- the same hosted path returned `404 page not found` for direct
  `POST /v1/responses` across a wider six-model matrix
- real `codex exec` through a custom provider fails at that same
  `/v1/responses` boundary
- a self-hosted NIM run on `umbra` with an `RTX 4090` now also separates
  cleanly:
  - `GET /v1/health/ready` returns `200`
  - `GET /v1/models` returns `200`
  - `POST /v1/chat/completions` returns `200`
  - `POST /v1/responses` returns `404 Not Found`
- a thin local `/v1/responses` shim can already bridge Codex to that tested
  self-hosted NIM route for a tool-free first pass:
  - real `codex exec` succeeded through the shim
  - the first-pass smoke returned `OK`
- the same shim now supports a narrow standard-function tool round trip:
  - against a mock `chat/completions` upstream, real `codex exec` completed
    with final assistant output `shim-tool-ok`
  - against the real self-hosted NIM route, real `codex exec` now completes a
    tool-bearing turn end-to-end too
  - the strongest real run used upstream chat extra body
    `{"temperature":0}` and preserved the exact requested tool arguments
  - remaining caveats are now narrower:
    - final assistant wording is still verbose rather than the literal
      `shim-tool-ok`
    - Codex still emitted `failed to record rollout items: channel closed`
      logs during the otherwise successful run
- the shim now also proves a broader multi-step tool chain against the mock
  upstream:
  - first tool call
  - second tool call
  - final assistant answer
  - exact final output:
    - `shim-tool-a`
    - `shim-tool-b`
  - this is the cleanest broader parity proof today because same-turn
    parallel multi-tool behavior is still a fibrous edge under
    `parallel_tool_calls:false`
- manual `chat/completions` works for
  `nvidia/nemotron-3-super-120b-a12b`
- NVIDIA's `chat_template_kwargs.force_nonempty_content = true` guidance
  materially changes the chat response shape

So `openai/codex#5458` still matters, but not as the first blocker on the
tested NVIDIA paths. The first blocker is `/v1/responses` availability or
compatibility itself.

## Why This Exists

Two current facts made this lane worth proving directly:

1. Codex already supports custom model providers that speak the Responses API.
2. NVIDIA NIM now advertises OpenAI-compatible APIs including experimental
   `/v1/responses` support for some LLM deployments, and NVIDIA's Nemotron 3
   Super model card includes coding-agent guidance that mentions an
   `extra_body` tweak for agent apps.

That means the meaningful outcomes are:

- direct compatibility works
- direct compatibility mostly works but needs provider tuning
- Codex needs a new primitive like provider-configured `extra_body`
- the specific NVIDIA endpoint is not actually compatible enough for Codex yet

## Current Hypothesis

The first blocking boundary on the tested hosted path is not authentication or
base URL wiring.

The first blocking boundary is `/v1/responses` availability or compatibility on
the hosted NVIDIA endpoint.

The second question, if a working Responses path exists, is request-shape
flexibility:

- Codex config already supports `base_url`, headers, query params, retries,
  idle timeouts, and websocket toggles.
- Codex does not currently expose a provider-level `extra_body` field.
- NVIDIA's current coding-agent guidance for at least one Nemotron endpoint
  includes `extra_body.chat_template_kwargs.force_nonempty_content = true`.

If direct `/v1/responses` requests work but Codex runs still fail because that
extra body is needed, `openai/codex#5458` becomes the natural upstream lane.

## Repo Layout

- `configs/codex.nvidia-nim.example.toml`
  - example Codex custom-provider config
- `docs/compatibility-checklist.md`
  - what we need to prove before making upstream claims
- `docs/first-live-run-2026-03-25.md`
  - recorded hosted proof so far
- `docs/hosted-responses-matrix-2026-03-25.md`
  - widened `/v1/responses` check across NVIDIA, Meta, and Mistral models
- `docs/self-hosted-proof-plan-2026-03-25.md`
  - exact next-step plan for separating hosted Integrate behavior from
    self-hosted NIM behavior
- `docs/self-hosted-vllm-proof-2026-03-26.md`
  - completed self-hosted proof on `umbra` after the driver/runtime upgrade,
    vLLM profile prefetch, and warmed relaunch
- `scripts/smoke-nim-api.sh`
  - direct NVIDIA NIM smoke against `/v1/models` and `/v1/responses`
- `scripts/smoke-nim-responses-matrix.sh`
  - direct `/v1/responses` checks across multiple NVIDIA models
- `scripts/smoke-nim-chat-fallback.sh`
  - `chat/completions` comparison with and without
    `chat_template_kwargs.force_nonempty_content`
- `scripts/smoke-codex-provider.sh`
  - optional real `codex exec` smoke using a custom provider override
- `scripts/preflight-self-hosted-nim.sh`
  - host-readiness check for a self-hosted NIM proof path
- `scripts/smoke-self-hosted-nim.sh`
  - local endpoint validation for a running self-hosted NIM
- `scripts/nim-responses-shim.mjs`
  - thin local bridge from Codex `/v1/responses` requests to NVIDIA
    `chat/completions`
- `scripts/smoke-codex-shim.sh`
  - end-to-end Codex smoke through the local shim and an SSH tunnel to the
    self-hosted NIM
- `scripts/smoke-codex-shim-tool-call.sh`
  - real self-hosted NIM tool-call repro through the shim
- `scripts/mock-chat-tools-upstream.mjs`
  - local mock `chat/completions` upstream for shim tool-cycle validation
- `scripts/smoke-codex-shim-mock-tool-call.sh`
  - end-to-end Codex smoke proving the shim's narrow tool round trip without
    depending on NVIDIA tool support
- `configs/codex.nvidia-nim-shim.example.toml`
  - example local Codex config pointing at the shim
- `docs/shim-first-pass-2026-03-26.md`
  - first local proof that Codex can work through the shim against the tested
    self-hosted NIM route
- `docs/shim-tool-roundtrip-mock-2026-03-26.md`
  - local proof that the shim can round-trip a standard function tool call
    through Codex against a mock chat upstream
- `docs/shim-multi-step-tool-chain-2026-03-26.md`
  - local proof that the shim can carry a broader sequential multi-step tool
    chain through Codex against a mock chat upstream
- `docs/self-hosted-tool-roundtrip-real-2026-03-26.md`
  - stronger local proof that the shim can carry a real tool-bearing Codex
    turn end-to-end against the tested self-hosted NVIDIA route
- `docs/self-hosted-tool-request-crash-2026-03-26.md`
  - earlier local proof of an unhealthy/crash path before the stronger
    stabilized tool-bearing run

## Required Environment

- `NVIDIA_API_KEY`
- `NIM_MODEL`
  - optional
  - default: `nvidia/nemotron-3-super-120b-a12b`

Optional:

- `NIM_BASE_URL`
  - default: `https://integrate.api.nvidia.com/v1`
- `NIM_PROMPT`
- `NIM_EXTRA_BODY_JSON`
  - raw JSON object merged into the request body during direct API smoke tests
- `POC_CODEX_SANDBOX`
  - default in the Codex smoke script is `read-only`
- `NGC_API_KEY`
  - required for self-hosted NIM pulls from NGC
- `SELF_HOSTED_NIM_BASE_URL`
  - default: `http://127.0.0.1:8000/v1`
- `SELF_HOSTED_NIM_MODEL`
  - optional model override if `/v1/models` does not return the desired served
    id
- `SELF_HOSTED_NIM_PROMPT`
- `SHIM_TUNNEL_PORT`
  - default: `8001`
- `SHIM_PORT`
  - default: `8011`
- `SHIM_UPSTREAM_BASE_URL`
  - optional override for the shim upstream base URL
- `SHIM_MODEL`
  - optional override for the model the shim forwards to
- `NIM_CHAT_EXTRA_BODY_JSON`
  - raw JSON object merged into the upstream `chat/completions`
    request body made by the shim
  - the strongest real tool-bearing run used:
    - `{"temperature":0}`
- `SHIM_TOOL_ALLOWLIST`
  - optional comma-separated function-tool allow-list for the shim
- `MOCK_UPSTREAM_PORT`
- `MOCK_MODEL`
- `MOCK_TOOL_COMMAND`
- `MOCK_TOOL_COMMANDS_JSON`
  - optional JSON array for broader multi-step mock tool chains
- `MOCK_TOOL_CALL_MODE`
  - optional mock tool-call mode
  - current useful values:
    - `sequential`
    - `parallel`

Instead of exporting variables into the launching shell, you can place them in
`./.env` inside this repo. The smoke scripts will source that file
automatically.

Start from:

```bash
cp .env.example .env
```

## Reproduction Flow

1. Run the direct API smoke:

```bash
./scripts/smoke-nim-api.sh
```

2. Run the hosted responses matrix:

```bash
./scripts/smoke-nim-responses-matrix.sh
```

3. Run the chat fallback comparison:

```bash
./scripts/smoke-nim-chat-fallback.sh
```

4. If that succeeds, run the real Codex provider smoke:

```bash
./scripts/smoke-codex-provider.sh
```

5. If the direct API smoke works but the Codex smoke fails, compare the saved
   request/response artifacts and decide whether the missing primitive belongs
   in `openai/codex#5458`.

6. If you want a local workaround against the self-hosted NIM route, run:

```bash
./scripts/smoke-codex-shim.sh
```

That script:

- opens an SSH tunnel to `umbra`
- starts the local shim
- runs real `codex exec` against the shim
- saves Codex, shim, and upstream artifacts together

7. If you want the real self-hosted NIM tool-bearing repro through the shim,
   run:

```bash
POC_CODEX_SANDBOX=danger-full-access ./scripts/smoke-codex-shim-tool-call.sh
```

That script now defaults the shim's upstream chat request to:

- `NIM_CHAT_EXTRA_BODY_JSON='{"temperature":0}'`

unless you override it explicitly.

8. If you want to validate the shim's narrow tool round trip independent of
   NVIDIA's tool support, run:

```bash
POC_CODEX_SANDBOX=danger-full-access ./scripts/smoke-codex-shim-mock-tool-call.sh
```

9. If you want a broader mock-backed multi-step tool-chain proof, run:

```bash
bash ./scripts/smoke-codex-shim-mock-multi-tool-call.sh
```

That path currently defaults to:

- `MOCK_TOOL_CALL_MODE=sequential`
- `MOCK_TOOL_COMMANDS_JSON='["printf shim-tool-a","printf shim-tool-b"]'`

## Self-Hosted Refinement Path

If you want to separate hosted Integrate behavior from self-hosted NIM
behavior:

1. Read `docs/self-hosted-proof-plan-2026-03-25.md`
2. Run:

```bash
./scripts/preflight-self-hosted-nim.sh
```

3. Bring up a local self-hosted NIM following the NVIDIA docs
4. Then run:

```bash
./scripts/smoke-self-hosted-nim.sh
```

Current status of that path:

- preflight and smoke scripts exist
- Docker plus NVIDIA container runtime are ready on the first candidate host
- `NGC_API_KEY` auth to `nvcr.io` worked
- the first NIM image pull worked
- the pulled image reports:
  - `com.nvidia.nim.version = 1.8.4`
  - `CUDA_VERSION = 12.8.0`
- the first NIM launch failed on a concrete requirement:
  - `cuda>=12.8`
- naive older-release pull guesses are not enough:
  - `nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-8b-v1:1.6.0` returned
    `manifest unknown`
  - `nvcr.io/nim/nvidia/llm-nim:1.6.0` also returned `manifest unknown`
- exact NGC repo inventory is now available for this model:
  - `1.8.4`
  - `1.8.3`
  - `1.8`
  - `1`
  - `1.8.2`
  - `latest`
- the oldest exposed tag still does not solve the host-compatibility problem:
  - `nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-8b-v1:1.8.2`
  - `docker image inspect` still shows `CUDA_VERSION = 12.8.0`
  - short launch check still fails on `cuda>=12.8`
- after upgrading the Windows driver on `umbra` to `595.79`, the
  `cuda>=12.8` blocker cleared
- after a cache-permission fix plus a warmed vLLM profile prefetch, the
  self-hosted service came up on:
  - `GET /v1/health/ready`
  - `GET /v1/models`
  - `POST /v1/chat/completions`
- on that same self-hosted run, `POST /v1/responses` still returned
  `404 Not Found`

So the self-hosted refinement is no longer just a plan. On this tested
self-hosted route, the API surface still stops short of `/v1/responses`.

## Strongest Public Artifact

This repo is meant to be linkable from the upstream Codex thread once the saved
findings are stable enough to be maintainer-useful.

The intended public use is:

- point to the scripts
- point to the saved live-run note
- keep the upstream comment narrow and evidence-backed
- avoid overclaiming NVIDIA compatibility beyond the exact hosted path tested

## Notes

- This repo is intentionally small.
- It is not yet claiming production support.
- It is meant to convert the lane from speculation into checkable evidence.
