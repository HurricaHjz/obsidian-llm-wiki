#!/usr/bin/env bash
# setup.sh — first-run bootstrap for the obsidian-llm-wiki framework.
#
#   bash setup.sh                 create empty registries (wiki/index.md, wiki/log.md) if missing
#   bash setup.sh --with-example  also load the demo from examples/seed/ into wiki/ + raw/
#   bash setup.sh --reset         remove the demo and blank the registries (start your own)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p wiki raw

mk_index() {
  cat > wiki/index.md <<'IDX'
---
title: "Wiki Index"
type: index
---

# Wiki Index

> Global catalogue. **Read this first** when answering a query, then drill into the relevant pages.
> Auto-maintained by the `ingest` skill. Format: `- [[Page Name]] — one-line description.`

## Sources
## Entities
## Tools
## Models
## Benchmarks
## Concepts
## Syntheses
## Developments
## Maps
## User
IDX
}

mk_log() {
  cat > wiki/log.md <<'LOG'
# Wiki Log

> Append-only timeline. Append a `## [date] action | title` entry on every brain-updating op — via shell
> (`cat >> wiki/log.md`), never by reading the whole file. Actions: ingest · query · lint · deep-lint · sync · setup · maps.

## [setup] Initialised from the obsidian-llm-wiki framework
- **Changed**: created the directory scaffold + registries.
LOG
}

mk_custom() {
  # seed the agent-preference layer (identity + output styles); never overwrites an existing file
  mkdir -p wiki/user
  local today; today="$(date +%F)"
  {
    cat <<CUSTHEAD
---
title: "Customisation"
type: user
confidence: high
tags: [user, customisation]
agent_name: ""             # what the agent calls itself (blank = none)
style: high-level          # default output style: high-level | detailed | summary | <your own>
role: generalist           # default role (task-context bundle): generalist | researcher | engineer | tutor | <your own>
language: English (UK)     # conversation language (the wiki itself always stays UK English)
created: $today
updated: $today
---
CUSTHEAD
    cat <<'CUSTBODY'

> **Agent preference layer.** How the agent behaves for you. Identity and output styles below are starter examples — this file is open-ended, so add any standing preference you want every session to honour. The agent reads it at the start of every session; keep it terse (cap ~120 lines). Governance in `CLAUDE.md` always outranks this file.

## Identity
<!-- Name the agent, set its working standard, say how to address you. -->
- Operate at the standard of a world-class researcher, engineer and tutor: rigour first, reason from first principles, cite or flag every claim, state uncertainty plainly, never fabricate.

## Output styles
The default style is the one named by the `style:` key in this file's YAML frontmatter. To switch for the current session only, just ask ("switch to detailed"); to change the default permanently, say "set default style to X" and the agent updates that frontmatter key. Styles shape conversational prose only — never wiki pages, reports, logs or confidence reporting. Styles change only what the user reads — never the agent's internal reasoning, planning, tool use, or processing depth; roles, by contrast, do shape how the agent works (see `## Roles`).

### high-level (default)
Concise and top-down: lead with the answer, plain language, fluent flow, short paragraphs over bullet walls, minimal jargon.

### detailed
Thorough, professional / academic register: mechanisms, caveats, definitions, structured sections, citations where relevant.

### summary
Maximum density: essentials only, no preamble, bullets or a table where they read faster — without sacrificing readability.

<!-- Add your own: "### <name>" + a short description, then set `style:` above to it. -->

## Roles
The active role is the `role:` frontmatter key (default `generalist`). Say "act as `<role>`" to switch for the current conversation — it holds until another switching instruction or the conversation ends; say "set default role to X" to persist it here. Roles are task-context bundles of 3–5 delta lines that shape both the reply and **how the agent approaches the task** — emphasis, approach and rigour may all shift, sometimes trading a little efficiency for quality. They add to the global rules, and only a marked `overrides <feature>:` line may replace a conversational global feature (style, formatting) — governance and system surfaces (wiki pages, reports, logs) are never touched. Begin **every reply** with the status line `<agent_name> · <role> · <style>` (omit the name while `agent_name` is blank); never put it on wiki pages, reports, or deliverables.

| Axis | Knob | Governs |
|---|---|---|
| style | `style:` above | register of conversational prose |
| role | `role:` above | task-context behaviours and emphasis |
| mode | per request | ingest/query depth: standard · concise · research |

### generalist (default)
<!-- Empty by design: Identity + the global rules, unchanged. Add your own specialist roles like:
### reviewer
- Focus on weaknesses and edge cases; list concrete faults before strengths.
- overrides style: detailed — always report findings in detail in this role.
-->

### researcher
- Citation-first claims; scrutinise methods, assumptions and statistics; frame results against related work; state limitations.

### engineer
- Lead with the design decision and its trade-offs; show runnable, tested code; state chosen defaults explicitly; flag technical debt; user-first judgement on anything user-facing.

### tutor
- Explain in plain, accessible language: define jargon on first use, use concrete analogies for hard ideas, keep the simplest phrasing that stays accurate.
- Worked example first, theory second; check understanding before advancing; scaffold difficulty progressively; Socratic questioning where it teaches better than telling.

## Deliverable defaults
<!-- Standing formats the `output` skill applies when an instruction is silent (an explicit
instruction always wins) — e.g.:
- Citations: author-year.
- Decks: Marp, 16:9.
Leave empty to let the agent decide per deliverable. -->

## Interaction preferences
<!-- Terse imperative bullets, e.g.:
- No emoji.
- Author-year citations in deliverables.
- When tutoring, use LaTeX for maths and give worked examples. -->

## Related
- [[About Me]] — who the owner is (this page is how the agent behaves)
CUSTBODY
  } > wiki/user/Customisation.md
}

