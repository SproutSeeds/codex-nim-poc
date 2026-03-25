# Codex ↔ NVIDIA NIM Compatibility Checklist

This checklist keeps the lane evidence-first.

## Direct API Layer

- `GET /v1/models` succeeds against the chosen NIM endpoint
- `POST /v1/responses` succeeds with a minimal non-streaming request
- streamed `POST /v1/responses` succeeds if the endpoint claims streaming support
- tool-calling request shape is accepted if the model advertises tool use
- structured output does not regress if that matters for the chosen model

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

## Public Rollout Guidance

- If direct API fails on `/v1/responses`, that is primarily an NVIDIA/API-side
  compatibility question.
- If direct API works but Codex cannot express the needed request body, that is
  primarily a Codex primitive question and likely belongs in `openai/codex#5458`.
- If both work, we can publish a narrow example-driven compatibility note
  instead of an issue.
