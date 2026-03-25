# Self-Hosted Proof Plan

Date: March 25, 2026

## Goal

Separate hosted NVIDIA Integrate behavior from self-hosted NVIDIA NIM behavior.

The hosted proof is already strong. This plan exists to answer the narrower
next question:

- does a self-hosted NIM deployment expose a working `/v1/responses` path even
  though the tested hosted Integrate surface returned `404`?

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

- host: `umbra`
- access path:
  - `ssh -i ~/.ssh/collab_umbra codyr@192.168.1.162`
- OS:
  - `Ubuntu 24.04.3 LTS` inside WSL2
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

What is still missing:

- `docker` is not installed in the WSL2 environment
- `docker` is also not available on the Windows host side
- `nvidia-container-toolkit` / `nvidia-ctk` is not present
- `NGC_API_KEY` was not provided for this path

So the current self-hosted path is blocked by runtime setup plus an NGC key,
not by GPU absence.

## Minimal Next Step

1. Install Docker on the target Linux environment.
2. Install NVIDIA Container Toolkit / runtime integration.
3. Export `NGC_API_KEY`.
4. Pull and run a small single-GPU NIM image.
5. Check:
   - `/v1/health/ready`
   - `/v1/models`
   - `/v1/responses`
6. Then run the local self-hosted smoke script in this repo.

## Suggested First Self-Hosted Target

Use a small single-GPU-compatible profile first rather than jumping directly to
the biggest model from the hosted proof. The exact image choice should follow
whatever the NVIDIA docs / profile tooling says is runnable on the 4090.

## Repo Support

This repo now includes:

- `scripts/preflight-self-hosted-nim.sh`
  - check host readiness before trying a launch
- `scripts/smoke-self-hosted-nim.sh`
  - validate a local self-hosted endpoint after NIM is up

## Current Read

The strongest current read is:

- self-hosted NIM proof looks feasible on `umbra`
- it is blocked by missing container runtime setup and `NGC_API_KEY`
- this is now an operational setup gap, not an uncertainty about where to try
