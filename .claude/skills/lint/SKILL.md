---
name: lint
description: >
  Health-check the Obsidian wiki — the "static analysis" pass for a knowledge base. Use when the
  user runs /lint, /health, /scan, or asks to "check the wiki", "find broken links", "clean up the
  wiki", or "find gaps/orphans/conflicts". Read-only scan that reports dead links, dead media
  embeds, orphan pages, pages missing from index.md, unresolved knowledge conflicts, live links
  leaking into the attic, and the count of pending `flagged:` freshness flags (≥5 suggests a deep-lint). Also restores the graph colour
  palette on request (on-demand only, never on a routine scan). Proposes fixes but only applies them
  after the user confirms.
user-invocable: true
---

# lint — knowledge-graph health check

## Goal
Find the rot that accumulates as a knowledge base grows: **dead links, orphans, unindexed pages,
unresolved conflicts.**

## When to run (and when not)
**Don't lint routinely after a normal ingest** — ingest/query leave the graph integrity-clean by
construction (CLAUDE.md §6). Run lint for *drift* (manual edits/renames/deletes in Obsidian, external or
OneDrive/git sync changes) and periodic *discovery* (emerging gap pages, cross-corpus contradictions,
stale claims).

**Scope boundary:** confidence coverage, staleness scoring, and online-source freshness are **not**
lint's job — they live in the heavier, ~monthly **`deep-lint`**. Routine `/lint` stays cheap and never
reads pages for confidence or fetches anything.

## Triggers
`/lint` · `/health` · `/scan` · "check my wiki" · "find broken links / orphans / gaps".

## Pipeline (read-only until the user approves fixes)

### 1 — Index consistency
Read `wiki/index.md`; glob every `.md` under `wiki/` (exclude `index.md`, `log.md`).
Report: pages registered in the index but **missing on disk**, and pages on disk but **not registered**.

### 2 — Link health (one shared script — the single source of truth for link rules)
Run `python3 .claude/skills/lint/check-links.py` (exit 0 = clean, 1 = findings; deep-lint's
structural pass uses the same script). It applies the codified rules so scans never re-derive them:
code spans / fenced blocks / HTML comments are not links; frontmatter `aliases` resolve; vault-path
and root-doc targets resolve; `wiki/log.md` is exempt as a source (append-only history); and **media
embeds `![[name.png|pdf|…]]` are checked against `assets/`** — a missing target is a **dead embed**,
reported separately (they are checked, not skipped). The script prints its scan totals as its own
positive control (§11): zero findings with zero links scanned is a broken probe, not a clean vault.
- Orphans are agent-checked (not part of the script): a page with **no inbound links** from any other page → **orphan** — but **exempt** `index`, `log`, and `maps/` pages (Maps of Content are navigational entry points, not orphans).

### 2b — Pending freshness flags (count only — reconciling them is deep-lint's job)
`grep -rl "^flagged:" wiki --include='*.md' | wc -l` — with the engine control
`grep -rl "^confidence:" wiki --include='*.md' | wc -l` (must be >0, proving the probe ran).
Report the count; at **≥5 flagged pages**, suggest running `/deep-lint` (the adaptive-cadence
signal from `wiki/developments/deeplint-scalable-maintenance-design.md`). Never read or resolve
the flagged pages here — lint counts, deep-lint reconciles.

### 2c — Attic-leak check (filenames only — attic contents are never opened)
Live pages must never link into the attic (CLAUDE.md §2.1): Obsidian resolves wikilinks vault-wide,
so a surviving `[[link]]` to an archived note silently reconnects retired material and can pull a
query in. List basenames only — `find attic -type f -name '*.md'`, skip `MANIFEST.md` (the check
reads names, never contents; attic absent or empty → report "attic-leak: n/a"). For each basename
`b`, grep live wiki (excluding `wiki/log.md`, append-only history) for the exact link forms
`"[[b]]" "[[b|" "[[b#" "/b]]" "/b|"` — plain-text mentions ("b (archived)") are the §2.1 sweep
style and are NOT findings. Any hit is a **leak finding**: report it; the fix (owner-confirmed) is
re-sweeping to plain text per §2.1, or `/attic restore` if the page should live again. Control
(§11): the same pipeline against one known live page name must return >0 before reporting "no leaks".

