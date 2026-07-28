---
name: deep-lint
description: >
  The heavy, infrequent (~monthly) maintenance pass for the wiki — a superset of `lint`. Use on
  /deep-lint, "monthly maintenance", "deep clean the wiki", "audit confidence", or "check my sources
  are up to date". Does everything `lint` does (dead links, orphans, unindexed pages, conflicts) PLUS
  reconciling query-time `flagged:` freshness flags, confidence coverage & correctness (changed +
  flagged + a sampled cold tail — never a full-vault LLM re-read), staleness scoring, capped
  freshness probes against the original ONLINE sources, the IDEAS.md Monitor review (its sole
  standing delegation), and a qmd refresh if enabled. Token-bounded by design; run ~monthly or when
  flags accumulate. Applies fixes only after confirming large or uncertain changes.
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
- **Customisation sanity (deep-lint only):** if `CUSTOMISATION.md` exists, verify its `## Settings`
  block exists and that its `style` and `role` values each name a section defined in the file (knobs live in the
  body, never the frontmatter — the §13 import strips YAML), every `overrides` line names a
  conversational feature (style / formatting), and that its **loading path is intact**: the file carries its
  `CUSTOMISATION-LOADED-v1` marker line and `CLAUDE.md` still holds the matching `@CUSTOMISATION.md`
  import (§13). Then **report its always-on cost** — bytes ÷ 4 ≈ tokens re-sent on every request of every
  session — rather than enforcing a size cap: the owner decides what the preference layer is worth, and only
  they can trim it. Flag any drift for the owner; never rewrite their preferences.
- **Attic guard (existence-only):** `attic/` and `attic/MANIFEST.md` exist, and the `path:attic/` colour
  group is present (`apply-palette.py --check` covers it). NEVER open attic contents — the attic is
  explicit-instruction-only (CLAUDE.md §2.1); this check reads nothing inside it.
- **Hard-wrap check:** flag wiki pages with suspected mid-sentence hard wraps (a prose line ending in a
  lowercase word or comma while the next line begins lowercase) — prose is one line per paragraph
  (CLAUDE.md §1 line discipline; Obsidian renders single newlines as breaks). Skip non-rendered text:
  frontmatter, code blocks, tables, and HTML-comment interiors. Fix on confirmation.
- **Rendering & narrative sweep (two cheap greps):** flag (a) raw `<tag>` tokens in rendered wiki prose
  outside backticks/comments — Obsidian parses them as HTML (CLAUDE.md §1); (b) correction-narrative
  phrases in `wiki/developments/` (e.g. "owner revision", "no longer", "earlier wording", "was removed") —
  development docs read forward-facing (CLAUDE.md §12). Fix on confirmation.
- **Always-on prefix budget (shell-only):** measure the always-on context layers — `wc -c CLAUDE.md`,
  the summed frontmatter of `.claude/skills/*/SKILL.md` (the ever-loaded `name:`/`description:` block
  between the `---` markers), and the count of always-on MCP servers (`.mcp.json` / project settings;
  0 when absent) — and compare against the `prefix budget:` figures in the previous deep-lint log
  entry (`grep "prefix budget:" wiki/log.md | tail -1`; first run = baseline, nothing to compare).
  Flag growth >10% for the owner (report-only — trimming is never automatic; CLAUDE.md §12 governs
  any cut). Record the fresh figures in this run's log entry:
  `prefix budget: CLAUDE.md <N> B · skill frontmatter <M> B · always-on MCP <k>`.

### 2 — Flag-ledger reconciliation (Tier 2 → Tier 3)
Collect the query-time freshness flags accumulated since the last run — one cheap global grep:
`grep -rn "^flagged:" wiki --include='*.md'` (glob quoted — unquoted it breaks under zsh; **verify
the probe against a known positive before trusting an empty result**, per CLAUDE.md §11). For each flagged page: re-read it, resolve the
suspicion (update the page · re-grade its `confidence` · re-ingest its source via §3.1 tools ·
or clear a false alarm), **remove the `flagged:` line**, and list the resolution in the report.
The ledger is the run's first LLM-read priority — these pages were suspected by an agent that had
actually read them.

### 3 — Confidence coverage & correctness (per CLAUDE.md §4.6)
- **Coverage:** every non-`map` page must carry a valid `confidence`. Cheap check:
  `grep -rL "^confidence:" wiki --include='*.md'` then drop `map`/`index`/`log`. Assign any missing ones.
- **Correctness:** re-assess pages **changed since the last deep-lint** (compare `updated`), any the
  structural pass flagged, **plus a random sample of the cold tail** (~10–20 pages with `updated`
  older than 90 days) — statistical coverage of pages no query ever visits, instead of an exhaustive
  re-read. **State the sampled fraction in the report** ("sampled 15 of 240 cold pages") — a bound
  never goes unstated. Prefer reading only frontmatter + the summary unless a fuller read is needed.
  Keep one consistent standard; on a tie pick the lower tier.
- Apply the same rule everywhere: peer-reviewed/expert/verified → `authoritative`; preprint/owner/
  official-doc → `high`; reputable secondary → `medium`; promo/social/listing/transcript → `low`;
  agent-speculative → `very-low`. Compiled pages cap at `high`.

