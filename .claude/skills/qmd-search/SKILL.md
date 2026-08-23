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
A thin, **dormant** adapter to `qmd` (design: `wiki/developments/qmd-opt-in-design.md`; setup runbook:
`wiki/developments/equipping-the-wiki-with-qmd.md`). It does **not** replace `index.md` (the curated, read-first catalogue); it is the
*semantic fallback* `query`/`output` reach for when the catalogue under-covers a question, and the
**refresh hook** that keeps qmd's embeddings current as the wiki changes. qmd retrieves; the wiki governs
(compile, cross-link, confidence, conflicts).

## Activation — capability detection (the opt-in *is* installation)
Use qmd **only if all three hold**; otherwise fall through to the default search silently:
1. `command -v qmd` succeeds (qmd installed), AND
2. an index exists for this vault (`qmd status` lists indexed collections), AND
3. there is **no `.qmd-off` marker** in the vault root — create that file to force qmd off without uninstalling; its absence means **active** (installing qmd + building an index *is* the opt-in).

This is one cheap shell check. If any condition fails, **do nothing**: the agent uses `index.md` → `grep`
exactly as normal. A fresh clone or a non-adopter is unaffected, with no prompt to install anything.

## When to invoke (opt-in — never on every search)
qmd search is **not** a default step. Invoke it only when:
1. **the user explicitly asks** (`/qmd-search`, "search semantically", "use qmd"), **or**
2. **the agent judges the cheap path insufficient** — `index.md` + `grep` under-cover the question (it needs
   semantic recall, or the corpus is too large to scan reliably).

Otherwise answer from `index.md` → `grep` and **do not call qmd** — a qmd *query* reads passages into the
agent's context (real tokens), so it must earn that cost. This gates only the **read** side; the **write**
side — refreshing embeddings on every page change — always runs when qmd is active (local compute,
≈ no agent tokens).

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

## Refresh on write — one-shot, NEVER a resident process
Two signals refresh whenever wiki page(s) are created or updated:
1. **`confidence`** — (re)assign / confirm per CLAUDE.md §4.6 for every changed file. **Always the
   agent's job**, never a hook's, and never gated on qmd.
2. **qmd embedding** — `qmd update && qmd embed`, once per write operation, never per file (incremental
   **per file, not per chunk**: qmd keys embeddings on a file's whole-content hash, so an unchanged file
   is skipped entirely and a changed one re-embeds *all* of its chunks — which is why `wiki/log.md` is
   excluded from the collection, CLAUDE.md §10). A no-op when qmd is dormant.

**Enforcement — a turn-end hook, not an agent step.** Measured 2026-08-23: as an agent-executed step the
embedding refresh did not fire at all, leaving the index 3 days and 138 files stale while every session
believed it current. Duties that gate nothing are not performed (this vault's 88%-vs-4% finding). So where
the harness supports it, the refresh belongs in a **`Stop` hook** — the harness runs it once per turn, so
no agent can forget it, and it costs zero agent tokens. **The agent then does NOT run the qmd commands
inline**; it still owns step 1. This is not a daemon, cron job, launchd job or file-watcher: the hook is a
one-shot that runs and exits, nothing stays resident, and nothing runs while the vault is idle.

The live hook is in this vault's `.claude/settings.json` (vault-local; it is not part of the shipped
framework, so an adopter installs their own). Shape, with the guards that matter:
```bash
command -v qmd >/dev/null 2>&1 || exit 0          # qmd absent      -> silent no-op
[ -e "$D/.qmd-off" ] && exit 0                     # forced off      -> silent no-op
[ -e "$S" ] && [ -z "$(find "$D/wiki" "$D/raw" -newer "$S" -print -quit)" ] && exit 0   # nothing changed
mkdir "$L" 2>/dev/null || exit 0                   # another refresh in flight
qmd update >/dev/null 2>&1 && qmd embed >/dev/null 2>&1 && mv -f "$S.new" "$S"
```
- **Gate on the filesystem, not on `qmd update`'s output.** An earlier design parsed its stdout and failed
  its own positive control; `find -newer` against a stamp file is ground truth and passes
  no-change / modify / create / delete / missing-stamp. Directory mtimes make deletions visible too.
- **Stamp before the work, promote after success** (`$S.new` → `$S`), so a file changed mid-refresh is
  caught next turn rather than skipped.
- **Fail open, never block.** Every premise failure exits 0; a missing stamp means "refresh".
- Costs ~10 ms on a turn that changed nothing, against ~1–75 s for an unconditional `qmd embed`.

**Where no such hook exists** (another harness, hooks disabled), the fallback is the original inline rule:
the agent runs `qmd update && qmd embed` itself as the last action of a write operation — `ingest`,
`query` after filing a synthesis, `deep-lint`, or any other write path. `deep-lint`'s own refresh remains
the periodic backstop either way.

## Graceful degradation (mandatory)
Any qmd call that errors, times out, or returns nonzero → **fall back silently** to `index.md` → `grep`
and carry on. The vault never depends on qmd; it only accelerates with it.

## Hard constraints
- **Retrieval only.** qmd never creates, edits, or deletes wiki pages, and never decides `confidence` or
  conflicts — those stay with `ingest`/`query`/`deep-lint`.
- **Nothing resident.** Every qmd invocation — by the agent or by the turn-end refresh hook — is a
  **one-shot CLI call** (`qmd search`/`vsearch`/`query`/`update`/`embed`) that runs and **exits**. The
  agent MUST NOT start the MCP daemon (`qmd mcp …`) or any long-running/watching qmd process; that is a
  manual, user-only opt-in. Nothing qmd-related stays resident, and nothing runs while the vault is idle.
- **Dormant by default.** Do nothing unless detection passes; never prompt a non-adopter to install qmd.
- **Index-first.** `index.md` is read before qmd; qmd is the semantic fallback/widener, not a replacement.
- **State stays out of git.** qmd config/index/models live in `~/.config/qmd` and `~/.cache/qmd`; a
  project-local index (`.qmd/`, `*.sqlite`) is git-ignored.
- British/UK English in any user-facing output.
