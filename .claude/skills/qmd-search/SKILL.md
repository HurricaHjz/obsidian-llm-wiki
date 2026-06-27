---
name: qmd-search
description: >
  OPTIONAL, DORMANT semantic-search layer over the wiki, powered by qmd (local hybrid BM25 + vector +
  rerank). Use only when the wiki has outgrown index.md AND the user has installed + enabled qmd. The
  agent auto-detects qmd; if it is absent or disabled this skill does nothing and the normal
  index.md → grep search runs unchanged. Provides confidence-aware semantic retrieval as the
  query/output fallback, plus a refresh hook that updates a page's qmd embedding whenever it is created
  or changed. Retrieval only — never writes or decides. Trigger: /qmd-search <query>, or internally as
  the query/output semantic fallback.
user-invocable: true
---

# qmd-search — optional semantic search over the wiki (dormant until qmd is installed)

## What this is
A thin, **dormant** adapter to [[qmd]] (design: `wiki/developments/qmd-opt-in-design.md`; setup runbook:
`wiki/developments/equipping-the-wiki-with-qmd.md`). It carries **zero runtime cost** until a user installs
qmd and builds an index. It does **not** replace `index.md` (the curated, read-first catalogue); it is the
*semantic fallback* `query`/`output` reach for when the catalogue under-covers a question, and the
**refresh hook** that keeps qmd's embeddings current as the wiki changes. qmd retrieves; the wiki governs
(compile, cross-link, confidence, conflicts).

## Activation — capability detection (the opt-in *is* installation)
Use qmd **only if all three hold**; otherwise fall through to the default search silently:
1. `command -v qmd` succeeds (qmd installed), AND
2. an index exists for this vault (`qmd status` lists indexed collections), AND
3. there is **no `.qmd-off` marker** in the vault root — create that file to force qmd off without uninstalling; its absence means **active** (installing qmd + building an index *is* the opt-in).

This is one cheap shell check. If any condition fails, **do nothing**: the agent uses `index.md` → `grep`
exactly as before. A fresh clone or a non-adopter is unaffected, with no prompt to install anything.

## When to invoke (opt-in — never on every search)
qmd search is **not** a default step. Invoke it only when:
1. **the user explicitly asks** (`/qmd-search`, "search semantically", "use qmd"), **or**
2. **the agent judges the cheap path insufficient** — `index.md` + `grep` under-cover the question (it needs
   semantic recall, or the corpus is too large to scan reliably).

Otherwise answer from `index.md` → `grep` and **do not call qmd**. Rationale: a qmd *query* reads passages
**into the agent's context** (real tokens) and adds latency, so it must earn that cost; the index-first path
is free and usually enough. This gates only the **read** side. The **write** side — refreshing embeddings on
every page change — always runs when qmd is active, because it is **local compute that costs ≈ no agent
tokens** (the agent only shells out and waits).

## Search (only when active)
- **CLI shell-out by default** (no daemon):
  `qmd query "<question>" --json --files --min-score <t> -n <k>` over the `wiki` collection. The CLI
  inherits the shell environment, sidestepping the MCP-spawn `HOME`/db-path pitfall (qmd issue #615).
- **MCP daemon** — an *advanced* option for heavy users who want warm models (`qmd mcp --http --daemon`);
  set `QMD_CONFIG_DIR` / the db path explicitly so the server opens the real index.
- **Confidence-aware ranking:** qmd ranks by relevance; then re-order by each page's `confidence`
  (down-rank `low`/`very-low`, lift `high`/`authoritative`) and break ties by newer `updated`
  (supersession), per CLAUDE.md §4.6. Then deep-read the top pages and govern as usual.
- **Index-first, always:** `index.md` is read first; qmd is the *fallback / widener* when the catalogue is
  insufficient or the corpus is large. A qmd hit never bypasses the governing deep-read.

## Refresh on write — explicit, agent-driven, NEVER a background process
The agent is the **only** writer of `wiki/` (humans don't hand-edit), so the refresh is a plain **inline
step the agent runs itself** as the last action of a write operation — **not** a daemon, cron job,
launchd job, or file-watcher. Nothing runs while the vault is idle, so nothing can error in the background.

**Whenever the agent creates or updates wiki page(s), immediately refresh both signals for the changed
files, in this order:**
1. **`confidence`** — (re)assign / confirm per CLAUDE.md §4.6 for every changed file. **Always** (not gated on qmd).
2. **qmd embedding** — *then*, **if qmd is active**, run `qmd update && qmd embed` once over the changed files
   (incremental: qmd re-indexes only changed files and re-embeds only changed chunks). Confidence is set
   **first** so the re-embedded file already carries its final frontmatter. A **no-op** when qmd is dormant.

Invoked by every write path — `ingest` (end of an ingest), `query` (after filing a synthesis), `deep-lint`,
and any other operation that writes a page. Run it **once per write operation**, not per file. Because the
agent always knows exactly when and what it changed, it just calls this explicitly — there is no scheduled
or always-on refresh anywhere.

## Graceful degradation (mandatory)
Any qmd call that errors, times out, or returns nonzero → **fall back silently** to `index.md` → `grep`
and carry on. The vault never depends on qmd; it only accelerates with it.

## Hard constraints
- **Retrieval only.** qmd never creates, edits, or deletes wiki pages, and never decides `confidence` or
  conflicts — those stay with `ingest`/`query`/`deep-lint`.
- **No background processes.** The agent only ever issues **one-shot CLI calls** (`qmd search`/`vsearch`/
  `query`/`update`/`embed`) that run and **exit**. It MUST NOT start the MCP daemon (`qmd mcp …`) or any
  long-running/background qmd process — that is a manual, user-only opt-in. Nothing qmd-related stays
  resident after an agent operation.
- **Dormant by default.** Do nothing unless detection passes; never prompt a non-adopter to install qmd.
- **Index-first.** `index.md` is read before qmd; qmd is the semantic fallback/widener, not a replacement.
- **State stays out of git.** qmd config/index/models live in `~/.config/qmd` and `~/.cache/qmd`; a
  project-local index (`.qmd/`, `*.sqlite`) is git-ignored.
- British/UK English in any user-facing output.
