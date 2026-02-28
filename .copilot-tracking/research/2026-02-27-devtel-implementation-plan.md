# devtel — Implementation Plan (v3)

**Date:** 2026-02-28  
**Status:** Ready to build  
**Repo:** `~/src/devtel`

---

## Architecture

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

**No external binaries. No Docker. No extra processes. No 1-star dependencies.**

Custom OTel SDK exporters write directly to a SQLite DB in the worktree. The `devtel` CLI queries it. Everything is in one npm package.

---

## Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Storage | SQLite (WAL mode) | Indexed, joins, concurrent r/w, zero infra |
| Collection | Custom OTel exporters (in-process) | No extra binary, no dependency risk, ~50 lines each |
| Query | CLI (`devtel`) | Agent-friendly, SQL escape hatch |
| Scope | Node.js first | Concrete use case; Python/multi-lang via OTLP receiver later |
| Distribution | npm package | `npx devtel` or install globally |

---

## SQLite Schema (our own)

**File:** `.devtel/telemetry.db`

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;

CREATE TABLE IF NOT EXISTS spans (
  trace_id     TEXT NOT NULL,
  span_id      TEXT NOT NULL,
  parent_id    TEXT,
  name         TEXT NOT NULL,
  service      TEXT NOT NULL,
  kind         INTEGER DEFAULT 0,
  start_ns     INTEGER NOT NULL,
  end_ns       INTEGER,
  status       INTEGER DEFAULT 0,
  status_msg   TEXT,
  attributes   TEXT,
  events       TEXT,
  PRIMARY KEY (trace_id, span_id)
);

CREATE TABLE IF NOT EXISTS logs (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp_ns INTEGER NOT NULL,
  trace_id     TEXT,
  span_id      TEXT,
  severity     INTEGER,
  level        TEXT NOT NULL DEFAULT 'INFO',
  body         TEXT,
  service      TEXT,
  attributes   TEXT
);

CREATE TABLE IF NOT EXISTS metrics (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp_ns INTEGER NOT NULL,
  name         TEXT NOT NULL,
  service      TEXT,
  kind         TEXT NOT NULL,
  value        REAL,
  unit         TEXT,
  attributes   TEXT,
  bounds       TEXT,
  counts       TEXT
);

CREATE INDEX IF NOT EXISTS idx_spans_start ON spans(start_ns);
CREATE INDEX IF NOT EXISTS idx_spans_status ON spans(status) WHERE status = 2;
CREATE INDEX IF NOT EXISTS idx_logs_ts ON logs(timestamp_ns);
CREATE INDEX IF NOT EXISTS idx_logs_level ON logs(level);
CREATE INDEX IF NOT EXISTS idx_logs_trace ON logs(trace_id) WHERE trace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_metrics_name_ts ON metrics(name, timestamp_ns);
```

---

## Repo Structure

```
~/src/devtel/
  package.json
  tsconfig.json
  vitest.config.ts
  src/
    cli.ts                  # Commander entry
    db.ts                   # Open/init SQLite DB, ensure schema + WAL
    schema.ts               # CREATE TABLE statements as string constants
    exporters/
      span-exporter.ts      # implements SpanExporter → INSERT INTO spans
      log-exporter.ts       # implements LogRecordExporter → INSERT INTO logs
      metric-exporter.ts    # implements PushMetricExporter → INSERT INTO metrics
    init.ts                 # devtel/init — auto-configures OTel SDK with our exporters
    commands/
      init-cmd.ts           # devtel init — create .devtel dir + DB + .devtel.env
      status.ts             # devtel status
      clean.ts              # devtel clean
      logs.ts               # devtel logs
      traces.ts             # devtel traces
      metrics.ts            # devtel metrics
      query.ts              # devtel query "SQL"
    util/
      time.ts               # "5m" → nanoseconds
      format.ts             # Output formatting
  tests/
    db.test.ts
    exporters.test.ts
    logs.test.ts
    traces.test.ts
    metrics.test.ts
    query.test.ts
  SKILL.md
  README.md
