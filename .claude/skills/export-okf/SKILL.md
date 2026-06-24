---
name: export-okf
description: >
  Export the wiki/ knowledge base as a conformant Open Knowledge Format (OKF v0.1) bundle — a
  portable, vendor-neutral directory of Markdown concept files. Use when the user runs /export-okf
  or asks to "export to OKF", "make an OKF bundle", "produce a portable/shareable bundle", or share
  the vault with other agents/tools. Deterministic and READ-ONLY w.r.t. the vault (never mutates
  wiki/); writes the bundle to okf-export/. It derives OKF frontmatter (description/resource/timestamp),
  converts [[wikilinks]] to bundle-relative markdown links (code-aware), copies referenced media,
  generates per-directory index.md (§6) + a root log.md (§7), and validates conformance (§9).
user-invocable: true
---

# export-okf — turn the vault into a portable OKF bundle

Why this exists: OKF is a *format*; `CLAUDE.md` is the *method*. This exports the former from the
latter (the "Option A" plan) — see the synthesis [[claude-md-vs-okf-complementary-layers]] and the
concept [[Open Knowledge Format]]. **Opt-in**: the vault stays the source of truth; OKF is a derived
artifact, only worth producing when sharing / interop / ingesting others' bundles is the goal.

## Trigger
`/export-okf`, or natural language: "export to OKF", "make/produce an OKF bundle", "a portable/shareable bundle".

## Run it (deterministic, read-only on `wiki/`)
```bash
python3 .claude/skills/export-okf/export_okf.py --out okf-export
```
Defaults: `--wiki wiki/`, `--assets assets/`, `--out okf-export/`. The script:
1. **Scans** `wiki/**` (the reserved root `index.md` / `log.md` are regenerated, not copied).
2. **Emits** each page with OKF frontmatter: keeps `type` / `title` / `tags` **and all extra keys**
   (carry-through), and derives `description` (page's `index.md` line, else first prose sentence),
   `resource` (from `source_url` / `sources`), `timestamp` (ISO 8601 from `updated`).
3. **Converts links**: `[[Page|alias]]` → bundle-relative `[alias](/path.md)` (with `#anchors`),
   `![[img]]` → `![](/assets/img)`. **Code spans/fences are protected** (example links aren't
   rewritten); unresolved links degrade to plain text (the spec tolerates broken links).
4. **Generates** per-directory `index.md` (§6: `* [Title](url) - description`) + a root `index.md`
   (progressive disclosure) + `log.md` (§7: date-grouped, newest-first, ISO dates).
5. **Copies** referenced media, then **validates** (§9) and prints a summary (concepts, broken links,
   conformance). Exit code is non-zero if any conformance issue is found.

## Guarantees
- **Never mutates `wiki/`** — output goes only to `okf-export/` (excluded from the Obsidian graph via
  `app.json` and from git via `.gitignore`).
- **Deterministic** — same vault ⇒ byte-identical bundle.
- **Unit-tested** — `python3 .claude/skills/export-okf/test_export_okf.py` (self-contained fixture
  vault; 39 checks covering frontmatter derivation, link conversion incl. code-awareness, indexes,
  log, asset copy, conformance, read-only, determinism).

## Maintenance
OKF is **v0.1 draft** and will change — if the spec moves, update the link/index/log rules and
`validate()` here (and re-run the test). To export a slice (one cluster) rather than the whole vault,
point `--wiki` at a subtree (future enhancement).
