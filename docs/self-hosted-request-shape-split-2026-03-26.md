# Self-Hosted Request-Shape Split Proof

Date: March 26, 2026

## Goal

Separate three possible explanations for the remaining self-hosted NIM stall on
the Codex shim path:

- cold start alone
- prewarm alone
- request-shape / payload-mass differences

## Compared Requests

Heavier request from the earlier timed-out run:

- Codex request:
  `artifacts/20260326-042941-codex-shim/0001-codex-responses-request.json`
- NIM chat request:
  `artifacts/20260326-042941-codex-shim/0001-nim-chat-request.json`

Smaller request from the later successful prewarmed run:

- Codex request:
  `artifacts/20260326-044926-codex-shim/0001-codex-responses-request.json`
- NIM chat request:
  `artifacts/20260326-044926-codex-shim/0001-nim-chat-request.json`

## Structural Deltas

Chat request shape:

- heavier request:
  - `messages_len: 4`
  - `tools_len: 24`
  - `messages_chars: 10945`
  - `tools_chars: 30072`
- smaller request:
  - `messages_len: 4`
  - `tools_len: 10`
  - `messages_chars: 6143`
  - `tools_chars: 18583`

Codex request shape:

- heavier request:
  - `messages_len: 3`
  - `tools_len: 26`
  - `input_chars: 10989`
  - `tools_chars: 30872`
  - `developer_join_len: 6160`
  - `user_join_len: 4447`
- smaller request:
  - `messages_len: 3`
  - `tools_len: 11`
  - `input_chars: 6157`
  - `tools_chars: 18653`
  - `developer_join_len: 5613`
  - `user_join_len: 241`

The biggest user-facing context split is that the heavier request carried a
large `# AGENTS.md instructions for /Volumes/Code_2TB/code/collaboration/codex-nim-poc`
payload as a user message, while the smaller request carried only the short
`<environment_context>` user block.

The biggest tool-surface split is that the heavier request also exposed a large
extra tool cluster that the smaller request did not include:

- `js_repl`
- `js_repl_reset`
- `list_mcp_resources`
- `list_mcp_resource_templates`
- `read_mcp_resource`
- `mcp__context7__query_docs`
- `mcp__context7__resolve_library_id`
- `mcp__openaiDeveloperDocs__fetch_openai_doc`
- `mcp__openaiDeveloperDocs__get_openapi_spec`
- `mcp__openaiDeveloperDocs__list_api_endpoints`
- `mcp__openaiDeveloperDocs__list_openai_docs`
- `mcp__openaiDeveloperDocs__search_openai_docs`
- `mcp__screenshot_full_page_mcp__capture_element`
- `mcp__screenshot_full_page_mcp__capture_screenshot`
- `mcp__screenshot_full_page_mcp__list_device_presets`

## Controlled Measurements

Heavier request, no prewarm:

- script:
  `bash ./scripts/measure-self-hosted-structured-latency.sh artifacts/20260326-042941-codex-shim/0001-nim-chat-request.json`
- artifact dir:
  `artifacts/20260326-104927-structured-latency`
- exact result:
  - `curl_exit=28`
  - `http_code=000`
  - `time_total=90.003658`

Heavier request, with prewarm, 120s budget:

- script:
  `MEASURE_PREWARM_TOOL_PATH=1 MEASURE_MAX_TIME_SECONDS=120 bash ./scripts/measure-self-hosted-structured-latency.sh artifacts/20260326-042941-codex-shim/0001-nim-chat-request.json`
- artifact dir:
  `artifacts/20260326-110400-structured-latency`
- exact result:
  - `curl_exit=28`
  - `http_code=000`
  - `time_total=120.006093`

Smaller request, no prewarm, 120s budget:

- script:
  `bash ./scripts/measure-self-hosted-structured-latency.sh artifacts/20260326-044926-codex-shim/0001-nim-chat-request.json`
- artifact dir:
  `artifacts/20260326-105918-structured-latency`
- exact result:
  - `curl_exit=28`
  - `http_code=000`
  - `time_total=120.006429`

Smaller request, no prewarm, later rerun:

