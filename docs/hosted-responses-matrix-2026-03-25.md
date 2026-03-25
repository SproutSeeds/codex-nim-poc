# Hosted Responses Matrix

Date: March 25, 2026

## Goal

Check whether the hosted NVIDIA Integrate endpoint exposes a working
`/v1/responses` path only for some models, or whether the failure looks broader
than the first two-model proof.

## Exact Results

All six tested models returned `404 page not found` for direct
`POST https://integrate.api.nvidia.com/v1/responses`:

- `nvidia/nemotron-3-super-120b-a12b`
- `nvidia/llama-3.3-nemotron-super-49b-v1`
- `nvidia/llama-3.1-nemotron-70b-instruct`
- `nvidia/nemotron-mini-4b-instruct`
- `meta/llama-3.3-70b-instruct`
- `mistralai/mistral-large`

## Artifact Paths

- summary:
  - `artifacts/20260325-143823-responses-matrix/summary.txt`
- per-model request / response captures:
  - `artifacts/20260325-143823-responses-matrix/*.request.json`
  - `artifacts/20260325-143823-responses-matrix/*.headers.txt`
  - `artifacts/20260325-143823-responses-matrix/*.body.json`

## Current Read

The strongest read from this widened hosted check is:

- the tested hosted Integrate surface is not just failing `/v1/responses` for
  one NVIDIA model
- the same `404 page not found` response appeared across multiple NVIDIA
  instruct models and also on tested Meta and Mistral instruct models
- that makes the current hosted boundary look more like an endpoint-level
  compatibility limitation than a single-model quirk

## Implication

This makes the public story sharper:

1. hosted NVIDIA Integrate currently fails the direct Responses prerequisite for
   Codex custom providers on the tested path
2. `openai/codex#5458` can still matter later if some hosted or self-hosted NIM
   path exposes working Responses semantics and still needs provider-level
   request-body tuning
