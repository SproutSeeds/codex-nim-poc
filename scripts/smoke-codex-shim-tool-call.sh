#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

export SHIM_TOOL_ALLOWLIST="${SHIM_TOOL_ALLOWLIST:-exec_command}"
export SHIM_FORCE_SINGLE_TOOL_CHOICE="${SHIM_FORCE_SINGLE_TOOL_CHOICE:-1}"
export SHIM_PREWARM_TOOL_PATH="${SHIM_PREWARM_TOOL_PATH:-1}"
export NIM_PROMPT="${NIM_PROMPT:-You must call the exec_command tool exactly once. Run the command \`printf shim-tool-ok\` and then reply with exactly shim-tool-ok.}"
if [[ -z "${NIM_CHAT_EXTRA_BODY_JSON:-}" ]]; then
  # Temperature zero made the real self-hosted tool-call path materially more
  # stable and preserved the exact requested tool arguments in the strongest run.
  export NIM_CHAT_EXTRA_BODY_JSON='{"temperature":0}'
fi
export POC_CODEX_SANDBOX="${POC_CODEX_SANDBOX:-workspace-write}"

"$ROOT_DIR/scripts/smoke-codex-shim.sh"
