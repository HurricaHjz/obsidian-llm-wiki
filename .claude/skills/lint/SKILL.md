---
name: lint
description: >
  Health-check the Obsidian wiki — the "static analysis" pass for a knowledge base. Use when the
  user runs /lint, /health, /scan, or asks to "check the wiki", "find broken links", "clean up the
  wiki", or "find gaps/orphans/conflicts". Read-only scan that reports dead links, orphan pages,
  pages missing from index.md, and unresolved knowledge conflicts. Also restores the graph colour
  palette on request (on-demand only, never on a routine scan). Proposes fixes but only applies them
  after the user confirms.
user-invocable: true
---

# lint — knowledge-graph health check

## Goal
Bring software static-analysis discipline to the wiki. Find the rot that accumulates as a
knowledge base grows: **dead links, orphans, unindexed pages, unresolved conflicts.**

## When to run (and when not)
`ingest` and `query` already leave the graph integrity-clean (ingest self-checks at its Step 7), so
**don't lint routinely after a normal ingest — there's nothing to fix.** Run lint when integrity may
have *drifted* from outside that path (manual edits/renames/deletes in Obsidian, external or
OneDrive/git sync changes, many ingests over time), or periodically for *discovery* a per-source
ingest can't do: emerging gap pages, cross-corpus contradictions, and stale claims.

**Scope boundary:** confidence coverage, staleness scoring, and online-source freshness are **not**
lint's job — they live in the heavier, ~monthly **`deep-lint`**. Routine `/lint` stays cheap and never
reads pages for confidence or fetches anything.

## Triggers
`/lint` · `/health` · `/scan` · "check my wiki" · "find broken links / orphans / gaps".

## Pipeline (read-only until the user approves fixes)

### 1 — Index consistency
Read `wiki/index.md`; glob every `.md` under `wiki/` (exclude `index.md`, `log.md`).
Report: pages registered in the index but **missing on disk**, and pages on disk but **not registered**.

### 2 — Link health
Extract every `[[wikilink]]` across all wiki pages.
- Link target doesn't exist → **dead link** (report source page → missing target).
- **Media embeds** `![[name.png|jpg|pdf|…]]` resolve to `assets/`, not a wiki page — never flag these as dead links.
- Page with **no inbound links** from any other page → **orphan** — but **exempt** `index`, `log`, and `maps/` pages (Maps of Content are navigational entry points, not orphans).

### 3 — Conflict audit
Find pages containing `## Conflicts / Open Questions`. List each unresolved conflict (the two sides)
as cognitive tech-debt to resolve.

### 4 — Gap scan (optional, suggestive)
Note entities/concepts mentioned often but lacking their own page, and stale claims newer sources
supersede. Suggest sources or web searches to fill gaps.

## Graph colour restore (on-demand — NOT part of a routine lint)
The graph's per-type colours live in `.obsidian/graph.json` → `colorGroups`. That file is **volatile**:
Obsidian rewrites it from memory whenever a graph setting changes (or a sync clobbers it), and can wipe
the palette so the graph turns all-grey. Unlike dead links or orphans, a wiped palette is **immediately
visible**, so there is no need to scan for it on every lint — handle it **only on a real signal**.

**Trigger — do this only when:**
1. the user reports a grey/colourless graph or asks to check/fix/restore graph colours, **or**
2. it is a **fresh vault** at first-run — `ingest`'s bootstrap calls this once (see that skill).

Otherwise do nothing: a routine `/lint` never reads `graph.json` or the palette.

**Procedure (one shared script — the single source of truth for the palette):**
- **Detect:** `python3 .claude/skills/lint/apply-palette.py --check` → exit 0 = palette complete (stop);
  exit 1 = it prints the missing framework groups.
- **Confirm, then restore:** on the user's OK, `python3 .claude/skills/lint/apply-palette.py --apply` —
  it **merges** the canonical palette (`.claude/skills/lint/palette.json`) into `colorGroups`, adding
  only the missing framework groups and **preserving any custom groups**. Idempotent.
- **Reload:** tell the user to **close the graph view and reload Obsidian** (`Cmd/Ctrl+R`), so Obsidian
  does not overwrite the edit with stale in-memory state.

The palette data (`palette.json`) and logic (`apply-palette.py`) ship with this skill, so `setup.sh`,
`ingest`'s first-run, and this restore all use the **same** definition — read **only** on this path,
never on a routine lint.

## Report format
```markdown
## 🩺 Wiki Health Report — YYYY-MM-DD

### ✅ Healthy
- ...

### ⚠️ Warnings
- **N orphan pages**: [[..]] — suggest linking or categorizing
- **N unindexed pages**: [[..]] — on disk but missing from index.md

### ❌ Errors
- **N dead links**: [[Source]] → [[Missing Target]]
- **N unresolved conflicts**: [[Page]]

### 🛠️ Proposed next steps
1. Auto-register unindexed pages? (y/n)
2. Re-derive / resolve the listed conflicts?
```

## Hard constraints
- **Read-only scan.** Do not modify, rename, or delete anything before the report.
- **Wait for confirmation** before applying any fix.
- **Graph colour restore is on-demand only** (see its section) — never scanned or read on a routine lint.
- After approved fixes, append to `wiki/log.md`:
  `## [YYYY-MM-DD] lint | fixed N issues (M dead links, K unindexed)`.
- Report in **British/UK English**.
