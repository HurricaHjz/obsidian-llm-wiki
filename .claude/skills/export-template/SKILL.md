---
name: export-template
description: >
  Sync THIS LLM-Wiki framework with its public GitHub repo, ONE direction per run: --push (vault → repo)
  publishes your framework; --pull (repo → vault) updates your framework from a newer repo version. Also
  builds a standalone content-free copy. Use when the user says "publish/export the framework", "update
  the public repo", "pull the latest framework", or "make the base template". Push shows the diff and
  commits+pushes only after you confirm; pull previews first and writes nothing until --apply. Ships the
  engine (CLAUDE.md, Manual.md, skills, graph config) + a tracked demo in examples/seed/, an MIT LICENSE +
  README + setup.sh + a .gitignore that TRACKS the framework and IGNORES all knowledge; strips all
  wiki/raw content + personal data; keeps the AI/LLM-research specialisation. Never copies your knowledge;
  the build dir is deleted after publishing. Full runbook: the RUNBOOK.md in this skill folder.
user-invocable: true
---

# export-template — produce / sync the shareable framework repo

## Goal
Turn this private vault into the public **obsidian-llm-wiki** framework — **without any knowledge** (no
wiki pages, raw sources, logs, or personal data) but **with** the engine (CLAUDE.md, Manual.md, the
skills, the graph config), an empty folder skeleton, a tracked **demo** (`examples/seed/`), a **setup.sh**
bootstrap, an **MIT** licence + README, and a **.gitignore that tracks the framework and ignores all
content**. Keeps the AI/LLM-research specialisation.

> Authoritative runbook + target tree: `RUNBOOK.md` + `SPEC.md` in this skill folder. The human-facing docs
> — **README.md, LICENSE.md, CONTRIBUTING.md + the `assets/` screenshot — live at the vault root** (visible, the
> canonical source); the build machinery (setup.sh, .gitignore/.gitattributes, the demo) lives in `payload/`
> here. No separate kit folder, and no build copy is left in the vault after a publish.

## Triggers
`/export-template` · "publish the framework" · "make/refresh the base template" · "update the public repo".

## Choosing the operation — ASK by default
**If the user's words already name the direction, just do it** — don't ask, and don't make them recite flags:
- "publish" / "push" / "export/share the framework" / "update the public repo" → **push**.
- "pull" / "update my framework from git" / "get the latest framework" → **pull**.
- "build/make the template" / "a content-free copy" → **fresh build**.

**Otherwise** (a bare `/export-template`, "sync my framework", "use export-template") **do not guess** —
ask with `AskUserQuestion`:
1. **Direction:** *Push — publish my framework → GitHub* · *Pull — update my framework ← GitHub* ·
   *Build — a standalone content-free copy*.
2. **Then the sub-option for that choice:**
   - **push** → confirm the repo-clone path (and remind them you will show the diff and wait for an OK).
   - **pull** → *Preview only (writes nothing)* vs *Preview then apply*; and *also pull the colour scheme?*
     (`--with-graph`, default **no**).

