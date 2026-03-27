## Self-Hosted Minimal-Profile Proof

Date: March 26, 2026

## Goal

Turn the earlier request-shape diagnosis into a reproducible real `codex exec`
path, then separate:

- already-warm service behavior
- true cold-start behavior after a remote NIM restart

## Warm Minimal-Profile Codex Runs

Harness:

- script:
  `scripts/smoke-codex-shim.sh`
- patched Codex binary:
  `/Volumes/Code_2TB/code/collaboration/codex/.worktrees/issue-5458-provider-model-metadata/codex-rs/target/debug/codex`
- key harness knobs:
  - `POC_CODEX_MINIMAL_PROFILE=1`
  - per-artifact `CODEX_HOME`
  - per-artifact `minimal-root`
  - `--ephemeral`

Patched minimal profile, with tool-path prewarm:

- artifact dir:
  `artifacts/20260326-minimal-profile-smoke-patched`
- exact result:
  - fallback-metadata warning: absent
  - final assistant output: `OK`

Patched minimal profile, no prewarm:

- command:
  `POC_CODEX_BIN=... POC_CODEX_MINIMAL_PROFILE=1 /usr/bin/time -p bash ./scripts/smoke-codex-shim.sh`
- artifact dir:
  `artifacts/20260326-minimal-profile-smoke-patched-no-prewarm`
- exact result:
  - final assistant output: `OK`
  - `real 69.47`

The minimal-profile request shape on the successful no-prewarm warm run was:

- Codex request:
  - `tools_len: 11`
  - `user_join_len: 314`
- translated NIM chat request:
  - `tools_len: 10`
  - roles:
    - `system`
    - `system`
    - `user`
    - `user`

## Cold-Start Direct Replay Follow-Up

To separate warm-service success from true cold-start behavior, the exact saved
minimal-profile NIM chat request was replayed through:

- script:
  `scripts/measure-self-hosted-structured-latency.sh`
- request:
  `artifacts/20260326-minimal-profile-smoke-patched-no-prewarm/0001-nim-chat-request.json`
- remote restart:
  - `MEASURE_RESTART_REMOTE_NIM=1`

Cold start, no prewarm:

- artifact dir:
  `artifacts/20260326-minimal-profile-cold-no-prewarm`
- exact result:
  - `curl_exit=28`
  - `http_code=000`
  - `time_total=120.006586`

Cold start, existing tool-path prewarm:

- artifact dir:
  `artifacts/20260326-minimal-profile-cold-prewarm`
- exact result:
  - `curl_exit=28`
  - `http_code=000`
  - `time_total=120.004516`

## Earlier Small-Success Request Under True Restart

The earlier smaller request that had succeeded on a warmed service with
prewarm was then replayed through the same true-restart path:

- request:
  `artifacts/20260326-044926-codex-shim/0001-nim-chat-request.json`
- artifact dir:
  `artifacts/20260326-small-success-cold-prewarm`
- exact result:
  - `curl_exit=28`
  - `http_code=000`
  - `time_total=120.004297`

## Structural Comparison

The earlier smaller successful request and the new minimal-profile request are
closer than they first looked:

- both have:
  - `tools_len: 10` on the NIM chat request
  - the same ten tool names
  - the same role sequence
  - `parallel_tool_calls: false`
- main remaining size delta:
  - earlier small-success request `user_text_len: 241`
  - minimal-profile request `user_text_len: 314`

The largest visible diff is path text in:

- skill file paths under the per-artifact `codex-home`
- the `<environment_context>` cwd path

## Interpretation

The strongest current read is:

- the minimal-profile harness is real and reproducible on an already-warm
  service
- the patched binary plus per-artifact writable `CODEX_HOME` removes the old
  fallback-warning and shared-home noise from that proof
- on a true remote restart, the current tool-path prewarm is not enough to
  carry even the smaller known-good request under the current `120s` budget
- so the remaining seam is not just "minimal profile got slightly too big"
- the sharper seam is:
  - already-warm structured path: works
  - true cold-start structured path after restart: still exceeds the current
    budget, even with the existing tool-path prewarm

## Exact-Request Prewarm Follow-Up

To test whether the real remaining seam was simply "wrong prewarm target," the
latency harness was extended with an exact-request prewarm phase:

- harness knob:
  - `MEASURE_PREWARM_EXACT_REQUEST=1`
- prewarm budget:
  - `MEASURE_PREWARM_MAX_TIME_SECONDS=300`
- request:
  `artifacts/20260326-minimal-profile-smoke-patched-no-prewarm/0001-nim-chat-request.json`

True restart, exact-request prewarm, then timed second request:

- artifact dir:
  `artifacts/20260326-minimal-profile-cold-exact-prewarm`
- exact prewarm result:
  - `prewarm_request_exit=0`
  - `prewarm_request_http_code=200`
  - `prewarm_request_time_total=187.466568`
- exact timed second-request result:
  - `curl_exit=0`
  - `http_code=200`
  - `time_total=58.247264`

This is the strongest cold-start refinement so far.

## End-To-End Codex Follow-Up

The exact-request prewarm result was then carried into the real Codex smoke
path.

Reusable hook:

- `scripts/smoke-codex-shim.sh` now supports:
  - `SHIM_PREWARM_REQUEST_JSON`
  - `SHIM_PREWARM_REQUEST_MAX_TIME_SECONDS`

True restart, exact-request prewarm, then real patched Codex minimal-profile
smoke:

- artifact dir:
  `artifacts/20260326-minimal-profile-cold-codex-exact-prewarm`
- exact result:
  - final assistant output: `OK`
  - end-to-end wall-clock:
    - `real 309.78`
  - the artifact also records the exact-request prewarm summary under:
    - `prewarm-exact-request/summary.txt`

So the current strongest local story is no longer just:

- warm service works
- cold start times out

It is now:

- warm minimal-profile Codex path works
- cold structured request path still times out under the old tool-path prewarm
- exact-request prewarm can carry the cold path
- and that exact-request prewarm now also carries the real end-to-end Codex
  smoke after a true restart

The next useful refinement is no longer generic request slimming. It is
cold-start-specific packaging, for example:

- carrying exact-request prewarm into a reusable end-to-end Codex smoke
- or finding a NIM/runtime lever that lowers the first structured-request
  compile cost enough that a separate prewarm is unnecessary

## One-Command Wrapper Packaging

That cold-start packaging now exists as a checked-in wrapper plus fixture:

- wrapper:
  - `scripts/smoke-codex-shim-cold-start.sh`
- fixture:
  - `configs/nim.minimal-profile.prewarm-request.json`

Strongest wrapper proof:

- artifact dir:
  - `artifacts/20260326-cold-start-wrapper`
- exact-request prewarm summary:
  - `prewarm_request_exit=0`
  - `prewarm_request_http_code=200`
  - `prewarm_request_time_total=180.839636`
- exact end-to-end result:
  - final assistant output: `OK`
  - end-to-end wall-clock:
    - `real 323.73`

So the cold-start workaround is no longer just a measured manual sequence.
It is now a reusable one-command path backed by a checked-in fixture.
