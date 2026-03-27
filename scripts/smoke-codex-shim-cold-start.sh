#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${POC_CODEX_MINIMAL_PROFILE:=1}"
: "${SHIM_RESTART_REMOTE_NIM:=1}"
: "${SHIM_PREWARM_REQUEST_JSON:=$ROOT_DIR/configs/nim.minimal-profile.prewarm-request.json}"
: "${SHIM_PREWARM_REQUEST_MAX_TIME_SECONDS:=300}"

export POC_CODEX_MINIMAL_PROFILE
export SHIM_RESTART_REMOTE_NIM
export SHIM_PREWARM_REQUEST_JSON
export SHIM_PREWARM_REQUEST_MAX_TIME_SECONDS

bash "$ROOT_DIR/scripts/smoke-codex-shim.sh"