The user can always skip the questions by stating it directly ("push, message 'tighten lint'", "pull and
apply with graph"). Honour any options they give; only ask for the ones they left unspecified.

## Three operations — ONE direction per run
**Never sync both ways at once.** Each invocation does exactly one of the following; passing `--pull` and
`--push` together is a hard error.

**`--push <repo>` — vault → repo (publish).** Overlays the vault-owned framework (CLAUDE.md, Manual.md,
`README.md`/`LICENSE.md`/`CONTRIBUTING.md` + `assets/`, `.claude/skills/**` (every skill, incl. export-template), `.obsidian` config,
the seed demo) **plus** the build machinery from this skill's `payload/` (.gitignore/.gitattributes, setup.sh)
into your existing clone — leaving `.git/` and all knowledge untouched. Then run the **guided publish
flow** below. (`--sync` is a back-compat alias.)
```bash
bash .claude/skills/export-template/export_template.sh --push /path/to/obsidian-llm-wiki
```

**`--pull <repo>` — repo → vault (update from a newer version).** `git pull`s your clone, then **previews**
exactly which framework files would change and **writes nothing**. Re-run with `--apply` to copy the repo's
framework into your vault (incl. `README.md`/`LICENSE.md`/`CONTRIBUTING.md` + `assets/` at the vault root) and
refresh the `payload/` machinery. Add `--with-graph` to also pull `.obsidian/graph.json` (the colour scheme);
`app.json`/appearance/core-plugins are **never** pulled.
```bash
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki            # preview
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki --apply    # apply
```

**Fresh build (no flag)** — a standalone content-free copy (the very first publish, or inspection):
```bash
bash .claude/skills/export-template/export_template.sh template-export
```

## Where the publish files live (and why nothing goes stale)
- **At the vault root** — `README.md`, `LICENSE.md`, `CONTRIBUTING.md` + the `assets/` screenshot: canonical and
  visible, so you read/verify and edit them in place, exactly as a clone shows them (all README links resolve).
- **`payload/` (in this skill)** — the build machinery that shouldn't sit loose in a vault: setup.sh and
  `.gitignore`/`.gitattributes` (kept as inert `*.txt`), plus the seed demo.

Both round-trip: **push reads** from these locations; **`pull --apply` writes** back to them (the root docs →
the vault root, the machinery → `payload/`). So an edit that lands on the repo (a merged PR, a typo fix)
flows home on the next pull and is preserved on the next push — never clobbered. The only thing deleted after
a publish is the build dir (`template-export/`); the root files and `payload/` always stay.

## Publish (push) — guided; the agent automates, you confirm
When the user wants to publish/update the public repo (`/export-template publish`, "push the latest
framework"), do it end-to-end but **pause once for confirmation before anything goes public**:
1. **Pull-then-overlay:** `bash .claude/skills/export-template/export_template.sh --push <repo>`.
   First do `git -C <repo> pull --ff-only` (so you never clobber unpulled remote edits), then the overlay.
   (For the very first publish, do a fresh build + create the GitHub repo instead — RUNBOOK §C.)
2. **Stage + review:**
   ```bash
   git -C <repo> add -A
   git -C <repo> --no-pager diff --cached --stat     # summary of what changed
   git -C <repo> --no-pager diff --cached            # full diff (skip only if very large)
   ```
   **Show the user** this and state plainly what will be published.
3. **Confirm — mandatory gate:** ask the user to approve and to give/confirm a commit message.
   **Never `commit` or `push` without an explicit "yes".**
4. **Publish:** `git -C <repo> commit -m "<message>" && git -C <repo> push`
5. **Report** the commit + push result + the repo URL. If `push` fails on auth, tell the user to set up a
   GitHub token / SSH key — never handle their credentials yourself.
6. **Clean up — keep no local copy:** once the push succeeds, delete the build directory
   (`rm -rf template-export`). A `--push` writes straight to the external repo clone, so nothing is left
   in the vault either way (`payload/` stays — it is the skill, not a build artifact).

## Update (pull) — guided; preview → confirm → apply
When the user wants to bring a newer framework from the repo into their vault ("pull the latest framework",
"update my framework from git"):
1. **Preview:** `bash .claude/skills/export-template/export_template.sh --pull <repo>`. Show the user the
   listed framework files that would change (README/CLAUDE/Manual/skills, plus the `payload/` refresh).
   **Nothing is written yet.**
2. **Confirm — mandatory gate:** ask the user to approve overwriting those vault framework files. Remind
   them their knowledge (`wiki/ raw/ output/` (and your own `assets/` media)) and `.obsidian` config are left untouched.
   **Never `--apply` without an explicit "yes".**
3. **Apply:** `bash .claude/skills/export-template/export_template.sh --pull <repo> --apply`
   (add `--with-graph` only if they also want the colour scheme).
4. **Report** what changed; suggest re-reading CLAUDE.md and reopening Obsidian if skills/graph changed.

## Guarantees
- **One direction per run:** `--pull` and `--push` are mutually exclusive (passing both errors out) — the
  framework never syncs both ways at once.
- **Pull is preview-first & safe:** `--pull` writes nothing without `--apply`; even with `--apply` it
  touches only framework files + `payload/`, **never** your knowledge (`wiki/ raw/ output/` (and your own `assets/` media)) or
  your `.obsidian` config (`graph.json` only, and only with `--with-graph`). It copies skills per-name —
  including `export-template` itself; replacing the running script mid-pull is Unix-safe (the old inode
  stays open, the new version applies next run).
- **No build copy left behind:** the build dir (`template-export/`) is deleted after publishing; the
  persistent sources are the vault-root docs (`README.md`, `LICENSE.md`, `CONTRIBUTING.md`, `assets/`) and this
  skill's `payload/` (setup.sh, git dotfiles, demo) — both kept fresh by `pull --apply`.
- **Never publishes unreviewed:** the publish flow always shows the diff and waits for your explicit OK
  before `commit`/`push`; your git credentials stay yours.
- **Read-only on the vault except `pull --apply`** (build/push write only under OUT / the repo clone).
- **No knowledge or personal data shipped** — `wiki/**`, `raw/**`, logs, `wiki/user/**` are never copied;
  `wiki/` + `raw/` ship empty (`.gitkeep`); the demo lives in `examples/seed/` only.
- **Git policy baked in**: the shipped `.gitignore` tracks the framework and ignores all content, so a
  user's notes never get committed (matches CLAUDE.md §11).
- `export-template` **ships too** — it is the contributor publish tool (see the Manual's Advanced caution).
  It syncs like any other skill; non-contributors can simply ignore it.

## After building — verify + publish
See RUNBOOK.md §B (verify: content git-ignored; framework tracked; no personal leak) and
§C (publish: GitHub New repo → `git init/add/commit/remote/push` → mark as a Template repository).

## Relationship to other skills & to Obsidian Git
- **export-okf** exports the *knowledge* (wiki) as an OKF bundle. **export-template** exports the
  *framework* (the empty engine) for others to reuse.
- **Obsidian Git** (plugin) is **complementary, not a replacement.** It backs up the *whole vault — your
  knowledge included — to a PRIVATE remote* (history + multi-device sync) by versioning the vault's own git
  repo. `export-template` instead builds and publishes a *separate, knowledge-free clone* to the *public*
  framework repo. Different repos, different jobs: never point the vault's backup remote at the public
  framework repo, and never publish knowledge. The publish/pull git steps stay shell-driven here because
  the framework repo is a separate clone, **not** the open vault that Obsidian Git operates on.
