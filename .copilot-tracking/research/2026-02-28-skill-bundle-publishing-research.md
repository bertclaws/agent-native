# Publishing Skill Collections / Bundles

**Date:** 2026-02-28  
**Status:** Complete  
**Question:** Can we publish a collection/bundle of skills (not one at a time) to ClawHub, SkillsMP, and npx skills?

---

## TL;DR

**Yes, but not via a single native "bundle" primitive on any platform.** Each platform has a different workaround:

| Platform | Native Bundle? | Workaround |
|---|---|---|
| **ClawHub** | ❌ No | `clawhub sync --all` batch-publishes all local skills at once |
| **SkillsMP** | ❌ No (aggregator) | Not a publishing platform — it indexes GitHub repos automatically |
| **npx skills** | ✅ Effectively yes | A GitHub repo with multiple `skills/` folders **is** the bundle — users install with `npx skills add owner/repo` |

**Recommended approach:** Maintain a single GitHub repo as the canonical source of truth (e.g., `andrewvineyard/openclaw-skills`), then publish from it to all three.

---

## Platform-by-Platform Analysis

### 1. ClawHub (clawhub.ai)

**What it is:** Official OpenClaw public skill registry. Versioned, searchable, CLI-driven.

**Publishing model:** One skill = one `clawhub publish <path>` call. Each skill gets its own slug, version, and changelog.

**Bundle approach:**
- **`clawhub sync`** — Scans a directory tree for skills and batch-publishes new/updated ones:
  ```bash
  clawhub sync --all --root ./skills --bump patch --changelog "Initial collection release"
  ```
  - `--all` skips prompts
  - `--root <dir...>` specifies extra scan roots
  - `--dry-run` to preview
  - `--concurrency <n>` for parallel registry checks
  - `--bump patch|minor|major` for version bumping

- **No meta-skill concept.** There's no "install this one thing and get 5 skills." Each skill is independently installable.

- **Potential workaround — meta-skill SKILL.md:**
  You could create a single "collection" skill whose SKILL.md instructions say "install these other skills":
  ```markdown
  ## Installation
  Run:
  clawhub install skill-a
  clawhub install skill-b
  clawhub install skill-c
  ```
  Or include a `scripts/install-all.sh` that runs the commands. Not ideal but functional.

### 2. SkillsMP (skillsmp.com)

**What it is:** An independent community aggregator that indexes agent skills from GitHub. NOT a publishing platform.

**How skills get listed:** SkillsMP crawls/indexes GitHub repos that contain SKILL.md files. You don't "publish" to it — it discovers your repo.

**Bundle approach:**
- Structure your GitHub repo with multiple skills, each in its own folder with a SKILL.md.
- SkillsMP will index each one independently.
- There's a leaderboard based on install telemetry from `npx skills add`.

**Action required:** Nothing beyond having a well-structured public GitHub repo.

### 3. npx skills (skills.sh / vercel-labs/skills)

**What it is:** Vercel's open-source CLI tool for installing agent skills from GitHub repos. Cross-compatible with Claude Code, Codex, OpenClaw, etc.

**Publishing model:** Your GitHub repo IS the distribution. No separate registry upload.

**Bundle approach — this is the winner:**
```
your-repo/
├── skills/
│   ├── skill-a/
│   │   └── SKILL.md
│   ├── skill-b/
│   │   └── SKILL.md
│   └── skill-c/
│       └── SKILL.md
```

Users can then:
```bash
# List available skills in the repo
npx skills add owner/repo --list

# Install ALL skills from the repo
npx skills add owner/repo

# Install a specific skill
npx skills add owner/repo --skill skill-a

# Install from a direct path
npx skills add https://github.com/owner/repo/tree/main/skills/skill-a
```

Supports targeting specific agents:
```bash
npx skills add owner/repo --agent openclaw
npx skills add owner/repo --agent claude-code
npx skills add owner/repo --agent codex
```

**This is effectively a bundle by design.** The repo is the collection.

---

## Recommended Strategy

### Step 1: Create a GitHub repo as the canonical source

```
andrewvineyard/openclaw-skills/     (or whatever name)
├── README.md
├── skills/
│   ├── skill-a/
│   │   ├── SKILL.md
│   │   └── scripts/...
│   ├── skill-b/
│   │   └── SKILL.md
│   └── skill-c/
│       └── SKILL.md
```

### Step 2: Publish to ClawHub (batch)

```bash
clawhub login
clawhub sync --all --root ./skills --bump minor
```

Each skill gets its own ClawHub entry. Users can install individually.

### Step 3: npx skills — free by default

The repo structure already works:
```bash
npx skills add andrewvineyard/openclaw-skills
```

Users get all skills, or can `--list` and pick.

### Step 4: SkillsMP — automatic

Once the repo is public and skills are installed by users, SkillsMP will index them via telemetry.

### Step 5 (Optional): Create a meta-skill on ClawHub

Publish a `skill-collection` skill whose SKILL.md references the npx command:
```markdown
---
name: andrew-skill-collection
description: A curated bundle of OpenClaw skills for X, Y, Z. Install all at once or pick individual skills.
---

# Andrew's Skill Collection

## Quick Install (all skills)
\```bash
npx skills add andrewvineyard/openclaw-skills
\```

## Individual Skills
- **skill-a**: `clawhub install skill-a` — Does X
- **skill-b**: `clawhub install skill-b` — Does Y
- **skill-c**: `clawhub install skill-c` — Does Z
```

This gives you a single discoverable entry point on ClawHub that points to the full bundle via npx.

---

## Tools Worth Knowing

- **`npx build-skill`** (Flash-Brew-Digital/build-skill) — Scaffolds an entire multi-skill repo with CI/CD, marketplace config, and sync scripts for managing collections over time.
- **`clawhub sync --dry-run`** — Preview what would be published without actually pushing.

---

## Sources
- https://docs.openclaw.ai/tools/clawhub
- https://github.com/openclaw/clawhub
- https://github.com/vercel-labs/skills
- https://skillsmp.com
- https://skills.sh/docs/faq
