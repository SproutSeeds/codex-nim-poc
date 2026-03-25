# First Live Run

Date: March 25, 2026

## Goal

Test whether Codex can talk directly to NVIDIA-hosted NIM endpoints through a
custom provider using the Responses API.

## Exact Results

- direct `GET https://integrate.api.nvidia.com/v1/models`: `200`
- direct `POST https://integrate.api.nvidia.com/v1/responses`: `404 page not found`
- `codex exec` through a custom provider configured for
  `https://integrate.api.nvidia.com/v1` and `wire_api = "responses"`:
  repeated `404 Not Found` against `/v1/responses`
- manual fallback `POST /v1/chat/completions` with model
  `nvidia/nemotron-3-super-120b-a12b`: `200`
- manual fallback `POST /v1/chat/completions` without
  `chat_template_kwargs.force_nonempty_content`: response had
  `message.content = null` and only reasoning fields
- manual fallback `POST /v1/chat/completions` with
  `chat_template_kwargs.force_nonempty_content = true`: response had non-null
  `message.content`

## Artifact Paths

- direct responses run:
  - `artifacts/20260325-083535/models.headers.txt`
  - `artifacts/20260325-083535/models.body.json`
  - `artifacts/20260325-083535/responses.headers.txt`
  - `artifacts/20260325-083535/responses.body.json`
- chat fallback run:
  - `artifacts/20260325-083535/chat-fallback/chat.headers.txt`
  - `artifacts/20260325-083535/chat-fallback/chat.body.json`
  - `artifacts/20260325-083535/chat-fallback/chat-extra.headers.txt`
  - `artifacts/20260325-083535/chat-fallback/chat-extra.body.json`
- Codex custom-provider run:
  - `artifacts/20260325-083519-codex/codex-exec.jsonl`
  - `artifacts/20260325-083519-codex/last-message.txt`

## Current Read

The strongest current read is:

- NVIDIA hosted NIM on `integrate.api.nvidia.com/v1` is usable through
  `chat/completions`
- this endpoint currently does not expose a working `/v1/responses` path for
  the tested model/provider path
- Codex therefore fails at the Responses boundary before any provider-specific
  `extra_body` primitive can help direct integration
- the `force_nonempty_content` guidance is still real and relevant for
  coding-agent-style chat-completions integrations

## Implication

This lane now looks like two separate questions:

1. direct Codex custom-provider support against hosted NVIDIA NIM needs real
   `/v1/responses` support
2. if NVIDIA ever exposes a working Responses path, Codex may still want a
   provider-level `extra_body` primitive for vendor-specific request tuning
