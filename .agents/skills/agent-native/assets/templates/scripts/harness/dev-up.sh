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

# .NET Aspire (AppHost project)
apphost=$(find "$root_dir" -maxdepth 3 -name "*AppHost*.csproj" 2>/dev/null | head -1)
if [ -n "$apphost" ]; then
  echo "Aspire AppHost detected — starting: dotnet run --project $apphost"
  dotnet run --project "$apphost"
  exit 0
fi

# ─── Fallback: run the app locally in dev mode ─────────────────────

# Node.js
if [ -f "$root_dir/package.json" ]; then
  if node -e 'const p=require("./package.json"); process.exit(p.scripts&&p.scripts.dev?0:1)' 2>/dev/null; then
    echo "Starting: npm run dev"
    npm run dev
    exit 0
  fi
  if node -e 'const p=require("./package.json"); process.exit(p.scripts&&p.scripts.start?0:1)' 2>/dev/null; then
    echo "Starting: npm start"
    npm start
    exit 0
  fi
fi

# Python
if [ -f "$root_dir/pyproject.toml" ]; then
  if grep -qE "uvicorn|fastapi" "$root_dir/pyproject.toml" 2>/dev/null; then
    echo "Starting: uvicorn with reload"
    if command -v uv >/dev/null 2>&1; then
      uv run uvicorn app.main:app --reload --port 8080
    else
      python3 -m uvicorn app.main:app --reload --port 8080
    fi
    exit 0
  fi
  if grep -qE "flask" "$root_dir/pyproject.toml" 2>/dev/null; then
    echo "Starting: flask dev server"
    if command -v uv >/dev/null 2>&1; then
      uv run flask run --debug --port 8080
    else
      python3 -m flask run --debug --port 8080
    fi
    exit 0
  fi
fi

# Go
if [ -f "$root_dir/go.mod" ] && command -v go >/dev/null 2>&1; then
  echo "Starting: go run ."
  go run .
  exit 0
fi

# Rust
if [ -f "$root_dir/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
  echo "Starting: cargo run"
  cargo run
  exit 0
fi

# .NET (non-Aspire)
if ls "$root_dir"/*.csproj >/dev/null 2>&1 || ls "$root_dir"/*.sln >/dev/null 2>&1; then
  echo "Starting: dotnet run"
  dotnet run
  exit 0
fi

echo "ERROR: Cannot detect dev environment setup."
echo "Set HARNESS_DEV_UP_CMD or customize scripts/harness/dev-up.sh"
echo ""
echo "Examples:"
echo "  export HARNESS_DEV_UP_CMD='docker compose up -d && npm run dev'"
echo "  export HARNESS_DEV_UP_CMD='go run ./cmd/server'"
exit 1
