# Theory: Agent-Native Repositories

## Problem

AI coding agents fail in most repositories — not because the models are weak, but because the repositories are hostile to non-human developers. The same codebase that a senior engineer navigates fluently (through tribal knowledge, IDE affordances, Slack threads, and years of context) becomes an opaque maze for an agent that starts each session from zero.

The core structural issue: repositories evolved for humans who accumulate context over months. Agents are ephemeral. They get a fresh checkout, no memory, and a token budget. Every undocumented convention, every "just ask Sarah" workflow, every implicit assumption about which make target to run — these are invisible walls. The agent wastes its reasoning budget rediscovering what any team member already knows, and often gets it wrong.

This is not a model problem. It's an environment problem. The same agent that flails in an undocumented monorepo scores near-perfect in a repo with clear instructions, deterministic commands, and observable execution. The delta is the repo, not the agent.

## Operating Theory

Agent-native is a direct analogy to cloud-native. In the early 2010s, applications worked fine on hand-configured servers but failed in containerized, orchestrated environments. The fix wasn't better containers — it was redesigning applications to be cloud-native: health endpoints, structured logging, 12-factor configuration, declarative infrastructure. The applications adapted to the new execution environment.

The same transition is happening now with AI agents as the new execution environment. A Dockerfile is to cloud-native what AGENTS.md is to agent-native. Kubernetes manifests map to Makefile.harness and scripts/. Health endpoints map to smoke.sh. Structured logging maps to OBSERVABILITY.md with JSONL and level policies. The parallel is precise, not metaphorical.

The key insight from OpenAI's harness engineering research is that nine specific practices account for most of the variance in agent performance. These aren't vague principles — they're concrete, artifact-producing practices: single-command wrappers, compact actionable docs, strict architectural boundaries, built-in observability, durable planning context, repo-local deterministic workflows, natural-language prototyping, static analysis investment, and entropy management. When a repo implements all nine, agents succeed reliably across models and tasks. When it doesn't, even the best models struggle.

The harness engineering playbook operationalizes these nine practices into installable artifacts. `bootstrap_harness.sh` drops in the full scaffold — AGENTS.md, architecture docs, observability conventions, a Makefile with stable entrypoints, real scripts behind those entrypoints, and audit tooling. The verification layer (`verify_customized.sh`, `audit_harness.sh`) ensures the setup isn't just template boilerplate but actually customized for the specific project.

## Strategy

The approach is layered and progressive, designed to make the easy path the correct path.

**Layer 1: Deterministic command surface.** Everything an agent needs to do maps to a stable command: `make setup`, `make format`, `make smoke`, `make check`, `make ci`. Behind these are real scripts in `scripts/harness/` that auto-detect the project's language and tooling. The agent never guesses; it reads AGENTS.md and executes. This eliminates the single largest failure mode: agents improvising build/test commands that don't exist or don't work. Setup handles dependency installation across all supported ecosystems, format auto-applies code formatters, and smoke tests adapt to the project type — HTTP servers, CLI tools, and libraries are all covered via auto-detection or the `HARNESS_SMOKE_MODE` override.

**Layer 2: Structured observability.** JSONL logs and traces with required fields (`ts`, `level`, `msg`, `service`, `trace_id`, `duration_ms`) give agents the same debugging surface that a human gets from reading stack traces and log output. The level policy (2xx→INFO, 4xx→WARN, 5xx→ERROR) makes severity machine-parseable. jq queries against `.harness/logs.jsonl` and `.harness/traces.jsonl` are the zero-dependency default; devtel is the upgrade path when scale demands it.

**Layer 3: Architectural guardrails.** ARCHITECTURE.md makes module boundaries explicit and pairs them with lint rules for enforcement. This prevents the most expensive agent failure: technically correct changes that violate architectural intent and create coupling that compounds over subsequent changes.

