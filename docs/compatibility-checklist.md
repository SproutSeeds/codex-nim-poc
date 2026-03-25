# Codex ↔ NVIDIA NIM Compatibility Checklist

This checklist keeps the lane evidence-first.

## Direct API Layer

- `GET /v1/models` succeeds against the chosen NIM endpoint
- `POST /v1/responses` succeeds with a minimal non-streaming request
- a second `/v1/responses` check on another NVIDIA model does not contradict
  the first result
- streamed `POST /v1/responses` succeeds if the endpoint claims streaming support
- tool-calling request shape is accepted if the model advertises tool use
- structured output does not regress if that matters for the chosen model

## Self-Hosted Separation Layer

- candidate host passes `scripts/preflight-self-hosted-nim.sh`
- self-hosted NIM reaches `/v1/health/ready`
- self-hosted `/v1/models` succeeds
- self-hosted `/v1/responses` is checked before making broader Codex claims
- if self-hosted differs from hosted Integrate, record that split explicitly

## Codex Provider Layer

- Codex custom provider config is enough to reach the endpoint
- auth works through `model_providers.<id>.env_key`
- SSE path is stable enough for `codex exec --json`
- resume/fork/session metadata does not break for the custom provider

## Likely Missing Primitive Checks

- provider-specific extra request-body fields needed?
- provider-specific static or environment-derived headers needed?
- provider-specific query params needed?
- websocket toggle required off?
- retry/idle timeout values need tuning?

## Evidence Threshold Before Public Claim

- direct NIM request artifacts saved
- Codex exec artifacts saved
- if the lane fails, the failing request layer is isolated:
  - NVIDIA endpoint contract gap
  - Codex custom-provider gap
  - missing provider-level request-body injection
  - docs/hosted-behavior mismatch

## Public Rollout Guidance

- If direct API fails on `/v1/responses`, that is primarily an NVIDIA/API-side
  compatibility question.
- If a widened hosted matrix shows the same `/v1/responses` `404` across
  multiple models or vendors on the same endpoint, prefer describing that as a
  hosted-surface compatibility boundary rather than a single-model quirk.
- If direct API works but Codex cannot express the needed request body, that is
  primarily a Codex primitive question and likely belongs in `openai/codex#5458`.
- If both work, we can publish a narrow example-driven compatibility note
  instead of an issue.
