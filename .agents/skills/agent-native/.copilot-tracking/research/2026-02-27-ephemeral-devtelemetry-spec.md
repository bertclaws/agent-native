# Ephemeral Dev Telemetry Stack — Specification (v3)

**Author:** Bert (Researcher) for Andrew Vineyard  
**Date:** 2026-02-27 (revised 2026-02-28)  
**Status:** Ready to build  
**Inspired by:** [OpenAI Harness Engineering](https://openai.com/index/harness-engineering/)

---

## 1. Problem Statement

Coding agents (Codex, Claude Code, Copilot CLI, etc.) operating in a local development environment are blind to runtime behavior. They can read code but can't observe:
- What errors are actually happening at runtime
- Which requests are slow and why
- How data flows through the system (distributed traces)
- Whether a fix they just applied actually improved things

## 2. Goals

1. **Zero-config for the developer** — `npm install devtel`, one import, done
2. **Standard protocols** — built on OpenTelemetry SDK (auto-instrumentation)
3. **Agent-queryable** — CLI queries logs, traces, metrics from SQLite; SQL escape hatch
4. **No external dependencies** — no Docker, no Go binaries, no 1-star repos, no extra processes
5. **Per-worktree isolation** — `.devtel/telemetry.db` per project
6. **Ephemeral by default** — gitignored, `devtel clean` removes everything

## 3. Architecture

```
┌──────────────────────────────────────────────────┐
│                Developer Worktree                │
│                                                  │
│  ┌──────────┐   OTel SDK        ┌────────────┐  │
│  │  App      │ ─── custom ─────▶│ .devtel/   │  │
│  │ (Node.js) │   exporters      │ telemetry  │  │
│  └──────────┘   (in-process)    │ .db        │  │
│                                 └─────┬──────┘  │
│                                       │          │
│  ┌──────────┐  devtel CLI (SQL)       │          │
│  │  Agent    │ ◀──────────────────────┘          │
│  └──────────┘                                    │
└──────────────────────────────────────────────────┘
```

**No extra processes.** Custom OTel exporters (SpanExporter, LogRecordExporter, PushMetricExporter) write directly to SQLite in-process. The `devtel` CLI queries the same DB file.

### 3.1 Components

| Component | Implementation | Role |
|---|---|---|
| **Telemetry Collection** | Custom OTel SDK exporters (~50 lines each) | In-process, batch INSERT into SQLite |
| **Storage** | SQLite (WAL mode, `.devtel/telemetry.db`) | Indexed, joinable, concurrent r/w |
| **Auto-Instrumentation** | `import "devtel/init"` | Configures OTel NodeSDK with custom exporters + auto-instrumentations |
| **Query Layer** | `devtel` CLI | Queries SQLite, renders agent-friendly output |

### 3.2 Why custom exporters (not an external collector)

- **Zero dependencies** — no Go binary, no Docker, no process to manage
- **We own the schema** — no guessing, no schema discovery, no breaking changes from upstream
- **In-process** — no network hop, no port management, no process lifecycle
- **~150 lines total** — three exporters, each trivial
- **The OTel SDK handles everything else** — batching, flushing, context propagation, auto-instrumentation

### 3.3 Future: Multi-Language Support

For Python/C#/etc., add a lightweight OTLP/HTTP → SQLite receiver (~100 lines Node.js) that accepts standard OTLP and writes to the same schema. This is additive — doesn't change the Node.js path.

## 4. User Experience

```bash
npm install devtel

# Initialize
npx devtel init

# Add to app entry:
# import "devtel/init";

# Start app → auto-instrumented, writes to .devtel/telemetry.db
npm run dev

# Query (from agent or terminal):
npx devtel logs --level error --last 5m
npx devtel traces --slow 500ms
npx devtel traces --id <trace_id>    # waterfall tree
npx devtel query "SELECT ..."        # SQL escape hatch

# Clean up
npx devtel clean
```

## 5. CLI Commands

```bash
devtel init            # Create .devtel/ dir, init DB, write .devtel.env
devtel status          # Show DB stats (row counts, time range, file size)
devtel clean           # Delete .devtel/ and .devtel.env

devtel logs [options]              # Query logs
  --level <level>                  # Filter by severity
  --last <duration>                # Time window (5m, 1h, 30s)
  --grep <text>                    # Body text search
  --trace <id>                     # Logs for a trace
  --limit <n>                      # Max results (default 20)
  --json                           # JSON output

devtel traces [options]            # Query traces
  --slow <duration>                # Min duration filter
  --errors                         # Error spans only
  --name <pattern>                 # Span name filter (supports *)
  --id <trace_id>                  # Full trace waterfall tree
  --limit <n>                      # Max results (default 20)
  --json                           # JSON output

devtel metrics [options]           # Query metrics
  --name <name>                    # Filter by metric name
  --agg <fn>                       # Aggregation (avg, p50, p95, p99, max, min)
  --last <duration>                # Time window
  --json                           # JSON output

devtel query "SQL"                 # Raw SQL escape hatch
```

## 6. Agent Skill Definition

```markdown
# devtel — Runtime Observability

When debugging runtime errors, performance issues, or verifying a fix:

1. `devtel init` if `.devtel/` doesn't exist
2. Add `import "devtel/init"` to the app entry point (once)
3. Restart the app
4. Reproduce the issue
5. Query:
   - `devtel logs --level error --last 5m`
   - `devtel traces --errors --last 5m`
   - `devtel traces --id <trace_id>` for full trace tree
   - `devtel query "SELECT ..."` for anything complex
6. Fix, restart, re-query to confirm
7. `devtel clean` when done
```

## 7. Production Parity

Same OTel SDK in production — just don't import `devtel/init`. Use your production exporter (App Insights, Datadog, etc.) instead. The instrumentation code is identical.

## 8. Open Questions

1. Should `devtel/init` check for `.devtel/` dir or a specific env var to activate?
2. npm package scope: `devtel` (unscoped) or `@devtel/cli`?
3. Ship as OpenClaw skill once stable?

---

*v3: Removed sqlite-otel dependency. Custom OTel exporters write directly to SQLite. No external binaries.*
