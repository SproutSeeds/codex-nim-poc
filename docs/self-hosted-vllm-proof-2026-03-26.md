# Self-Hosted vLLM Proof

Date: March 26, 2026

## Goal

Finish the self-hosted separation test on the same NIM family after the hosted
Integrate proof already showed:

- `GET /v1/models` works
- `POST /v1/chat/completions` works
- `POST /v1/responses` returns `404`

The question here was narrower:

- does a real self-hosted NIM deployment on the local `RTX 4090` expose a
  working `/v1/responses` route?

## Host

- Host label: `umbra`
- Windows driver after upgrade: `595.79`
- Runtime path: WSL2 + Docker + NVIDIA Container Toolkit
- GPU: `NVIDIA GeForce RTX 4090`

## Image And Profile

- Image:
  - `nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-8b-v1:latest`
- Chosen profile:
  - `4f904d571fe60ff24695b5ee2aa42da58cb460787a968f1e8a09f5a7e862728d`
  - `vllm-bf16-tp1-pp1`
- Served model name:
  - `meta/llama-3.1-8b-instruct`

## What Changed Versus The Earlier Failed Attempts

1. The Windows/NVIDIA driver was upgraded so the earlier `cuda>=12.8` blocker
   disappeared.
2. The mounted cache directory was fixed for the container user.
3. `list-model-profiles` confirmed a generic `vllm-bf16-tp1-pp1` profile was
   compatible on the 4090.
4. `download-to-cache --profiles <vllm-profile>` was run to prefetch the model
   shards and tokenizer/config artifacts.
5. The service was relaunched from the warmed cache with the pinned vLLM
   profile.

## Exact Results

Remote direct checks on `umbra`:

- `GET http://127.0.0.1:8000/v1/health/ready`
  - `200 OK`
- `GET http://127.0.0.1:8000/v1/models`
  - `200 OK`
  - served model id: `meta/llama-3.1-8b-instruct`
- `POST http://127.0.0.1:8000/v1/chat/completions`
  - `200 OK`
  - test prompt returned `OK.`
- `POST http://127.0.0.1:8000/v1/responses`
  - `404 Not Found`
  - body: `{"detail":"Not Found"}`

Scripted artifact bundle through an SSH tunnel:

- script:
  - `./scripts/smoke-self-hosted-nim.sh`
- exact summary:
  - `ready_status=200`
  - `models_status=200`
  - `model_id=meta/llama-3.1-8b-instruct`
  - `responses_status=404`
- local artifact directory:
  - `artifacts/20260326-001433-self-hosted`

## Important Log Markers

- `Graph capturing finished in 220 secs.`
- `Route: /v1/chat/completions, Methods: POST`
- `Route: /v1/models, Methods: GET`
- `Route: /v1/health/ready, Methods: GET`
- there was no `/v1/responses` route in the advertised route list

## Strongest Current Read

This is no longer just a hosted Integrate compatibility story.

On at least one real self-hosted NIM route:

- health works
- model listing works
- chat completions work
- `/v1/responses` is still absent as a route and returns `404`

So the first Codex compatibility blocker on the tested NVIDIA paths is still
the same one:

- Codex requires `wire_api = "responses"`
- the tested NVIDIA routes still stop short of a working `/v1/responses`
  surface

That means provider-level request-body tuning is still conceptually relevant
later, but it is not the first blocker on this self-hosted proof either.
