---
name: improve
disable-model-invocation: true
description: "Use when the user says /improve or wants to discover what the app could do better from a product perspective: feature gaps, growth opportunities, marketing, business potential, unfinished work. Thinks like a product owner, not a code reviewer. For code quality, performance, security, a11y, DX, modernization issues use /audit instead."
model: sonnet
effort: high
context: fork
allowed-tools:
  - Agent
  - Bash
  - Read
  - Glob
  - Grep
  - TodoWrite
  - AskUserQuestion
  - WebSearch
  - WebFetch
---

# Improve: Discover product potential

**EXECUTE IMMEDIATELY — do not explain, do not announce. Start directly with step 1.**

## Distinction from /audit

| | /audit | /improve |
|---|---|---|
| **Asks** | "What's broken or bad about the code?" | "What could the app do as a product?" |
| **Perspective** | Code reviewer / QA / tech lead | Product owner / growth lead / strategist |
| **Checks** | Security, performance, a11y, code quality, SEO, DX, modernization | Feature gaps, growth, marketing, business, unfinished features |
| **Output** | Findings + auto-fix | Prioritized report with ideas |
| **Fixes** | Yes, automatically | No — user decides |

**Do NOT report (that's /audit's job):**
- Code quality, DRY, naming, architecture
- Performance, N+1, bundle size, caching
- Security, missing validation
- A11y, SEO (technical), typography, UI design, UX patterns
- Outdated dependencies, modernization
- DX, tooling, tests, docs, setup

## Flow

### 1. Determine project context

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Framework erkennen
if [ -f "$PROJECT_ROOT/artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="app/ resources/ database/ routes/ config/"
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="src/ app/ pages/ components/ lib/ public/"
elif [ -f "$PROJECT_ROOT/nuxt.config.ts" ] || [ -f "$PROJECT_ROOT/nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="components/ composables/ pages/ layouts/ server/ plugins/"
elif [ -f "$PROJECT_ROOT/manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find "$PROJECT_ROOT" -name 'apps.py' -exec dirname {} \; | head -20 | tr '\n' ' ')"
elif [ -f "$PROJECT_ROOT/Gemfile" ]; then
  FRAMEWORK="rails"
  SOURCE_DIRS="app/ config/ db/ lib/"
elif [ -f "$PROJECT_ROOT/wp-config.php" ] || ([ -f "$PROJECT_ROOT/style.css" ] && grep -q "Theme Name" "$PROJECT_ROOT/style.css" 2>/dev/null); then
  FRAMEWORK="wordpress"
  SOURCE_DIRS="$(find "$PROJECT_ROOT" -maxdepth 2 \( -name 'functions.php' -o -name 'style.css' \) -exec dirname {} \; | sort -u | tr '\n' ' ')"
else
  FRAMEWORK="generic"
  SOURCE_DIRS="src/ lib/ app/"
fi

echo "FRAMEWORK: $FRAMEWORK"
echo "---"
echo "Dateistruktur (Top-Level):"
ls -1 "$PROJECT_ROOT" | head -30
echo "---"

# Config/Dependency-Infos
for cfg in composer.json package.json requirements.txt Cargo.toml go.mod Gemfile pyproject.toml; do
  if [ -f "$PROJECT_ROOT/$cfg" ]; then
    echo "=== $cfg ==="
    cat "$PROJECT_ROOT/$cfg" 2>/dev/null | head -80
  fi
done
```

Produce:
- **FRAMEWORK:** detected framework
- **SOURCE_DIRS:** relevant source directories
- **PROJECT_CONTEXT:** load `## Audit Context` from the project's CLAUDE.md:
  ```bash
  PROJECT_CLAUDE_MD="$(git rev-parse --show-toplevel)/CLAUDE.md"
  if [ -f "$PROJECT_CLAUDE_MD" ]; then
    PROJECT_CONTEXT=$(awk '/^## Audit Context$/{found=1; next} /^## /{found=0} found' "$PROJECT_CLAUDE_MD")
  fi
  ```
- **TECH_STACK:** detected technologies (DB, cache, queue, frontend, CSS etc.)

### 2. Dispatch product analysis

Dispatch **a single agent** via the Agent tool.

Read the agent definition from `agents/1-features.md` in the skill directory. Pass along:
- FRAMEWORK, SOURCE_DIRS, TECH_STACK
- PROJECT_CONTEXT (if present)

| Agent file | Model | Question |
|-------------|--------|---------------|
| `agents/1-features.md` | `opus` | "What can the app do — and what could it do next?" |

### 3. Produce the report

Consolidate the agent's results into the following structure:

```
## Improve Report — {FRAMEWORK} Project

### What the app currently does
Short summary (paragraph). What the product is, core features, user roles.

### Quick Wins (< 1h effort, high impact)
1. [Perspective] Description — why + expected benefit
2. ...

### Recommended Features (1h-1d effort)
1. [Perspective] Description — why + expected benefit
2. ...

### Strategic Ideas (> 1d effort)
1. [Perspective] Description — why + expected benefit
2. ...

### Unfinished Features
- Feature X (status: half done) — file:line
- ...

### Already Well Implemented
- What the project does right
```

**Perspective** is one of: Product / Growth / Marketing / Business

**Prioritization criteria:**
1. **Impact on end users** > everything else
2. **Effort vs. benefit** — quick wins first
3. **Obvious next step first** — features that fit the existing product > new directions

**Do not invent findings.** If an area is strong, list it under "Already Well Implemented".

### 4. Offer next steps

Ask the user after the report:
> Should I implement one of these findings directly? You can also just give me a number.

**IMPORTANT: Do not start implementing automatically. The user decides.**
