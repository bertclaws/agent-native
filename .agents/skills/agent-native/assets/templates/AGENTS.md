# AGENTS.md

> **CUSTOMIZE THIS FILE** — replace all `<placeholder>` values with real project info.
> Read `docs/OBSERVABILITY.md` and `docs/ARCHITECTURE.md` before writing code.

## Project Overview

- Project: `<project-name>`
- Primary runtime(s): `<runtime>`
- Main entrypoint(s): `<entrypoints>`

## Harness Commands

Run from repository root:

| Goal | Command |
|---|---|
| Fast sanity check | `make smoke` |
| Static checks | `make check` |
| Full test suite | `make test` |
| CI-equivalent local run | `make ci` |

## Constraints And Guardrails

- Prefer deterministic scripts over interactive/manual steps.
- Keep command names stable (`smoke`, `check`, `test`, `ci`).
- Update docs and scripts in the same change when workflow behavior changes.
- Avoid side effects outside the repo unless explicitly required.

## Architecture Boundaries

- Parse and validate external data at boundaries.
- Keep internal data models typed and normalized.
- Keep each module focused on one responsibility.
- **Enforce boundaries with lint rules** (see `docs/ARCHITECTURE.md` for examples).
- Customize `docs/ARCHITECTURE.md` with real module boundaries and execution flow — do not leave template boilerplate.

## Observability Convention

**Read `docs/OBSERVABILITY.md` for the full logging convention.**

Key rules:
- All structured logs write to `.harness/logs.jsonl`, traces to `.harness/traces.jsonl`
- Generate a `trace_id` per request and propagate it through context
- Track `duration_ms` per request
- **Level policy:** 2xx → INFO, 4xx → WARN, 5xx/exceptions → ERROR
- Required fields: `ts`, `level`, `msg`, `service`
- Customize `docs/OBSERVABILITY.md` with project-specific endpoint examples

## Execution Plans

- For tasks expected to exceed ~30 minutes, create/update `PLANS.md` before coding.
- Track scope, constraints, milestones, and verification steps.

## Static Analysis And Quality Gates

- Run `make check` before `make test`.
- Run `make ci` before pushing large refactors.
- Treat lint/type failures as blocking.
- **Minimum test coverage:** at least 5 meaningful tests covering core operations (CRUD, error cases, edge cases). Tests must verify real behavior, not just "assert True".

## Entropy Management

- Remove stale scripts/docs quickly.
- Keep templates and real workflows in sync.
- **Before considering setup complete, run:** `scripts/verify_customized.sh .` — it catches leftover template placeholders, stub scripts, and missing observability wiring.
- Run periodic harness audits: `scripts/audit_harness.sh .`
