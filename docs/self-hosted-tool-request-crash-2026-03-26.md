# Self-Hosted Tool Request Crash

Date: March 26, 2026

## Goal

Test the next real bridge step after the tool-free shim success:

- can the tested self-hosted NVIDIA NIM route survive a standard
  tool-bearing `chat/completions` request once the shim translates Codex
  function tools into chat tools?

## Topology

- Codex custom provider:
  - local shim at `http://127.0.0.1:8011/v1`
- shim upstream:
  - SSH tunnel to `umbra:127.0.0.1:8000`
- upstream NIM route:
  - self-hosted `meta/llama-3.1-8b-instruct`
  - served by `nim_llm_sdk.entrypoints.openai.api_server`

## Exact Result

The first tool-bearing request reached the self-hosted NIM route, but the NIM
engine failed before any tool call was emitted back to Codex.

- smoke script:
  - `./scripts/smoke-codex-shim-tool-call.sh`
- prompt shape:
  - force one `exec_command` tool call for `printf shim-tool-ok`
- first narrow shim fix already needed before this run:
  - drop nested `function.strict` from chat tool definitions because the
    tested NIM route rejected it as an extra field

After that schema fix, the real upstream boundary became:

- upstream `POST /v1/chat/completions` returned:
  - `500 InternalServerError`
  - body:
    - `Engine loop is not running. Inspect the stacktrace to find the original error: RuntimeError('Engine loop has died').`
- Codex retried and received the same upstream `500` on each retry
- the self-hosted service then reported:
  - `GET /v1/health/ready -> 503 Service Unavailable`
  - body:
    - `{"object":"error","message":"Service in unhealthy","type":"ServiceUnavailableError","param":null,"code":503}`

## Supporting Local Findings

- the self-hosted service process stayed alive after the unhealthy transition:
  - `nim_llm_sdk.entrypoints.openai.api_server` still running as user
    `codacli`
- process tree snapshot:
  - parent launcher: `/bin/bash /opt/nim/start_server.sh`
  - main API pid during inspection: `5050`
- this means the failure is not "process disappeared immediately"
- from the bridge perspective, Codex never got a valid upstream tool call item
  on this real NVIDIA path

## Strongest Current Read

The shim is no longer the first blocker for tool turns.

On the tested real self-hosted NVIDIA path:

- the shim can translate the request into chat-tool form
- but the upstream NIM route becomes unhealthy on the first tool-bearing chat
  request

So the current separation is:

- shim logic: viable
- real self-hosted NVIDIA tool-bearing upstream: not yet viable on this tested
  route
