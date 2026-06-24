---
name: lint
description: >
  Health-check the Obsidian wiki — the "static analysis" pass for a knowledge base. Use when the
  user runs /lint, /health, /scan, or asks to "check the wiki", "find broken links", "clean up the
  wiki", or "find gaps/orphans/conflicts". Read-only scan that reports dead links, orphan pages,
  pages missing from index.md, and unresolved knowledge conflicts. Proposes fixes but only applies
  them after the user confirms.
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
- After approved fixes, append to `wiki/log.md`:
  `## [YYYY-MM-DD] lint | fixed N issues (M dead links, K unindexed)`.
- Report in **British/UK English**.
