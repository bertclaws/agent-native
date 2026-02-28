# Plankton Multi-Platform Hooks: Research & PR Plan

**Date:** 2026-02-21
**Status:** Complete
**Goal:** Make [alexfazio/plankton](https://github.com/alexfazio/plankton) work with GitHub Copilot CLI and VS Code agent mode, structured as a contributable upstream PR.

---

## 1. Executive Summary

Plankton is a real-time code quality enforcement system built on Claude Code hooks. It uses a three-phase architecture (auto-format → collect violations → delegate fixes to a Claude subprocess) triggered by `PreToolUse`, `PostToolUse`, and `Stop` hooks.

**Good news:** The hook ecosystems have converged significantly. VS Code agent mode already reads Claude Code's `.claude/settings.json` format natively. Copilot CLI uses a slightly different format in `.github/hooks/`, but the differences are manageable.

**The work breaks into three tiers:**
1. **Free (already works):** VS Code agent mode — reads `.claude/` hooks as-is
2. **Small adaptation:** Copilot CLI — needs `.github/hooks/` configs + input/output JSON translation in the shell scripts
3. **Larger refactor:** Phase 3 subprocess — currently hardcodes `claude -p`, needs to be model/CLI-agnostic

---

## 2. Platform Hook Format Comparison

### 2.1 Config File Locations

| Platform | Location | Format |
|---|---|---|
| Claude Code | `.claude/settings.json` | PascalCase events, `matcher` field, nested under `hooks` |
| Copilot CLI | `.github/hooks/*.json` | `version: 1`, camelCase events under `hooks` object |
| VS Code Agent Mode | Both `.claude/` AND `.github/hooks/` | Reads both formats; `.claude/` takes precedence for same event |

**Key insight:** VS Code explicitly states it "parses Claude Code's hook configuration format, including matcher syntax." So Plankton already works in VS Code agent mode with zero changes.

### 2.2 Event Name Mapping

| Claude Code | Copilot CLI | VS Code Agent |
|---|---|---|
| `PreToolUse` | `preToolUse` | `PreToolUse` (Claude format) |
| `PostToolUse` | `postToolUse` | `PostToolUse` |
| `Stop` | `agentStop` | `Stop` |
| `UserPromptSubmit` | `userPromptSubmitted` | `UserPromptSubmit` |
| `SessionStart` | `sessionStart` | `SessionStart` |
| `SubagentStop` | `subagentStop` | `SubagentStop` |
| — | `sessionEnd` | — |
| — | `errorOccurred` | — |
| — | — | `PreCompact` |
| — | — | `SubagentStart` |

### 2.3 Input JSON Schema Differences

**Claude Code `PreToolUse` input:**
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file.py",
    "old_string": "...",
    "new_string": "..."
  }
}
```

**Copilot CLI `preToolUse` input:**
```json
{
  "timestamp": 1704614600000,
  "cwd": "/path/to/project",
  "toolName": "bash",
  "toolArgs": "{\"command\":\"rm -rf dist\"}"
}
```

**Critical differences:**
- Claude: `tool_name` / `tool_input` (structured object)
- Copilot CLI: `toolName` / `toolArgs` (JSON **string**, not object)
- Copilot CLI adds `timestamp` and `cwd` as top-level fields
- Tool names differ: Claude uses `Edit`/`Write`/`Bash`, Copilot CLI uses `edit`/`create`/`bash` (lowercase, different verbs)

### 2.4 Output JSON Schema Differences

**Claude Code `PreToolUse` output:**
```json
{"decision": "block", "reason": "Protected linter config file"}
```

**Copilot CLI `preToolUse` output:**
```json
{"permissionDecision": "deny", "permissionDecisionReason": "Protected linter config file"}
```

**VS Code Agent Mode `PreToolUse` output:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "...",
    "updatedInput": {},
    "additionalContext": "..."
  }
}
```

**Critical differences:**
- Claude: `decision: "approve"/"block"` + `reason`
- Copilot CLI: `permissionDecision: "allow"/"deny"/"ask"` + `permissionDecisionReason`
- VS Code: wraps in `hookSpecificOutput` with `permissionDecision` + supports `updatedInput` for modifying tool args
- Value mapping: `approve` ↔ `allow`, `block` ↔ `deny`

### 2.5 PostToolUse Differences

**Claude Code:** Hook can return structured output that influences the agent.
**Copilot CLI:** Output is **ignored** — "result modification is not currently supported."

This is a **significant limitation** for Plankton. The `multi_linter.sh` PostToolUse hook returns exit code 2 with stderr messages to report violations back to the agent. Exit code 2 = "blocking error" works the same way in both systems, so the core mechanism still functions. But any structured JSON output Plankton returns in PostToolUse will be silently dropped by Copilot CLI.

