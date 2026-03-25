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
- manual `chat/completions` works for
  `nvidia/nemotron-3-super-120b-a12b`
- NVIDIA's `chat_template_kwargs.force_nonempty_content = true` guidance
  materially changes the chat response shape

So `openai/codex#5458` still matters, but not as the first blocker on this
tested hosted path. The first blocker is hosted `/v1/responses` availability or
compatibility.

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
