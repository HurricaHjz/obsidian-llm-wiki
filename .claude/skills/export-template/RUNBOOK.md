# RUNBOOK — publish & maintain the obsidian-llm-wiki-assistant framework

Turns the private vault into the public framework repo **github.com/HurricaHjz/obsidian-llm-wiki-assistant**, with
your knowledge kept local. Read top to bottom.

## A. Build the template
```bash
bash .claude/skills/export-template/export_template.sh template-export
```
Produces `template-export/` per `SPEC.md`.

## B. Verify (script prints most of this — confirm)
- Skills = **every directory under `.claude/skills/`** (auto-discovered by `list_skills()`; check with `ls .claude/skills` — never a hand-kept list, which has gone stale twice: v0.7.6 and the 2026-08-23 `attic` omission). export-template ships too — users need its `--pull` to update.
- **Suites — run all seven; green = `0 failed` printed by each suite itself** (never compare against a historical count — assertion totals grow):
  ```bash
  for t in capture_write funnel_knobs gather_links run_ledger; do (cd .claude/skills/gather && python3 test_$t.py) || echo "SUITE FAILED: $t"; done
  for t in export_template setup_customisation token_isolation; do (cd .claude/skills/export-template && bash test_$t.sh) || echo "SUITE FAILED: $t"; done
  ```
- `template-export/wiki` & `/raw` hold only `.gitkeep` (no seed, no `index.md`/`log.md`); the demo is in
  `template-export/examples/seed/`.
- No personal leak: grep the build for **your own** name / handle / affiliation
  (e.g. `grep -riE '<your-name>|<your-handle>|<your-org>' template-export`) → expect only the
  LICENSE.md/README author line (intended); `template-export/wiki/user/` is empty.
- **Git-policy test** (the important one):
  ```bash
  cd template-export && git init -q && git add -A
  git check-ignore -q wiki/log.md raw/x.md output/y.md wiki/sources/z.md && echo "content ignored ✓"
  git ls-files | grep -qE 'CLAUDE.md|MANUAL.md|\.claude/skills/|examples/seed' && echo "framework tracked ✓"
  cd ..
  ```
- **setup.sh test**: in a copy, `bash setup.sh` creates `index.md`/`log.md`; `--with-example` loads the demo.

## C. Publish (first time)
1. **github.com → New repository** → name `obsidian-llm-wiki-assistant` → **Public** → do **not** add a README or
   licence (we ship them) → **Create repository**.
2. In Terminal:
   ```bash
   cd template-export
   git init -b main
   git add -A
   git commit -m "obsidian-llm-wiki-assistant: framework v0.1"
   git remote add origin https://github.com/HurricaHjz/obsidian-llm-wiki-assistant.git
   git push -u origin main
   ```
3. On GitHub → **Settings → tick "Template repository"**; add a description + topics
   (`obsidian`, `claude`, `second-brain`, `llm`, `knowledge-management`, `ai-research`).
4. The README images already ship (`assets/framework_demo.png`, `assets/hero.png` — tracked, referenced
   by `README.md`). To refresh one later, replace it under `assets/` at your vault root (where the README
   lives), then `--push` again.

> No `gh` CLI needed. Prefer a GUI? **GitHub Desktop**: File → Add local repo → `template-export` →
> Publish repository (untick "keep private").

## D. Maintain — push and pull (ONE direction at a time)
The framework round-trips with the repo (README.md, LICENSE.md + `assets/` at the vault root; the
build machinery in the skill's `payload/`). Keep your clone **outside the vault**; never sync both ways at
once. **Easiest:**
ask the agent to publish or update via the
`export-template` skill — it automates the steps and **pauses for your confirmation** before anything is
written publicly or back into your vault (see the skill's "Publish (push)" / "Update (pull)" flows). Manual
equivalents:

**Push (vault → repo)** — you improved the framework locally and want to publish it:
```bash
git -C /path/to/obsidian-llm-wiki-assistant pull --ff-only                              # never clobber remote edits
bash .claude/skills/export-template/export_template.sh --push /path/to/obsidian-llm-wiki-assistant
cd /path/to/obsidian-llm-wiki-assistant && git add -A && git diff       # review → commit → push
```
`--push` overlays vault-owned files (CLAUDE.md, MANUAL.md, `README.md`/`LICENSE.md` + `assets/`,
`.claude/skills/**`, `.obsidian` config, `examples/seed`) **and** the build machinery from the skill's
`payload/` (setup.sh, .gitignore, .gitattributes), leaving `.git/` untouched. (`--sync` is an alias.)

**Pull (repo → vault)** — the repo has a newer framework (another machine, a merged PR) and you want it:
```bash
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki-assistant            # preview — writes nothing
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki-assistant --apply    # apply (+ --with-graph for colours)
```
`--pull` previews which framework files differ, then (with `--apply`) copies CLAUDE.md, MANUAL.md,
`README.md`/`LICENSE.md` + `assets/` and the skills into your vault and refreshes the `payload/`
machinery — **never** touching your knowledge (`wiki/ raw/ output/` and your own `assets/` media) or `.obsidian` config. It copies
skills per-name — including `export-template` itself; replacing the running script mid-pull is Unix-safe (the old inode stays open).

### If the GitHub repo gets renamed
GitHub redirects the old URL so pushes keep working, but fix the name promptly — a redirect dies if the
old name is ever re-registered. Three steps, in order:
1. **Detect:** the push output prints a `remote:` moved notice, or
   `gh repo view <owner>/<old-name> --json nameWithOwner` resolves to the new name.
2. **Re-point the clone:** `git -C /path/to/<clone> remote set-url origin
   https://github.com/<owner>/<new-name>.git`, then verify with `git fetch --dry-run`.
3. **Sweep the live framework files** for the old name (README.md, this RUNBOOK, SKILL.md, SPEC.md,
   `payload/setup.sh` — enumerate with `grep -r` first; after replacing, verify zero standalone old-name
   hits remain plus a positive new-name control). Log the sweep as `framework`; it ships on the next
   publish. Historical layers (wiki pages, log entries, archived quotes) keep the old name — history
   stays as written.

## Golden rules
- Edit the framework in the **vault**, not in the repo (else `--push` can't carry your change across).
- **Pull before you push** — keeps `payload/` current and avoids clobbering remote edits (merged PRs).
- **One direction per run:** `--pull` and `--push` never happen together.
- Never `git add` knowledge (`wiki/**`, `index.md`, `log.md`, `raw/**`, `output/**`); the `.gitignore`
  blocks it — don't force past it.
- Never ship personal data; keep the demo clearly deletable (`setup.sh --reset`).
