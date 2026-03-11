#!/usr/bin/env bash
set -euo pipefail

# DEV-UP — Start the local development environment.
#
# Brings up everything the app needs to run locally:
# databases, caches, message brokers, the app itself, etc.
#
# Auto-detects common patterns. Customize or set HARNESS_DEV_UP_CMD.

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root_dir"

if [ -n "${HARNESS_DEV_UP_CMD:-}" ]; then
  eval "$HARNESS_DEV_UP_CMD"
  exit 0
fi

# Docker Compose (most common for multi-service)
if [ -f "$root_dir/docker-compose.yml" ] || [ -f "$root_dir/docker-compose.yaml" ] || [ -f "$root_dir/compose.yml" ] || [ -f "$root_dir/compose.yaml" ]; then
  echo "Starting services via Docker Compose..."
  docker compose up -d
  echo "Dev environment up ✅"
  echo "Run 'make dev-down' to stop."
  exit 0
fi

# Devcontainer (VS Code / Codespaces)
if [ -f "$root_dir/.devcontainer/devcontainer.json" ] || [ -f "$root_dir/.devcontainer.json" ]; then
  echo "Devcontainer detected — use 'Dev Containers: Reopen in Container' in VS Code"
  echo "or 'devcontainer up --workspace-folder .' if devcontainer CLI is installed."
  exit 0
fi

# Tilt (Kubernetes dev)
if [ -f "$root_dir/Tiltfile" ] && command -v tilt >/dev/null 2>&1; then
  echo "Starting Tilt..."
  tilt up
  exit 0
fi

# .NET Aspire
if grep -rq "Aspire" "$root_dir"/*.csproj "$root_dir"/**/*.csproj 2>/dev/null; then
  echo "Aspire project detected — starting with dotnet run..."
  local apphost
  apphost=$(find "$root_dir" -name "*.AppHost.csproj" -o -name "*AppHost.csproj" | head -1)
  if [ -n "$apphost" ]; then
    dotnet run --project "$apphost"
  else
    dotnet run
  fi
  exit 0
fi

# Fallback: just run the app in dev mode
if [ -f "$root_dir/package.json" ]; then
  if node -e 'const p=require("./package.json"); process.exit(p.scripts&&p.scripts.dev?0:1)' 2>/dev/null; then
    echo "Starting: npm run dev"
    npm run dev
    exit 0
  fi
fi

if [ -f "$root_dir/pyproject.toml" ]; then
  if grep -qE "uvicorn|fastapi" "$root_dir/pyproject.toml" 2>/dev/null; then
    echo "Starting: uvicorn with reload"
    uv run uvicorn app.main:app --reload --port 8080
    exit 0
  fi
fi

echo "ERROR: Cannot detect dev environment setup."
echo "Set HARNESS_DEV_UP_CMD or customize scripts/harness/dev-up.sh"
echo ""
echo "Examples:"
echo "  export HARNESS_DEV_UP_CMD='docker compose up -d && npm run dev'"
echo "  export HARNESS_DEV_UP_CMD='tilt up'"
exit 1
