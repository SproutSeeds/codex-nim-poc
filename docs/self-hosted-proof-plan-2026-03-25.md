# Self-Hosted Proof Plan

Date: March 25, 2026

## Goal

Separate hosted NVIDIA Integrate behavior from self-hosted NVIDIA NIM behavior.

The hosted proof is already strong. This plan exists to answer the narrower
next question:

- does a self-hosted NIM deployment expose a working `/v1/responses` path even
  though the tested hosted Integrate surface returned `404`?

## March 26, 2026 Result

This plan is now partially resolved.

The completed self-hosted run is recorded in:

- `docs/self-hosted-vllm-proof-2026-03-26.md`

The strongest result from that run is:

- self-hosted `GET /v1/health/ready` returned `200`
- self-hosted `GET /v1/models` returned `200`
- self-hosted `POST /v1/chat/completions` returned `200`
- self-hosted `POST /v1/responses` returned `404 Not Found`

So the self-hosted path now says something materially stronger than this plan
did originally: the lack of `/v1/responses` is not only a hosted Integrate
surface issue on the tested NVIDIA path.

## Why This Matters

If self-hosted NIM exposes working Responses semantics, then the current public
story becomes much tighter:

- hosted Integrate surface limitation first
- Codex provider-level tuning questions second

If self-hosted NIM does not expose working Responses semantics either, then the
problem broadens beyond the hosted Integrate surface.

## Official Doc Anchors

- Get started with NVIDIA NIM for LLMs:
  - `https://docs.nvidia.com/nim/large-language-models/1.15.0/getting-started.html`
- Supported models / GPUs:
  - `https://docs.nvidia.com/nim/large-language-models/1.15.0/supported-models.html`

Key doc points relevant to this lane:

- self-hosted NIM uses Docker plus `NGC_API_KEY`
- the docs describe `curl http://0.0.0.0:8000/v1/health/ready` and
  `curl http://0.0.0.0:8000/v1/models` as the basic local validation path
- the supported-models page includes `GeForce RTX 4090` in the GPU table, while
  also noting that NVIDIA AI Enterprise infrastructure does not support the
  RTX 4090

## Candidate Host

Current best candidate:

- local Ubuntu `24.04.3 LTS` environment inside WSL2
- GPU:
  - `NVIDIA GeForce RTX 4090`
  - `24564 MiB`
- driver / CUDA as reported by `nvidia-smi`:
  - driver `560.94`
  - CUDA `12.6`
- memory:
  - `31 GiB` total
- disk:
  - roughly `657 GiB` free on `/`

## Current Blocking Findings On Umbra

What is already good:

- GPU visible in WSL2
- driver is recent
- free disk is ample for a first pass
- memory is reasonable for a 24 GB single-GPU proof path

What was missing at first:

- `docker` was not installed
- `nvidia-container-toolkit` / `nvidia-ctk` was not present
- `NGC_API_KEY` was not provided for this path

What is true now:

- Docker is installed
- NVIDIA container runtime is installed and configured
- a CUDA base container can see the RTX 4090 successfully
- `NGC_API_KEY` worked for `docker login nvcr.io`
- the first NIM image pull succeeded:
  - `nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-8b-v1:latest`
- `docker image inspect` on the pulled image reports:
  - `com.nvidia.nim.version = 1.8.4`
  - `CUDA_VERSION = 12.8.0`
- the first NIM launch failed immediately with a concrete runtime requirement
  error:
  - `nvidia-container-cli: requirement error: unsatisfied condition: cuda>=12.8`

So the current self-hosted path is no longer blocked by registry auth or basic
container runtime setup. It is now blocked by driver/runtime compatibility for
the chosen NIM image.

One more useful refinement:

- direct older-release pull guesses are not enough
- both of these returned `manifest unknown`:
  - `nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-8b-v1:1.6.0`
  - `nvcr.io/nim/nvidia/llm-nim:1.6.0`
- exact NGC inventory for this repository now shows only:
  - `1.8.4`
  - `1.8.3`
  - `1.8`
  - `1`
  - `1.8.2`
  - `latest`
- the oldest exposed tag still does not lower the CUDA floor:
  - `nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-8b-v1:1.8.2`
  - `docker image inspect` still reports `CUDA_VERSION = 12.8.0`
  - a short `docker run` check still fails on:
    - `nvidia-container-cli: requirement error: unsatisfied condition: cuda>=12.8`

So the next clean branch point is exact NGC repository/tag inventory or a host
driver/runtime upgrade, not more blind tag guessing.

## Minimal Next Step

1. Choose either:
   - a newer NVIDIA driver/runtime path that satisfies `cuda>=12.8`, or
   - a different self-hosted model repository altogether, if we specifically
     want to avoid a driver change on this host
2. Pull and run the chosen single-GPU NIM image.
3. Check:
   - `/v1/health/ready`
   - `/v1/models`
   - `/v1/responses`
4. Then run the local self-hosted smoke script in this repo.

## Suggested First Self-Hosted Target

Use a small single-GPU-compatible profile first rather than jumping directly to
the biggest model from the hosted proof.

The first attempted target was:

- `nvcr.io/nim/nvidia/llama-3.1-nemotron-nano-8b-v1:latest`

That image pulled successfully, but the first launch attempt failed on the
current host with:

- `cuda>=12.8` required by the container prestart checks

## Repo Support

This repo now includes:

- `scripts/preflight-self-hosted-nim.sh`
  - check host readiness before trying a launch
- `scripts/smoke-self-hosted-nim.sh`
  - validate a local self-hosted endpoint after NIM is up

## Current Read

The strongest current read is:

- self-hosted NIM proof looks feasible on the local RTX 4090 host
- the container runtime path is now ready
- registry auth works
- for this exact model repository, the oldest exposed tag still requires
  `cuda>=12.8`
- the first remaining blocker is now more specifically a host driver/runtime
  upgrade, not basic self-hosting mechanics