### 2.6 Stop Hook Differences

**Claude Code:** `Stop` hook can return `{"decision": "block"}` to prevent session exit.
**Copilot CLI:** `agentStop` — output is ignored per current docs. This means `stop_config_guardian.sh` (which blocks session exit if linter configs were modified) **will not work** on Copilot CLI.

### 2.7 Matcher Support

| Platform | Matcher | Example |
|---|---|---|
| Claude Code | ✅ Regex on tool name | `"matcher": "Edit\|Write"` |
| VS Code Agent | ✅ Same as Claude Code | `"matcher": "Edit\|Write"` |
| Copilot CLI | ❌ No matcher | All hooks fire for all tools of that event type |

Without matchers, Copilot CLI hooks fire on every tool invocation. The scripts themselves already check `toolName` / `tool_name` internally, so this is a performance concern (extra script invocations) but not a correctness issue.

---

## 3. Plankton Scripts — What Needs to Change

### 3.1 `protect_linter_configs.sh` (PreToolUse, matcher: `Edit|Write`)

**Current behavior:** Reads `tool_input.file_path` from stdin JSON, outputs `{"decision": "approve/block"}`.

**Changes needed for Copilot CLI:**
- Parse `toolName` + `toolArgs` (JSON string) instead of `tool_input.file_path`
- Map tool names: `edit`/`create` (Copilot) → same logic as `Edit`/`Write` (Claude)
- Output `{"permissionDecision": "allow/deny"}` format
- Skip gracefully when `toolName` isn't a file-editing tool (no matcher to filter)

**Approach:** Add a platform detection shim at the top of each script. If input has `toolName`, it's Copilot CLI format; if `tool_name`, it's Claude Code format. Normalize internally.

### 3.2 `enforce_package_managers.sh` (PreToolUse, matcher: `Bash`)

**Current behavior:** Reads `tool_input.command` from stdin, blocks legacy package managers.

**Changes needed for Copilot CLI:**
- Parse `toolArgs` (JSON string) and extract `command` from it
- Same output format translation as above
- Skip when `toolName` isn't `bash`

### 3.3 `multi_linter.sh` (PostToolUse, matcher: `Edit|Write`)

**Current behavior:** Reads `tool_input.file_path`, runs three-phase linting, spawns `claude -p` subprocess.

**Changes needed for Copilot CLI:**
- Parse `toolArgs` for file path
- Skip when `toolName` isn't a file-editing tool
- **Phase 3 subprocess:** Replace hardcoded `claude -p` with configurable CLI command (see §4)
- PostToolUse output is ignored by Copilot CLI, but exit code 2 still blocks — this should work

### 3.4 `stop_config_guardian.sh` (Stop hook)

**Current behavior:** Blocks session exit if linter configs were modified via `git diff`.

