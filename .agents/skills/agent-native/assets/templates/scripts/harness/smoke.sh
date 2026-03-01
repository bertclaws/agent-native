#!/usr/bin/env bash
set -euo pipefail

# SMOKE TEST — Verify the app starts, responds, and shuts down cleanly.
#
# This script MUST:
#   1. Start the application server in the background
#   2. Wait for it to become ready (poll a health endpoint)
#   3. Make at least one request to verify it works
#   4. Kill the server and exit
#
# Customize the variables below for your project.
# See docs/OBSERVABILITY.md for the logging convention.

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root_dir"

# ─── CUSTOMIZE THESE ───────────────────────────────────────────────
# START_CMD: command to start the server (backgrounded automatically)
# HEALTH_URL: endpoint to poll for readiness
# SMOKE_URL: endpoint to hit for a basic functional check
# PORT: port your server listens on

START_CMD="${HARNESS_SMOKE_START_CMD:-}"    # e.g. "uv run uvicorn app.main:app --port 8080"
HEALTH_URL="${HARNESS_SMOKE_HEALTH_URL:-http://localhost:8080/health}"
SMOKE_URL="${HARNESS_SMOKE_URL:-http://localhost:8080/}"
PORT="${HARNESS_SMOKE_PORT:-8080}"
READY_TIMEOUT=15  # seconds to wait for server readiness

# ─── AUTO-DETECT START COMMAND (if not set) ────────────────────────
if [ -z "$START_CMD" ]; then
  if [ -f "$root_dir/pyproject.toml" ]; then
    # Python — try uvicorn, then gunicorn
    if grep -q "uvicorn" "$root_dir/pyproject.toml" 2>/dev/null; then
      START_CMD="uv run uvicorn app.main:app --host 0.0.0.0 --port $PORT"
    elif grep -q "fastapi" "$root_dir/pyproject.toml" 2>/dev/null; then
      START_CMD="uv run fastapi run --port $PORT"
    fi
  elif [ -f "$root_dir/package.json" ]; then
    # Node.js — try npm start
    if node -e 'const p=require("./package.json"); process.exit(p.scripts&&p.scripts.start?0:1)' 2>/dev/null; then
      START_CMD="npm run -s start"
    fi
  elif [ -f "$root_dir/go.mod" ]; then
    # Go
    START_CMD="go run ."
  elif [ -f "$root_dir/*.csproj" ] || ls "$root_dir"/*.csproj >/dev/null 2>&1; then
    # C#
    START_CMD="dotnet run --urls http://0.0.0.0:$PORT"
  fi
fi

if [ -z "$START_CMD" ]; then
  echo "ERROR: Cannot detect start command."
  echo "Set HARNESS_SMOKE_START_CMD or customize scripts/harness/smoke.sh"
  exit 1
fi

# ─── CLEANUP TRAP ──────────────────────────────────────────────────
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ─── START SERVER ──────────────────────────────────────────────────
echo "Starting server: $START_CMD"
$START_CMD &
SERVER_PID=$!

# ─── WAIT FOR READY ───────────────────────────────────────────────
echo "Waiting for server on $HEALTH_URL (timeout: ${READY_TIMEOUT}s)..."
elapsed=0
while [ "$elapsed" -lt "$READY_TIMEOUT" ]; do
  if curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
    echo "Server ready after ${elapsed}s"
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "$elapsed" -ge "$READY_TIMEOUT" ]; then
  echo "ERROR: Server did not become ready within ${READY_TIMEOUT}s"
  exit 1
fi

# ─── SMOKE REQUESTS ───────────────────────────────────────────────
echo "Hitting smoke endpoint: $SMOKE_URL"
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "$SMOKE_URL" 2>&1 || echo "000")
if [ "$HTTP_CODE" = "000" ]; then
  echo "ERROR: Smoke request failed (no response)"
  exit 1
fi
echo "Smoke response: HTTP $HTTP_CODE"

# ─── DONE ─────────────────────────────────────────────────────────
echo "Smoke test passed ✅"
