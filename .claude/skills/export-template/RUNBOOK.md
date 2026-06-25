# RUNBOOK — publish & maintain the obsidian-llm-wiki framework

Turns the private vault into the public framework repo **github.com/HurricaHjz/obsidian-llm-wiki**, with
your knowledge kept local. Read top to bottom.

## Decisions (locked)
- ✅ Seed demo lives in `examples/seed/` (tracked); `wiki/`+`raw/` ship empty.
- ✅ `.gitignore` tracks the framework, ignores all knowledge (`wiki/`/`raw/`/`index.md`/`log.md`/`output/`/`okf-export/`).
- ✅ AI/LLM-research specialisation kept; **MIT**, © 2026 Mingjun (Jerry) Zhang.
- ✅ Beginner-first `Manual.md`; `README.md` = onboarding that points to the Manual.
- ✅ `setup.sh` bootstraps a fresh clone; `CONTRIBUTING.md` + `.gitattributes` included.

## A. Build the template
```bash
bash .claude/skills/export-template/export_template.sh template-export
```
Produces `template-export/` per `SPEC.md`.

## B. Verify (script prints most of this — confirm)
- Skills = all of `ingest gather query lint export-okf output export-template` (export-template ships too, for contributors).
- `template-export/wiki` & `/raw` hold only `.gitkeep` (no seed, no `index.md`/`log.md`); the demo is in
  `template-export/examples/seed/`.
- No personal leak: grep the build for **your own** name / handle / affiliation
  (e.g. `grep -riE '<your-name>|<your-handle>|<your-org>' template-export`) → expect only the
  LICENSE.md/README author line (intended); `template-export/wiki/user/` is empty.
- **Git-policy test** (the important one):
  ```bash
  cd template-export && git init -q && git add -A
  git check-ignore -q wiki/log.md raw/x.md output/y.md wiki/sources/z.md && echo "content ignored ✓"
  git ls-files | grep -qE 'CLAUDE.md|Manual.md|\.claude/skills/|examples/seed' && echo "framework tracked ✓"
  cd ..
  ```
- **setup.sh test**: in a copy, `bash setup.sh` creates `index.md`/`log.md`; `--with-example` loads the demo.

## C. Publish (first time)
1. **github.com → New repository** → name `obsidian-llm-wiki` → **Public** → do **not** add a README or
   licence (we ship them) → **Create repository**.
2. In Terminal:
   ```bash
   cd template-export
   git init -b main
   git add -A
   git commit -m "obsidian-llm-wiki: framework v0.1"
   git remote add origin https://github.com/HurricaHjz/obsidian-llm-wiki.git
   git push -u origin main
   ```
3. On GitHub → **Settings → tick "Template repository"**; add a description + topics
   (`obsidian`, `claude`, `second-brain`, `llm`, `knowledge-management`, `ai-research`).
4. The README screenshot already ships at `assets/framework_demo.png` (tracked, referenced by `README.md`).
   To refresh it later, replace `assets/framework_demo.png` at your vault root (where the README lives),
   then `--push` again.

> No `gh` CLI needed. Prefer a GUI? **GitHub Desktop**: File → Add local repo → `template-export` →
> Publish repository (untick "keep private").

## D. Maintain — push and pull (ONE direction at a time)
The framework round-trips with the repo (README.md, LICENSE.md, CONTRIBUTING.md + `assets/` at the vault root; the
build machinery in the skill's `payload/`). Keep your clone **outside the vault**; never sync both ways at
once. **Easiest:**
ask the agent to publish or update via the
`export-template` skill — it automates the steps and **pauses for your confirmation** before anything is
written publicly or back into your vault (see the skill's "Publish (push)" / "Update (pull)" flows). Manual
equivalents:

**Push (vault → repo)** — you improved the framework locally and want to publish it:
```bash
git -C /path/to/obsidian-llm-wiki pull --ff-only                              # never clobber remote edits
bash .claude/skills/export-template/export_template.sh --push /path/to/obsidian-llm-wiki
cd /path/to/obsidian-llm-wiki && git add -A && git diff       # review → commit → push
```
`--push` overlays vault-owned files (CLAUDE.md, Manual.md, `README.md`/`LICENSE.md`/`CONTRIBUTING.md` + `assets/`,
`.claude/skills/**`, `.obsidian` config, `examples/seed`) **and** the build machinery from the skill's
`payload/` (setup.sh, .gitignore, .gitattributes), leaving `.git/` untouched. (`--sync` is an alias.)

**Pull (repo → vault)** — the repo has a newer framework (another machine, a merged PR) and you want it:
```bash
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki            # preview — writes nothing
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki --apply    # apply (+ --with-graph for colours)
```
`--pull` previews which framework files differ, then (with `--apply`) copies CLAUDE.md, Manual.md,
`README.md`/`LICENSE.md`/`CONTRIBUTING.md` + `assets/` and the skills into your vault and refreshes the `payload/`
machinery — **never** touching your knowledge (`wiki/ raw/ output/` and your own `assets/` media) or `.obsidian` config. It copies
skills per-name — including `export-template` itself; replacing the running script mid-pull is Unix-safe (the old inode stays open).

## Golden rules
- Edit the framework in the **vault**, not in the repo (else `--push` can't carry your change across).
- **Pull before you push** — keeps `payload/` current and avoids clobbering remote edits (merged PRs).
- **One direction per run:** `--pull` and `--push` never happen together.
- Never `git add` knowledge (`wiki/**`, `index.md`, `log.md`, `raw/**`, `output/**`); the `.gitignore`
  blocks it — don't force past it.
- Never ship personal data; keep the demo clearly deletable (`setup.sh --reset`).
```

The `export-template` skill now **ships too** (for contributors); its `payload/` is its build data, and the
SPEC/RUNBOOK/tests here travel with it. Non-contributors can ignore it (see the Manual's Advanced caution).
