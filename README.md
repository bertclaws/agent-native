# agent-native

Make your code repo agent-native — designed so any AI coding agent can pick it up and work effectively.

Like **cloud-native** gave us Dockerfiles, health endpoints, and structured logging, **agent-native** gives repos the structure AI agents need: clear instructions, observable execution, verifiable quality gates, and architectural guardrails.

## What's in the box

```
.agents/skills/agent-native/
├── SKILL.md                    # How to use this skill
├── assets/templates/           # AGENTS.md, ARCHITECTURE.md, OBSERVABILITY.md, Makefile, scripts
├── scripts/
│   ├── bootstrap_harness.sh    # One command to install everything
│   ├── verify_customized.sh    # Catches leftover boilerplate
│   └── audit_harness.sh        # Checks for gaps
└── references/                 # Static analysis, agent hooks, browser tools
```

## Quick start

```bash
bash .agents/skills/agent-native/scripts/bootstrap_harness.sh .
```

Then follow the instructions it prints.

## What makes a repo agent-native?

| Artifact | Purpose |
|---|---|
| `AGENTS.md` | Agent instructions — commands, constraints, conventions |
| `docs/ARCHITECTURE.md` | Module boundaries + lint rules to enforce them |
| `docs/OBSERVABILITY.md` | Structured logging convention (JSONL, level policy) |
| `Makefile.harness` | Stable command surface: `make smoke`, `make check`, `make ci` |
| `scripts/harness/` | Real scripts behind the Makefile (smoke, test, lint, typecheck) |
| `.harness/` | Runtime observability data (logs.jsonl, traces.jsonl) |
| `verify_customized.sh` | Verifies the setup is real, not template boilerplate |

## The cloud-native parallel

| Cloud-native | Agent-native |
|---|---|
| Dockerfile | AGENTS.md |
| k8s manifests | Makefile.harness + scripts/ |
| Health endpoints | smoke.sh |
| Structured logging | OBSERVABILITY.md + hlog()/htrace() |
| 12-factor config | ARCHITECTURE.md + boundary enforcement |
| Readiness probes | verify_customized.sh |

## Validated

Tested across Python, TypeScript, C#, and Go with blind AI grading:

| Round | Builder | Avg Score | Key insight |
|---|---|---|---|
| R1 | Codex (hand-held) | 23.25/25 | Prompts doing the work |
| R2 | Codex (minimal) | 21.50/25 | Exposed playbook gaps |
| R3 | Opus (minimal) | 24.50/25 | After playbook fixes |
| R4 | Codex (minimal) | **24.75/25** | Playbook carries the weight |

See [harness-eval](https://github.com/bertclaws/harness-eval) for full results.

## Usage as a skill

Drop `.agents/skills/agent-native/` into any repo. Compatible with:
- **GitHub Copilot CLI** — reads from `.agents/skills/`
- **Claude Code** — reads from `.agents/skills/` or custom instructions
- **Any agent** — SKILL.md is the entrypoint