### 2d — qmd registry guard (one scripted check; skipped silently when qmd is dormant)
`wiki/log.md` must stay out of the semantic index (CLAUDE.md §10) — embeddings key on a file's
whole-content hash, so every append re-embeds the whole timeline, and a hit invites an ~80k-token
`qmd get`. The exclusion lives in `~/.config/qmd/index.yml`, **outside the vault and outside both
git repos**, so it can disappear silently. Run
`sh .claude/skills/lint/check-qmd-registry.sh .` and copy its one line into the report verbatim.
The script carries its own §11 control (`index.md`, deliberately kept, must be listed) and reports
`PROBE FAILED` rather than "clean" when its own premise breaks. Exit 1 = finding; the fix is to
restore `ignore: ["**/log.md"]` on the `wiki` collection and re-run `qmd update`.

### 2e — Skill-injection guard (names only — no skill contents are read)
Third-party installers write skill directories into agent skill roots (a user-level skill loads into
**every** session — e.g. Agent Reach's documented SKILL.md auto-install; two register incidents prove
the class: `wiki/developments/known-issues.md` 2026-08-21/22). Diff both roots against the sanctioned
baseline `.claude/skills/lint/sanctioned-skills.txt`:
```bash
b=".claude/skills/lint/sanctioned-skills.txt"    # ships with the framework: vault-skill names only
h="$HOME/.claude/skills/.sanctioned.txt"         # machine-local baseline: user-level skill names
[ -s "$b" ] || { echo "PROBE FAILED: vault baseline missing/empty"; }   # premise guard, never "clean"
comm -13 <(grep '^vault:' "$b" | cut -d: -f2 | sort) <(ls .claude/skills | sort)
[ -d ~/.claude/skills ] || echo "PROBE FAILED: ~/.claude/skills missing"   # premise guard, never "clean"
[ -s "$h" ] && [ -d ~/.claude/skills ] && comm -13 <(sort "$h") <(ls ~/.claude/skills | sort)
```
Any name printed = an **unsanctioned skill directory** (finding: report it; the fix — owner-confirmed —
is removal, or a conscious baseline addition in the same pass that sanctions it). No machine-local
baseline yet (fresh machine) → report the current `~/.claude/skills` list as info and propose seeding
`$h` from it after the owner reviews — never a finding, never auto-seeded. Baseline entries missing on
disk are reported as info (drift), not findings. §11 control before trusting an empty result: re-run
one `comm` with a known-absent name injected into the disk side (`printf 'zzz-ctrl\n'`) and confirm it
prints. A missing/empty vault baseline or an unreadable root reports `PROBE FAILED`, never "clean".
(Deep-lint inherits this via its structural pass.)

### 3 — Conflict audit
Find pages containing `## Conflicts / Open Questions`. List each unresolved conflict (the two sides)
as cognitive tech-debt to resolve.

### 4 — Gap scan (optional, suggestive)
Note entities/concepts mentioned often but lacking their own page, and stale claims newer sources
supersede. Suggest sources or web searches to fill gaps.

## Graph colour restore (on-demand — NOT part of a routine lint)
The graph's per-type colours live in `.obsidian/graph.json` → `colorGroups`. That file is **volatile**:
Obsidian rewrites it from memory whenever a graph setting changes (or a sync clobbers it), and can wipe
the palette so the graph turns all-grey. A wiped palette is **immediately visible**, so handle it
**only on a real signal** — never scan for it on a routine lint.

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
- **N dead links**: [[Source]] → [[Missing Target]] · **N dead embeds**: [[Source]] → ![[missing.png]]
- **N unresolved conflicts**: [[Page]]

### ⏳ Flags
- **N pages carry `flagged:`** (engine control OK) — ≥5 → consider `/deep-lint`
- `<the qmd-registry line, verbatim from the script>` · `attic-leak: none / n/a / N leaks` · `skill-guard: clean / N unsanctioned (control OK)`

### 🛠️ Proposed next steps
1. Auto-register unindexed pages? (y/n)
2. Re-derive / resolve the listed conflicts?
```

## Hard constraints
- **Read-only scan.** Do not modify, rename, or delete anything before the report.
- **No unverified "clean".** A check that returns zero findings must be validated with a positive
  control (the same probe matching something known to exist) before the report may say "clean"
  (CLAUDE.md §11).
- **Wait for confirmation** before applying any fix.
- **Graph colour restore is on-demand only** (see its section) — never scanned or read on a routine lint.
- After approved fixes, append to `wiki/log.md`:
  `## [YYYY-MM-DD] lint | fixed N issues (M dead links, K unindexed)`.
- **Refresh on write:** if approved fixes touched wiki pages, the `qmd-search` refresh applies — run it
  inline only where no turn-end refresh hook is installed (that skill owns the rule); a no-op when qmd is dormant.
- Report in **British/UK English**.