### 4 — Staleness
Flag `authoritative`/`high` pages whose `updated` is old or that a newer page supersedes; down-weight or
add a `## Conflicts / Open Questions` note, and route high-stakes stale claims to the human. Use `updated`
+ supersession; do not silently rewrite.
- **Archive candidates (suggest-only):** flag pages that look retired — superseded and not cited by any
  live work, or long-stale at low confidence — as *suggestions* for the attic (CLAUDE.md §2.1). NEVER
  move anything yourself: archiving happens only on the user's explicit instruction.

### 5 — Freshness against online sources (cheap signals first)
For pages whose `sources:`/`source_url` point at an external URL, check whether the upstream **materially
changed**, cheapest signal first, and re-ingest **only** when it did:
- **Cheap probes:** `gh api repos/<o>/<r>` (latest release / `pushed_at` / default-branch commit) for repos;
  `curl -sI <url>` (`Last-Modified` / `ETag`) for pages; a version string in the page.
- **Skip the immutable:** published papers / PDFs / DOIs rarely change — don't re-fetch them.
- **On a real change → re-ingest through the normal pipeline** (defuddle / `curl` / markitdown per §3.1).
  **Never WebFetch for re-ingest** (it returns a summary, not the source). Merge updates into the existing
  pages (don't duplicate), refresh that page's `confidence` and `updated`, and note the change.
- **Bound and prioritise:** cap fetches per run, ordering candidates by **confidence × age ×
  inbound-link degree** (hub pages first — a stale hub misleads more queries than a stale leaf), and
  state anything skipped, so "checked" never overstates coverage.

### 6 — Monitor review (the IDEAS.md delegation — Monitor section ONLY)
A `/deep-lint` invocation carries the owner's standing delegation to open **only** the `## 📡 Monitor`
section of `IDEAS.md` — TODO, Ideas and Archive stay untouchable under the normal
explicit-instruction-only contract. For each Monitor caution: gather current vault **evidence**
(counts, log history, flag volume — real numbers, not impressions) and report a status:
**promotion-ripe** (propose a new TODO №, cross-referenced — the owner's word moves it) ·
**dormant** (evidence unchanged) · **evidence-changed** (summarise what moved). Writes to IDEAS.md
happen only after this run's normal confirmation, land as appended "(agent)" annotations (the
owner's wording is content-immutable), and **every IDEAS.md write is reported in the reply's change
table** (mirroring CLAUDE.md §12 system-file reporting) and listed in this run's log entry.

### 7 — qmd refresh (only if qmd is installed and enabled)
If qmd is in use, run `qmd update && qmd embed` so the search index reflects the month's changes
(see `qmd-opt-in-design`). Skip silently if qmd is absent.

### 8 — Registries & report
Update `index.md` for any pages added/renamed. Append one `deep-lint` entry to `log.md` (via shell).
Produce a report: structural fixes, confidence changes (with before→after), stale flags, sources
refreshed/skipped, qmd status.

## Report format
```markdown
## 🧹 Deep-Lint Report — YYYY-MM-DD
### Flags
- N `flagged:` pages reconciled (fixed · re-graded · re-ingested · cleared) — probe control-verified
### Structural
- N dead links · N orphans · N unindexed · N unresolved conflicts (fixed: …)
- prefix budget: CLAUDE.md N B (Δ vs last audit) · skill frontmatter M B (Δ) · always-on MCP k (>10% growth flagged)
### Confidence
- N pages missing a level (assigned) · N re-tiered (e.g. [[X]] high→authoritative) · cold tail: sampled k of N (list any re-tiered)
### Staleness
- N stale high/authoritative claims flagged: [[..]] · N attic candidates suggested (user decides)
### Freshness
- N sources changed upstream & re-ingested: [[..]] · N checked, unchanged · N skipped (immutable/capped — stated)
### Monitor (IDEAS delegation)
- per caution: №n — promotion-ripe / dormant / evidence-changed (+ the evidence)
### qmd
- updated + embedded (or: not enabled)
```

## Hard constraints
- **Heavy and infrequent.** Not part of routine ops; `/lint` handles the frequent cheap pass.
- **Human in the loop** for large or uncertain changes (mass re-tiering, many re-ingests, conflict
  resolutions) — report and confirm before applying.
- **Re-ingest via the §3.1 capture tools** (defuddle / curl / markitdown), **never WebFetch**.
- **Token discipline:** cheap signals before any fetch; scope LLM re-reads to ledger + changed +
  sampled pages (never the whole vault); bound network work per run; never dump whole-file contents
  to "check" them. **Every bound and sample is stated in the report — no silent caps** (CLAUDE.md §11).
- **IDEAS.md boundary:** the delegation covers the Monitor section ONLY, report-first; any IDEAS write
  is confirmed, "(agent)"-marked, in the reply's change table, and in the log entry. TODO/Ideas/Archive
  are never touched by this skill.
- Append `## [YYYY-MM-DD] deep-lint | <summary>` to `wiki/log.md` (shell append, never Read+Edit).
- Report in **British/UK English**.
