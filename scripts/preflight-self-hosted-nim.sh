#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

status() {
  printf '%-28s %s\n' "$1" "$2"
}

fail_note=0

echo "Self-hosted NIM preflight"
printf 'root=%s\n' "$ROOT_DIR"
printf '\n'

arch="$(uname -m 2>/dev/null || echo unknown)"
status "arch" "$arch"
if [[ "$arch" != "x86_64" ]]; then
  fail_note=1
fi

os_pretty="$(
  lsb_release -ds 2>/dev/null \
    || awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null \
    || echo unknown
)"
status "os" "$os_pretty"

if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_line="$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | head -n 1)"
  status "nvidia-smi" "present"
  status "gpu" "$gpu_line"
else
  status "nvidia-smi" "missing"
  fail_note=1
fi

if command -v docker >/dev/null 2>&1; then
  status "docker" "$(docker --version)"
else
  status "docker" "missing"
  fail_note=1
fi

if command -v nvidia-ctk >/dev/null 2>&1; then
  status "nvidia-ctk" "$(nvidia-ctk --version | head -n 1)"
elif command -v nvidia-container-cli >/dev/null 2>&1; then
  status "nvidia-container-cli" "$(nvidia-container-cli --version | head -n 1)"
else
  status "nvidia-container-toolkit" "missing"
  fail_note=1
fi

mem_line="$(free -h 2>/dev/null | awk 'NR==2 {print $2 " total, " $7 " available"}' || true)"
if [[ -n "$mem_line" ]]; then
  status "memory" "$mem_line"
fi

disk_line="$(df -h / 2>/dev/null | awk 'NR==2 {print $4 " free on /"}' || true)"
if [[ -n "$disk_line" ]]; then
  status "disk" "$disk_line"
fi

if [[ -n "${NGC_API_KEY:-}" ]]; then
  status "NGC_API_KEY" "present"
else
  status "NGC_API_KEY" "missing"
  fail_note=1
fi

printf '\n'
if [[ "$fail_note" -eq 0 ]]; then
  echo "preflight=ready"
else
  echo "preflight=blocked"
fi