**Layer 4: Control system model.** The most ambitious layer borrows from control theory. The `docs/control/` templates model the autonomous development loop as a feedback system: setpoints (PR pass@1 rate, merge cycle time, revert rate), sensors (CI results, traces, eval outcomes), actuators (code edits, script updates, CI adjustments), and a controller that decides corrective actions. This reframes agent supervision from ad-hoc review to measurable closed-loop control with explicit error budgets and escalation rules.

The layering matters because adoption is progressive. A team can get 80% of the value from layers 1 and 2 alone. The control system model (layer 4) is where the framework points toward fully autonomous development loops — but it's aspirational infrastructure, not a prerequisite.

## Key Discoveries

**The playbook carries the weight, not the model.** Evaluation rounds across Codex and Opus demonstrated this clearly. Round 1 with hand-held Codex scored 23.25/25. Round 2 with minimal-guidance Codex dropped to 21.50 — exposing playbook gaps, not model gaps. After fixing the playbook, Round 3 with Opus hit 24.50 and Round 4 with Codex reached 24.75. The improvement tracked playbook quality, not model capability. This is the strongest evidence that the environment is the bottleneck.

**Verification must be layered.** A single `make ci` isn't enough. The framework uses three distinct verification commands: `make ci` (functional correctness), `verify_customized.sh` (catches leftover template boilerplate), and `audit_harness.sh` (structural integrity of the harness itself). Each catches a different class of failure that the others miss.

**Entropy is the real enemy.** Practice 9 exists because the other eight practices decay naturally. Scripts drift from docs. Docs drift from reality. Flaky tests get ignored. Logging field names mutate. The entropy management layer — periodic audits, drift detection, nightly CI harness checks — is what makes the framework durable rather than a one-time setup that rots.

**Agent hooks are the enforcement mechanism.** Pre-tool hooks (protect linter configs, enforce package managers, platform shims) prevent agents from making well-intentioned but destructive changes. The hooks run before the agent's tool calls execute, creating a safety layer that doesn't depend on the agent's judgment.

## Open Questions

**Does the control system model actually close the loop?** The `docs/control/` templates define setpoints, sensors, actuators, and feedback loops — but these are currently unfilled templates. No repo has yet demonstrated a fully autonomous development loop with measurable error budgets and automatic corrective action. The framework provides the structure, but whether teams will actually instrument their repos to this degree is untested. It may be that the control theory framing is more useful as a mental model than as literal operational infrastructure.

**Where is the boundary between agent-native and over-engineering?** The full scaffold is substantial: AGENTS.md, ARCHITECTURE.md, OBSERVABILITY.md, Makefile.harness, six scripts, audit tooling, control system docs, eval metrics. For a large production repo, this is clearly justified. For a small utility or library, the overhead may exceed the benefit. The rollout checklist acknowledges phases, but there's no clear guidance on minimum viable agent-nativeness.

**How does this compose across skills?** Agent-native lives alongside other skills (playwright-cli for browser automation, theorist for narrative theory). The skill model assumes agents load SKILL.md files and compose capabilities. But the interaction between skills — particularly between agent-native's structural requirements and other skills' operational patterns — is largely unexplored. Can an agent effectively juggle harness engineering while also maintaining theory documents and running browser verification?

**Will the cloud-native analogy hold?** The parallel is compelling but may break in important ways. Cloud-native practices became standardized because deployment environments converged (containers, orchestrators, cloud providers). Agent environments are diverging — different models, different tool-use patterns, different context windows, different reasoning capabilities. A repo optimized for Codex's strengths might not be optimal for Opus or for whatever comes next. The framework bets on model-agnostic practices, but that bet is early.

**What does "agent-native" mean when agents get better?** If future models can navigate undocumented repos as fluently as senior engineers, does the framework become unnecessary scaffolding? The counter-argument is that cloud-native practices remained valuable even as cloud platforms matured — structured logging, health endpoints, and declarative config are still best practices regardless of how good the infrastructure gets. The bet is that explicit structure always beats implicit convention, for any executor.
