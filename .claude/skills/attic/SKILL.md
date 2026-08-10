---
name: attic
description: >
  Archive vault files into attic/ cold storage, or restore them — the executable runbook for the
  CLAUDE.md §2.1 contract. Use ONLY on an explicit user instruction: /attic, "archive X to the
  attic", "retire these files", "restore Y from the attic", "what's in my attic?". NEVER runs
  automatically — not from IDEAS.md, and a deep-lint suggestion becomes actionable only when the
  owner issues it. Handles one file or a batch (a closed project or campaign): inbound-reference
  census, harvest of future-useful facts into surviving pages, an owner-approved preview, move +
  manifest, a plain-text link sweep, index/log/qmd upkeep, and a control-verified final check.
  Census-scoped reads — never a full-vault pass.
user-invocable: true
---

# attic — cold-storage archive & restore (§2.1, executed)

## Contract
CLAUDE.md §2.1 stays the governing text: the attic is explicit-instruction-only, its contents are
never knowledge, and outside this operation it stays unread. This skill adds **procedure only** —
it can never relax a permission. Never edit the *contents* of an archived file, in either direction.

## Triggers
`/attic archive <files|folder|topic>` · `/attic restore <item>` · `/attic list` · natural language
("archive the X project to the attic", "retire these files", "what's in my attic?"). Passive
context (an `@`-mention, an editor selection, IDEAS.md) never triggers it.

## Archive pipeline

### 0 — Scope
Resolve the instruction to a concrete candidate list: explicit paths, a folder, or a topic located
via `index.md` + targeted grep. Wiki pages, `output/` deliverables and `assets/` files all qualify.
`raw/` stays out of scope unless the owner names it — the source layer is already immutable cold
storage, and archived pages' `sources:` may keep pointing at it (attic→outside links are allowed).

### 1 — Census (read-only)
For every candidate, find inbound references with BOTH pattern families — missing the second family
is the known failure mode (deliverables are often cited as backticked paths, not links):
- **wikilinks**: `grep -rF "[[<basename>" --include='*.md' wiki` (catches `]]`, `|`, `#`, `![[`);
- **plain paths**: `grep -rF "<origin/path>"` plus the bare filename, across wiki/.
Also scan `MANUAL.md`, `README.md`, `output/` (report-only surfaces). Classify every hit:
**live wiki** (must sweep) · **co-candidate** (link stays — attic-internal edges are by design) ·
**`wiki/log.md`** (append-only history, never swept). Positive control (§11): the same probe against
a known-linked live page must return >0 before any "no inbound references" claim. Also check each
basename against `raw/` and `wiki/` for name collisions — this drives the manifest link form.

### 2 — Harvest gate
Before anything moves, read each candidate **wiki page** and fold facts with future value into the
surviving graph: status/outcome facts → the relevant synthesis or campaign page; durable
programme/route/organisation facts → entity pages; reusable personal material (approved bios,
standing decisions) → `wiki/user/`. New knowledge only — never duplicate what survivors already
hold. Deliverables (output/assets) are skimmed for the same purpose, not compiled. Every harvest
edit is listed in the preview.

### 3 — Preview & approval (mandatory gate)
Present the full table — file · origin · one-phrase reason · harvest destination(s) · sweep scale —
and WAIT for the owner's go. No file moves before approval, however obvious the case.

### 4 — Move
Batches get a thematic subfolder (`attic/<topic-year>/`, e.g. `funding-2026/`); singletons go to
the attic root (the standing convention). Move folders intact; quote every path (spaces,
apostrophes). `path:attic/` graph colouring covers subfolders automatically.

### 5 — Manifest
Append to `attic/MANIFEST.md`, newest-first, ONE line per file:
`- [YYYY-MM-DD] <link-or-path> — from `origin/` — one-phrase reason`.
`.md` files → **path-prefixed** wikilink `[[<subfolder>/<name>]]` (unambiguous under basename
collisions; gives the grey graph edge). Non-Markdown → a backticked path (an unresolvable wikilink
is worse than none). Reasons name where harvested facts now live, so a future restore knows what
already survived. The manifest is written only inside this operation.

### 6 — Sweep
Replace every live-wiki inbound reference with plain text: first occurrence per file
`X (archived)`, later occurrences the plain title; reword where a sentence needs it. Co-candidate
links stay; `wiki/log.md` is never rewritten. §4.4 guard: every edited page keeps ≥1 wikilink — if
a sweep would orphan a page, substitute a link to the harvest destination. Remove the candidates'
`index.md` entries and refresh index descriptions that named them. Bump `updated:` only where
knowledge changed — a pure link swap is not a knowledge update.

### 7 — Guarded verify (before the log is written)
Run with §11 positive controls; write the log and refresh qmd ONLY when all pass:
- per-candidate link probe over live wiki (excl. `log.md`) = 0, using the exact link forms
  `"[[<b>]]" "[[<b>|" "[[<b>#" "/<b>]]" "/<b>|"` · control on a kept page name > 0;
- per-candidate path probe = 0 · control on a kept working-file path > 0;
- `index.md` clean of candidates · control on a kept entry > 0;
- no live-wiki links into attic paths: `grep -rF "[[<subfolder>/" wiki` = 0;
- orphan guard: every swept page still contains `[[`;
- moved-file count = manifest-line delta; origin folders hold no candidate remnants; `raw/`
  untouched (`find raw -type f -newermt "<op start>"` empty).
Residues are findings, not embarrassments: fix, re-run the probe, and report them honestly.

### 8 — Registries
Append one `attic` entry to `wiki/log.md` (shell append, never Read+Edit) naming: harvest edits,
swept pages, moves, manifest delta. If qmd is active, run `qmd update && qmd embed`.

## Restore pipeline
1. Read `attic/MANIFEST.md` (this instruction is the sanctioned read); locate the item + origin.
2. Move the file back (recreate the origin folder if needed); delete its manifest line.
3. Wiki page → re-register in `index.md` (fresh one-liner from the page); then offer to re-link the
   plain-text mentions (`grep -rF "<name> (archived)" wiki`) — the owner picks which go live again.
4. Append an `attic` log entry; qmd refresh if active.

## /attic list
Read the manifest back to the owner. Nothing else in the attic is opened.

## Report format
Compact table: moved/restored (count + destination) · harvested (fact → surviving page) · swept
(pages / links) · verify results (each probe with its control). British/UK English.

## Hard constraints
- **Explicit user instruction only**; the Step-3 preview gate is never skipped.
- **Census-scoped reads** — never a full-vault re-read; token discipline throughout.
- **A zero-findings check is a claim**: every probe carries a positive control (CLAUDE.md §11).
- Never edit archived file contents; never sweep co-candidates or `log.md` history.
- deep-lint SUGGESTS candidates (as ready `/attic archive …` lines); only the owner's word runs them.