**Changes needed for Copilot CLI:**
- Map to `agentStop` event
- ⚠️ **Copilot CLI ignores agentStop output** — blocking won't work
- Best effort: log a warning to stderr (which may appear in the agent's context) but can't actually block
- This is a platform limitation, not something we can fix in Plankton

---

## 4. Phase 3 Subprocess — Making It Model-Agnostic

This is the highest-value change for upstream contribution. Currently `multi_linter.sh` hardcodes:

```bash
claude -p "Fix these violations: ..." --model haiku/sonnet/opus
```

### 4.1 Proposed Abstraction

Add a `subprocess` config section to `.claude/hooks/config.json`:

```json
{
  "subprocess": {
    "cli": "auto",
    "model_tiers": {
      "fast": "haiku",
      "standard": "sonnet",
      "capable": "opus"
    },
    "timeout": 300
  }
}
```

Where `"cli": "auto"` detects the available CLI:
1. `claude` → `claude -p "..." --model <model>`
2. `copilot` → `copilot exec "..."` (or `gh copilot exec`)
3. `codex` → `codex exec "..."`
4. Custom → `"cli": "/path/to/my-agent --prompt"`

### 4.2 Model Routing

Currently uses Anthropic-specific model names (`claude-3-5-haiku`, `claude-sonnet-4`, `claude-opus-4`). The abstraction maps generic tiers (`fast`/`standard`/`capable`) to provider-specific model names.

Default mappings per CLI:
- **claude:** haiku / sonnet / opus (current behavior)
- **copilot:** model selection handled by Copilot (no `--model` flag needed)
- **codex:** gpt-5.2-codex (single model, no tiers)
- **custom:** user-configured

---

## 5. Recommended PR Structure

### PR 1: Platform-agnostic input/output shim (small, low risk)

Add a shared helper function (`platform_shim.sh`) that:
- Auto-detects Claude vs Copilot input format
- Normalizes to a common internal format
- Provides output functions that emit the correct JSON for the detected platform

Source it from each hook script:
```bash
source "$(dirname "$0")/platform_shim.sh"
# Now use: get_file_path, get_tool_name, emit_approve, emit_block "reason"
```

**Files changed:** New `platform_shim.sh`, minor edits to all 4 hook scripts.
**Risk:** Low — existing Claude Code behavior unchanged, just wrapped.

### PR 2: Add `.github/hooks/` config for Copilot CLI

Generate a `.github/hooks/plankton.json` that mirrors the `.claude/settings.json` hooks but in Copilot CLI format:

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "bash": ".claude/hooks/protect_linter_configs.sh",
        "timeoutSec": 5
      },
      {
        "type": "command",
        "bash": ".claude/hooks/enforce_package_managers.sh",
        "timeoutSec": 5
      }
    ],
    "postToolUse": [
      {
        "type": "command",
        "bash": ".claude/hooks/multi_linter.sh",
        "timeoutSec": 600
      }
    ],
    "agentStop": [
      {
        "type": "command",
        "bash": ".claude/hooks/stop_config_guardian.sh",
        "timeoutSec": 10
      }
    ]
  }
}
```

Note: Scripts stay in `.claude/hooks/` — both configs point to the same scripts. The platform shim handles format differences.

**Files changed:** New `.github/hooks/plankton.json`, updated docs.
**Risk:** Very low — additive only.

### PR 3: Model-agnostic Phase 3 subprocess (larger, high value)

Refactor `multi_linter.sh` Phase 3 to use configurable CLI. This addresses the upstream TODO: "model routing currently assumes Anthropic models."

**Files changed:** `multi_linter.sh`, `config.json` schema, docs.
**Risk:** Medium — core behavior change, needs testing.

### PR 4: Documentation & platform compatibility matrix

Update README, REFERENCE.md, SETUP.md with:
- "Works with" badges (Claude Code ✅, VS Code Agent ✅, Copilot CLI ⚠️ partial)
- Platform compatibility matrix
- Known limitations (Copilot CLI: no matcher, no Stop blocking, no PostToolUse output)
- Setup instructions per platform

---

## 6. Known Limitations (Copilot CLI)

| Feature | Claude Code | VS Code Agent | Copilot CLI |
|---|---|---|---|
| PreToolUse blocking | ✅ | ✅ | ✅ |
| PostToolUse linting | ✅ | ✅ | ✅ (exit code 2 works) |
| Stop hook blocking | ✅ | ✅ | ❌ (output ignored) |
| Tool matcher | ✅ | ✅ | ❌ (scripts filter internally) |
| PostToolUse output | ✅ | ✅ | ❌ (ignored) |
| Phase 3 subprocess | ✅ (claude -p) | ✅ (claude -p) | ⚠️ (needs CLI abstraction) |
| Config protection | ✅ Full | ✅ Full | ⚠️ PreToolUse only (no Stop blocking) |

**Bottom line:** Copilot CLI gets ~80% of Plankton's functionality. The main gap is the Stop hook can't block session exit, so config tampering detection is warn-only on Copilot CLI.

---

## 7. Implementation Estimate

| PR | Effort | Complexity | Upstream Value |
|---|---|---|---|
| PR 1: Platform shim | 2-3 hours | Low | High — enables everything else |
| PR 2: .github/hooks config | 30 min | Trivial | Medium — nice to have |
| PR 3: Model-agnostic subprocess | 4-6 hours | Medium | Very high — addresses upstream TODO |
| PR 4: Docs | 1-2 hours | Low | High — table stakes for multi-platform |

**Total: ~1 day of focused coding work.**

---

## 8. Sources

- Plankton repo: https://github.com/alexfazio/plankton
- Plankton `.claude/settings.json`: https://raw.githubusercontent.com/alexfazio/plankton/main/.claude/settings.json
- Plankton `multi_linter.sh`: https://raw.githubusercontent.com/alexfazio/plankton/main/.claude/hooks/multi_linter.sh
- Plankton REFERENCE.md: https://raw.githubusercontent.com/alexfazio/plankton/main/docs/REFERENCE.md
- GitHub Copilot CLI hooks: https://docs.github.com/en/copilot/how-tos/copilot-cli/use-hooks
- Copilot hooks config reference: https://docs.github.com/en/copilot/reference/hooks-configuration
- VS Code Agent hooks (Preview): https://code.visualstudio.com/docs/copilot/customization/hooks
- Claude Code hooks: https://code.claude.com/docs/en/hooks