mk_ideas() {
  # seed the owner's scratchpad (ignored by the agent in normal runs); never overwrites an existing file
  cat > IDEAS.md <<'IDEASEOF'
# IDEAS

> **Owner's scratchpad.** My future ideas, open questions and potential issues, in my own words. **The agent ignores this file in normal runs** — it reads or maintains it only when I explicitly say so. Nothing here is verified or agreed, so it must never drive normal work or enter the wiki without my instruction. I append bullets freely; the agent keeps the Overview table in sync when I ask.

<!-- HOW TO USE (invisible in reading view):
  - Jot fast: add "- [YYYY-MM-DD] …" bullets at the top of Ideas or Potential issues (date optional).
  - Ask the agent to "maintain IDEAS.md" and it will number new items, sync the Overview table, and move finished items to the Archive.
  - Statuses: open · ✅ done · ❌ dropped · ➡️ moved (say where).
-->

## 📋 Overview
<!-- one row per item; kept in sync by the agent on request; № links a row to its bullet below -->

| № | Item | Kind | Status |
|---|------|------|--------|

## 💡 Ideas
<!-- newest first, one line each -->


## ⚠️ Potential issues / watch-list
<!-- newest first; risks, suspected bugs, things that felt off -->


## 🗄️ Archive
<!-- finished items land here with their № and outcome (✅ done · ❌ dropped · ➡️ moved) plus a word on why -->
IDEASEOF
}

apply_palette() {
  # ensure the graph's per-type colour palette is present (idempotent; merges, preserves custom groups)
  if [ -f .claude/skills/lint/apply-palette.py ]; then
    python3 .claude/skills/lint/apply-palette.py --apply >/dev/null 2>&1 || true
  fi
}

DEMO_RAW="raw/2-papers/example-gpt4-and-mmlu.md"
DEMO_WIKI=("wiki/sources/example-gpt4-and-mmlu.md" "wiki/concepts/Large Language Model.md" \
           "wiki/entities/OpenAI.md" "wiki/models/GPT.md" "wiki/benchmarks/MMLU.md" "wiki/maps/home.md")

case "${1:-}" in
  --with-example)
    [ -f wiki/index.md ] || mk_index
    [ -f wiki/log.md ]   || mk_log
    if [ -d examples/seed ]; then
      cp -R examples/seed/raw/.  raw/
      cp -R examples/seed/wiki/. wiki/
      echo "✓ demo loaded. Open the graph view, then ask the agent:  /query what is GPT?"
      echo "  When finished exploring:  bash setup.sh --reset"
    else
      echo "! examples/seed not found — created empty registries only."
    fi
    [ -f wiki/user/Customisation.md ] || mk_custom
    [ -f IDEAS.md ] || mk_ideas
    apply_palette
    ;;
  --reset)
    rm -f "$DEMO_RAW" "${DEMO_WIKI[@]}" 2>/dev/null || true
    mk_index; mk_log
    [ -f wiki/user/Customisation.md ] || mk_custom
    [ -f IDEAS.md ] || mk_ideas
    echo "✓ reset: demo removed, registries blanked. Drop a source into raw/ and run /ingest."
    ;;
  ""|--init)
    [ -f wiki/index.md ] || mk_index
    [ -f wiki/log.md ]   || mk_log
    [ -f wiki/user/Customisation.md ] || mk_custom
    [ -f IDEAS.md ] || mk_ideas
    apply_palette
    echo "✓ ready. Drop a source into raw/ and run /ingest"
    echo "  (or try the demo first:  bash setup.sh --with-example)"
    ;;
  *)
    echo "usage: bash setup.sh [--with-example | --reset]"; exit 1 ;;
esac