- script:
  `MEASURE_MAX_TIME_SECONDS=120 MEASURE_ARTIFACT_DIR=artifacts/20260326-small-original-no-prewarm-rerun bash ./scripts/measure-self-hosted-structured-latency.sh artifacts/20260326-044926-codex-shim/0001-nim-chat-request.json`
- artifact dir:
  `artifacts/20260326-small-original-no-prewarm-rerun`
- exact result:
  - `curl_exit=0`
  - `http_code=200`
  - `time_total=77.603513`

Smaller request, with prewarm, 120s budget:

- script:
  `MEASURE_PREWARM_TOOL_PATH=1 bash ./scripts/measure-self-hosted-structured-latency.sh artifacts/20260326-044926-codex-shim/0001-nim-chat-request.json`
- artifact dir:
  `artifacts/20260326-110127-structured-latency`
- exact result:
  - `curl_exit=0`
  - `http_code=200`
  - `time_total=77.536565`

## Derived Variants

The comparison above still changes two major things at once:

- tool surface
- large user payload

To separate those, a helper script now derives targeted variants:

- script:
  `bash ./scripts/derive-request-shape-variants.sh <heavy> <small> <out-dir>`
- generated variant dir:
  `artifacts/request-shape-variants-20260326`

Generated variants:

- `heavy-small-user.json`
  - keeps the heavy tool surface
  - replaces only the large user payload with the smaller request's user block
- `heavy-small-tools.json`
  - keeps the heavy message surface
  - replaces only the tool surface with the smaller request's tool set
- `heavy-small-user-small-tools.json`
  - replaces both

## Variant Measurements

Heavy messages + small user only, with prewarm:

- request:
  `artifacts/request-shape-variants-20260326/heavy-small-user.json`
- artifact dir:
  `artifacts/20260326-heavy-small-user-prewarm`
- exact result:
  - `curl_exit=28`
  - `http_code=000`
  - `time_total=120.004285`

Heavy messages + small tools only, with prewarm:

- request:
  `artifacts/request-shape-variants-20260326/heavy-small-tools.json`
- artifact dir:
  `artifacts/20260326-heavy-small-tools-prewarm`
- exact result:
  - `curl_exit=0`
  - `http_code=200`
  - `time_total=77.395921`

Heavy messages + small user + small tools, with prewarm:

- request:
  `artifacts/request-shape-variants-20260326/heavy-small-user-small-tools.json`
- artifact dir:
  `artifacts/20260326-heavy-small-user-small-tools-prewarm`
- exact result:
  - `curl_exit=0`
  - `http_code=200`
  - `time_total=65.273231`

Heavy messages + small tools only, no prewarm:

- request:
  `artifacts/request-shape-variants-20260326/heavy-small-tools.json`
- artifact dir:
  `artifacts/20260326-heavy-small-tools-no-prewarm`
- exact result:
  - `curl_exit=0`
  - `http_code=200`
  - `time_total=77.609740`

Heavy messages + small user + small tools, no prewarm:

- request:
  `artifacts/request-shape-variants-20260326/heavy-small-user-small-tools.json`
- artifact dir:
  `artifacts/20260326-heavy-small-user-small-tools-no-prewarm`
- exact result:
  - `curl_exit=0`
  - `http_code=200`
  - `time_total=65.681709`

## Interpretation

The strongest current local read is:

- prewarm alone is not enough for the heavier request
- shrinking only the large user payload is not enough either
- tool-surface reduction is the dominant lever
- once the tool surface is reduced to the smaller successful set, the request
  can succeed without prewarm on the currently warmed service
- once the tool surface is reduced, trimming the large user payload still
  helps further, cutting the measured response time from about `77.6s` to about
  `65.7s`
- the earlier smaller-request/no-prewarm timeout means runtime state still
  matters; the non-prewarmed small-surface path is not perfectly stable enough
  yet to overclaim strict determinism

So the remaining self-hosted seam is now sharper than "NIM is slow":

- the structured path is still very sensitive to request mass
- the larger tool schema surface is the first-order contributor in the current
  measured split
- the large `AGENTS` user payload is still real, but looks like a second-order
  latency contributor once the tool surface is under control
- runtime warmness still modulates the smaller-surface path, so prewarm remains
  a useful stabilizer even though it is no longer the dominant lever
- the next technical move should be controlled request-surface minimization,
  not just more generic warmup retries
