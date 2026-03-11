#!/usr/bin/env bash
set -euo pipefail

# DEV-DOWN — Stop the local development environment.
#
# Tears down services started by dev-up.
# Customize or set HARNESS_DEV_DOWN_CMD.

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root_dir"

if [ -n "${HARNESS_DEV_DOWN_CMD:-}" ]; then
  eval "$HARNESS_DEV_DOWN_CMD"
  exit 0
fi

# Docker Compose
if [ -f "$root_dir/docker-compose.yml" ] || [ -f "$root_dir/docker-compose.yaml" ] || [ -f "$root_dir/compose.yml" ] || [ -f "$root_dir/compose.yaml" ]; then
  echo "Stopping services via Docker Compose..."
  docker compose down
  echo "Dev environment down ✅"
  exit 0
fi

# Tilt
if [ -f "$root_dir/Tiltfile" ] && command -v tilt >/dev/null 2>&1; then
  echo "Stopping Tilt..."
  tilt down
  exit 0
fi

# Generic: kill background processes on common dev ports
echo "No Docker Compose or Tilt detected."
echo "Set HARNESS_DEV_DOWN_CMD or customize scripts/harness/dev-down.sh"
echo ""
echo "Examples:"
echo "  export HARNESS_DEV_DOWN_CMD='docker compose down && pkill -f uvicorn'"
exit 1
