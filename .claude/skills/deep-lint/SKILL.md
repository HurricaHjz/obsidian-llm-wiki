---
name: deep-lint
description: >
  The heavy, infrequent (~monthly) maintenance pass for the wiki — a superset of `lint`. Use on
  /deep-lint, "monthly maintenance", "deep clean the wiki", "audit confidence", or "check my sources
  are up to date". Does everything `lint` does (dead links, orphans, unindexed pages, conflicts) PLUS
  confidence coverage & correctness, staleness scoring, and freshness against the original ONLINE
  sources, and refreshes the qmd index if enabled. Token-expensive by design, so it is NOT routine —
  run it about once a month. Applies fixes only after confirming large or uncertain changes.
user-invocable: true
---

# deep-lint — monthly deep maintenance

## Goal
Keep the whole knowledge base **correct, calibrated, and current** in one bundled pass. Everything
expensive that routine `/lint` deliberately skips lives here, so `/lint` can stay cheap and frequent.

## When to run
**About once a month**, or before a milestone (a big query session, an export, enabling qmd). It reads
pages and may fetch from the network, so it is heavy — do **not** run it after every ingest. Routine
integrity is `/lint`'s job; `deep-lint` is the periodic deep clean.

## Triggers
`/deep-lint` · "monthly maintenance" · "deep clean / deep audit the wiki" · "are my sources still current?"

## Pipeline (read/scan first; confirm before large changes)

### 1 — Structural pass (everything `lint` does)
Run the full `lint` pipeline: index consistency, link health (dead links, orphans — `maps/`/`index`/`log`
exempt), unresolved `## Conflicts / Open Questions`, and the gap scan. Fix the cheap, unambiguous issues
(register unindexed pages, etc.) after the report.

### 2 — Confidence coverage & correctness (per CLAUDE.md §4.6)
- **Coverage:** every non-`map` page must carry a valid `confidence`. Cheap check:
  `grep -rL "^confidence:" wiki --include=*.md` then drop `map`/`index`/`log`. Assign any missing ones.
- **Correctness:** re-assess pages **changed since the last deep-lint** (compare `updated`), and any the
  structural pass flagged, against the §4.6 rubric. Prefer reading only frontmatter + the summary unless
  a fuller read is needed. Keep one consistent standard; on a tie pick the lower tier.
- Apply the same rule everywhere: peer-reviewed/expert/verified → `authoritative`; preprint/owner/
  official-doc → `high`; reputable secondary → `medium`; promo/social/listing/transcript → `low`;
  agent-speculative → `very-low`. Compiled pages cap at `high`.

### 3 — Staleness
Flag `authoritative`/`high` pages whose `updated` is old or that a newer page supersedes; down-weight or
add a `## Conflicts / Open Questions` note, and route high-stakes stale claims to the human. Use `updated`
+ supersession; do not silently rewrite.

### 4 — Freshness against online sources (cheap signals first)
For pages whose `sources:`/`source_url` point at an external URL, check whether the upstream **materially
changed**, cheapest signal first, and re-ingest **only** when it did:
- **Cheap probes:** `gh api repos/<o>/<r>` (latest release / `pushed_at` / default-branch commit) for repos;
  `curl -sI <url>` (`Last-Modified` / `ETag`) for pages; a version string in the page.
- **Skip the immutable:** published papers / PDFs / DOIs rarely change — don't re-fetch them.
- **On a real change → re-ingest through the normal pipeline** (defuddle / `curl` / markitdown per §3.1).
  **Never WebFetch for re-ingest** (it returns a summary, not the source). Merge updates into the existing
  pages (don't duplicate), refresh that page's `confidence` and `updated`, and note the change.
- **Bound it:** cap fetches per run and `log()` anything skipped, so "checked" never overstates coverage.

### 5 — qmd refresh (only if qmd is installed and enabled)
If qmd is in use, run `qmd update && qmd embed` so the search index reflects the month's changes
(see [[qmd-opt-in-design]]). Skip silently if qmd is absent.

### 6 — Registries & report
Update `index.md` for any pages added/renamed. Append one `deep-lint` entry to `log.md` (via shell).
Produce a report: structural fixes, confidence changes (with before→after), stale flags, sources
refreshed/skipped, qmd status.

## Report format
```markdown
## 🧹 Deep-Lint Report — YYYY-MM-DD
### Structural
- N dead links · N orphans · N unindexed · N unresolved conflicts (fixed: …)
### Confidence
- N pages missing a level (assigned) · N re-tiered (e.g. [[X]] high→authoritative)
### Staleness
- N stale high/authoritative claims flagged: [[..]]
### Freshness
- N sources changed upstream & re-ingested: [[..]] · N checked, unchanged · N skipped (immutable)
### qmd
- updated + embedded (or: not enabled)
```

## Hard constraints
- **Heavy and infrequent.** Not part of routine ops; `/lint` handles the frequent cheap pass.
- **Human in the loop** for large or uncertain changes (mass re-tiering, many re-ingests, conflict
  resolutions) — report and confirm before applying.
- **Re-ingest via the §3.1 capture tools** (defuddle / curl / markitdown), **never WebFetch**.
- **Token discipline:** cheap signals before any fetch; scope confidence re-assessment to changed/flagged
  pages; bound network work per run; never dump whole-file contents to "check" them.
- Append `## [YYYY-MM-DD] deep-lint | <summary>` to `wiki/log.md` (shell append, never Read+Edit).
- Report in **British/UK English**.
