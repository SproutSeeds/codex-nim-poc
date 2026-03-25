# Codex NVIDIA NIM POC

This repo is a narrow proof-of-concept for one question:

- can `openai/codex` talk directly to NVIDIA-hosted NIM endpoints through
  Codex custom model providers, or
- do we hit a request-shape gap that needs a Codex-side primitive such as
  provider-configured extra request-body fields?

The current best public fit on the Codex side is:

- `openai/codex#5458`
  - https://github.com/openai/codex/issues/5458

The current strongest local proof is here:

- `docs/first-live-run-2026-03-25.md`

## Why This Exists

Two current facts make this lane worth proving directly:

1. Codex already supports custom model providers that speak the Responses API.
2. NVIDIA NIM now advertises OpenAI-compatible APIs including experimental
   `/v1/responses` support for some LLM deployments, and NVIDIA's Nemotron 3
   Super model card includes coding-agent guidance that mentions an
   `extra_body` tweak for agent apps.

That means the likely outcomes are now:

- direct compatibility works
- direct compatibility mostly works but needs provider tuning
- Codex needs a new primitive like provider-configured `extra_body`
- the specific NVIDIA endpoint is not actually compatible enough for Codex yet

## Current Hypothesis

The strongest likely break is not authentication or base URL wiring.

The strongest likely break is request-shape flexibility:

- Codex config already supports `base_url`, headers, query params, retries,
  idle timeouts, and websocket toggles.
- Codex does not currently expose a provider-level `extra_body` field.
- NVIDIA's current coding-agent guidance for at least one Nemotron endpoint
  includes `extra_body.chat_template_kwargs.force_nonempty_content = true`.

If direct `/v1/responses` requests work but Codex runs fail because that extra
body is needed, `openai/codex#5458` becomes the natural upstream lane.

## Repo Layout

- `configs/codex.nvidia-nim.example.toml`
  - example Codex custom-provider config
- `docs/compatibility-checklist.md`
  - what we need to prove before making upstream claims
- `docs/first-live-run-2026-03-25.md`
  - recorded hosted proof so far
- `scripts/smoke-nim-api.sh`
  - direct NVIDIA NIM smoke against `/v1/models` and `/v1/responses`
- `scripts/smoke-nim-responses-matrix.sh`
  - direct `/v1/responses` checks across multiple NVIDIA models
- `scripts/smoke-nim-chat-fallback.sh`
  - `chat/completions` comparison with and without
    `chat_template_kwargs.force_nonempty_content`
- `scripts/smoke-codex-provider.sh`
  - optional real `codex exec` smoke using a custom provider override

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

Instead of exporting variables into the launching shell, you can place them in
`./.env` inside this repo. The smoke scripts will source that file
automatically.

Start from:

```bash
cp .env.example .env
```

## First Pass

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

## Notes

- This repo is intentionally small.
- It is not yet claiming production support.
- It is meant to convert the lane from speculation into checkable evidence.