```

---

## Dependencies

**Runtime:**
- `better-sqlite3` — sync SQLite for CLI queries
- `commander` — CLI framework
- `ms` — parse duration strings
- `@opentelemetry/api` — OTel types
- `@opentelemetry/sdk-trace-base` — SpanExporter interface
- `@opentelemetry/sdk-logs` — LogRecordExporter interface
- `@opentelemetry/sdk-metrics` — PushMetricExporter interface
- `@opentelemetry/sdk-node` — NodeSDK for the init helper
- `@opentelemetry/auto-instrumentations-node` — auto-instrumentation for init helper

**Dev:**
- `typescript`, `vitest`, `@types/better-sqlite3`, `@types/node`

---

## Build Steps

### Step 1: Scaffold + DB + Schema

1. `npm init`, install all deps, tsconfig (ES2022, Node16, outDir: dist, ESM)
2. `src/schema.ts` — SQL strings for creating tables + indexes
3. `src/db.ts` — `openDb(dbPath)`: open SQLite, run schema DDL, set WAL mode, return db handle. `getDefaultDbPath()`: resolves `.devtel/telemetry.db` from cwd

### Step 2: Custom OTel Exporters

Each exporter implements the standard OTel interface and batch-inserts into SQLite.

**`src/exporters/span-exporter.ts`:**
```typescript
import { SpanExporter, ReadableSpan } from '@opentelemetry/sdk-trace-base';
// export(spans) → INSERT INTO spans VALUES (?, ?, ...) for each span
// Convert span.spanContext().traceId, spanId, parentSpanId, name, etc.
// Attributes → JSON.stringify
// shutdown() → no-op (ephemeral)
```

**`src/exporters/log-exporter.ts`:**
```typescript
import { LogRecordExporter, ReadableLogRecord } from '@opentelemetry/sdk-logs';
// export(logs) → INSERT INTO logs VALUES (?, ?, ...)
// Map severityNumber, severityText, body, traceId, spanId
```

**`src/exporters/metric-exporter.ts`:**
```typescript
import { PushMetricExporter, ResourceMetrics } from '@opentelemetry/sdk-metrics';
// export(metrics) → INSERT INTO metrics VALUES (?, ?, ...)
// Handle gauge, counter, histogram data points
// For histograms: store bounds + counts as JSON arrays
```

### Step 3: `devtel/init` Auto-Instrumentation Helper

```typescript
// src/init.ts — import "devtel/init" at app entry point
// 1. Check if .devtel/telemetry.db exists (or .devtel/ dir)
// 2. If not, no-op silently
// 3. If yes, configure NodeSDK with our custom exporters pointing at that DB
// 4. Register auto-instrumentations
// 5. sdk.start()
```

This replaces the need for sqlite-otel entirely. One import line and you're instrumented.

### Step 4: CLI Commands — `init`/`status`/`clean`

**`devtel init`:**
- `mkdir -p .devtel`
- Create and init `.devtel/telemetry.db` (run schema DDL)
- Write `.devtel.env` — NOT for OTLP endpoint (no collector!), but as a marker + convenience:
  ```
  DEVTEL_ACTIVE=true
  DEVTEL_DB=.devtel/telemetry.db
  OTEL_SERVICE_NAME=${basename(cwd)}
  ```
- Add `.devtel/` and `.devtel.env` to `.gitignore` if not already there
- Print summary

**`devtel status`:**
- Check `.devtel/telemetry.db` exists
- Count rows in each table, show time range, DB file size

**`devtel clean`:**
- `rm -rf .devtel/ .devtel.env`

### Step 5: CLI Query Commands

Same as before but querying our own schema (no guesswork):

**`devtel logs`** — `--level`, `--last`, `--grep`, `--trace`, `--limit` (20), `--json`
**`devtel traces`** — default: root spans; `--slow`, `--errors`, `--name`, `--id` (waterfall tree), `--limit` (20), `--json`
**`devtel metrics`** — default: list names; `--name`, `--agg` (avg/p50/p95/p99/max/min), `--last`, `--json`
**`devtel query "SQL"** — raw pass-through

Trace waterfall for `--id`:
```
GET /api/users (245ms) ✓
  ├─ middleware.auth (12ms) ✓
  ├─ db.query SELECT users (180ms) ✓
  └─ serialize.response (8ms) ✓
```

### Step 6: SKILL.md + README

Agent skill doc + human docs.

---

## How It Works (User Experience)

```bash
# In any Node.js project:
npm install devtel

# Initialize (creates .devtel/ with empty SQLite DB)
npx devtel init

# Add one import to your app entry point:
# import "devtel/init";

# Start your app — OTel auto-instruments, writes to SQLite
npm run dev

# Query from another terminal (or let your coding agent do it):
npx devtel logs --level error --last 5m
npx devtel traces --slow 500ms
npx devtel traces --id abc123
npx devtel query "SELECT * FROM spans WHERE name LIKE '%auth%'"

# Clean up when done
npx devtel clean
```

---

## Important Implementation Notes

1. **We own the schema.** No discovery step needed — we define the tables.
2. **Exporters are ~50 lines each.** The OTel SDK does the heavy lifting (batching, flushing). We just implement `export()` and `shutdown()`.
3. **better-sqlite3 is synchronous** — perfect for CLI queries, and the OTel export() callbacks can use it too since they're called in batch intervals.
4. **WAL mode is critical** — app writes + CLI reads concurrently.
5. **The init helper must be importable as `"devtel/init"`** — use package.json `exports` field to map this.
6. **Nanosecond timestamps** throughout (OTel standard). Duration computed in queries: `(end_ns - start_ns) / 1e6` for milliseconds.
7. **Graceful degradation** — if .devtel/ doesn't exist, init helper no-ops. If DB is empty, query commands say "no data".
8. **ESM throughout** — `"type": "module"` in package.json.
