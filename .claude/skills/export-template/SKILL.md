---
name: export-template
description: >
  Sync THIS LLM-Wiki framework with its public GitHub repo, ONE direction per run: --push (vault → repo)
  publishes your framework; --pull (repo → vault) updates your framework from a newer repo version. Also
  builds a standalone content-free copy. Use when the user says "publish/export the framework", "update
  the public repo", "pull the latest framework", or "make the base template". Push shows the diff and
  commits+pushes only after you confirm; pull previews first and writes nothing until --apply. Ships the
  engine (CLAUDE.md, MANUAL.md, skills, graph config) + a tracked demo in examples/seed/, an MIT LICENSE +
  README + setup.sh + a .gitignore that TRACKS the framework and IGNORES all knowledge; strips all
  wiki/raw content + personal data; keeps the AI/LLM-research specialisation. Never copies your knowledge;
  the build dir is deleted after publishing. Full runbook: the RUNBOOK.md in this skill folder.
user-invocable: true
---

# export-template — produce / sync the shareable framework repo

## Goal
Turn this private vault into the public **obsidian-llm-wiki-assistant** framework — **without any knowledge** (no
wiki pages, raw sources, logs, or personal data) but **with** the engine (CLAUDE.md, MANUAL.md, the
skills, the graph config), an empty folder skeleton, a tracked **demo** (`examples/seed/`), a **setup.sh**
bootstrap, an **MIT** licence + README, and a **.gitignore that tracks the framework and ignores all
content**. Keeps the AI/LLM-research specialisation.

> Authoritative runbook + target tree: `RUNBOOK.md` + `SPEC.md` in this skill folder. The human-facing docs
> — **README.md, LICENSE.md + the `assets/` screenshot — live at the vault root** (visible, the
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

**`--push <repo>` — vault → repo (publish).** Overlays the vault-owned framework (CLAUDE.md, MANUAL.md,
`README.md`/`LICENSE.md` + `assets/`, `.claude/skills/**` (every skill, incl. export-template), `.obsidian` config,
the seed demo) **plus** the build machinery from this skill's `payload/` (.gitignore/.gitattributes, setup.sh)
into your existing clone — leaving `.git/` and all knowledge untouched. Then run the **guided publish
flow** below. (`--sync` is a back-compat alias.)
```bash
bash .claude/skills/export-template/export_template.sh --push /path/to/obsidian-llm-wiki-assistant
```

**`--pull <repo>` — repo → vault (update from a newer version).** `git pull`s your clone, then **previews**
exactly which framework files would change and **writes nothing**. Re-run with `--apply` to copy the repo's
framework into your vault (incl. `README.md`/`LICENSE.md` + `assets/` at the vault root) and
refresh the `payload/` machinery. Add `--with-graph` to also pull `.obsidian/graph.json` (the colour scheme);
`app.json`/appearance/core-plugins are **never** pulled.
```bash
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki-assistant            # preview
bash .claude/skills/export-template/export_template.sh --pull /path/to/obsidian-llm-wiki-assistant --apply    # apply
```

**Fresh build (no flag)** — a standalone content-free copy (the very first publish, or inspection):
```bash
bash .claude/skills/export-template/export_template.sh template-export
```

## Where the publish files live
- **At the vault root** — `README.md`, `LICENSE.md` + the `assets/` screenshot
  (canonical and visible; edit them in place).
- **`payload/` (in this skill)** — the build machinery: setup.sh and `.gitignore`/`.gitattributes`
  (kept as inert `*.txt`), plus the seed demo.

Both round-trip: **push reads** from these locations; **`pull --apply` writes** back to them (the root docs →
the vault root, the machinery → `payload/`), so a repo-side edit flows home on the next pull and is never
clobbered by a push. The only thing deleted after a publish is the build dir (`template-export/`); the root
files and `payload/` always stay.

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
   **Personal-strings gate (mandatory, before the recap):** scan the **staged tree** — what will
   actually ship — not the diff: `git -C <repo> grep -i --cached -e "<string>"` for every derived
   personal string, plus one positive control (a string known to exist, e.g. `wiki`). **Derive the
   strings at runtime, never hardcode them here** (they must not ship): the `agent_name` from
   `CUSTOMISATION.md` frontmatter, the git handle/email local-part from the repo's config,
   the vault's absolute-path components, and any extra lines in `output/publish-gate-strings.txt`
   (optional, owner-local, never shipped). Filter hits against `publish-allowlist.md` (in this skill
   folder): every allowlisted line carries its justification and must itself be public-safe. Any
   **unallowlisted** hit HALTS the publish for inspection; a hit adjudicated benign is added to the
   allowlist with its reason, once, permanently. Zero unallowlisted hits + control > 0 = gate passed.
   **Throttle gate (mandatory, before the recap):** `python3 .claude/skills/delegate/throttle.py check --require default` must exit 0 on the vault — a template is never published with floor definitions, drifted tiers or a description naming a current tier; a `PROBE FAILED` halts the publish like any other gate failure.
   **Candidate recap — mandatory final confirmation:** before committing, present the **candidate's
   row** — `Ver | Feature | What it does | What it achieves` — verified against the actual files/tests
   (never from memory). **Derive the version number from evidence, not memory**: read
   `git -C <repo> log --oneline` AND the vault log's `export |` entries at recap time — a parallel
   session may have published since this session last looked (v0.8.3 shipped mislabelled because a
   same-day release was missed this way). The **full version-family table** — every release of the
   current minor so far plus the candidate, each row verified — runs only at a **minor-version
   boundary** (the first release of a new minor, vX.Y.0) or when the owner asks for a "full recap".
   The user's go-ahead on the presented recap is the publish approval.
   **Framework paths are name-neutral (2026-08-28).** The agent's own name is user-space config
   (`agent_name`, seeded blank in the shipped `setup.sh`), so no shipped path or env var may embed
   it. The agent home is `~/.llm-wiki/` (ingest run ledger, and any future agent-owned state) and
   the lane belt is `LLM_WIKI_LANE`. A vault whose home already sits elsewhere aliases it with a
   machine-local symlink rather than moving data, so the convention costs no migration.
3. **Confirm — mandatory gate:** ask the user to approve and to give/confirm a commit message.
   **Never `commit` or `push` without an explicit "yes".**
4. **Publish:** `git -C <repo> commit -m "<message>" && git -C <repo> push`
5. **Report & log:** report the commit + push result + the repo URL, then append one `export` entry to
   `wiki/log.md` via shell (version, commit hash, what shipped). The publish event logs `export`; the
   framework edits it ships were already logged as `framework` when made — never log the push as a second
   `framework`. A failed or aborted push logs nothing. If `push` fails on auth, tell the user to set up a
   GitHub token / SSH key — never handle their credentials yourself.
6. **Clean up — keep no local copy:** once the push succeeds, delete the build directory
   (`rm -rf template-export`). A `--push` writes straight to the external repo clone, so nothing is left
   in the vault either way (`payload/` stays — it is the skill, not a build artifact).
7. **Private backup — gated closing step:** if the vault root is a git repo with a remote, back the
   vault up now: `git add -A && git commit -m "backup: YYYY-MM-DD (post <version> publish)" && git push`
   (owner identity, no AI attribution). Report the result in-reply; never ask for confirmation and
   never log it in `wiki/log.md`. If the vault has no git repo or remote, say so in one line and move
   on — the backup must never block a publish.

## Update (pull) — guided; preview → confirm → apply
When the user wants to bring a newer framework from the repo into their vault ("pull the latest framework",
"update my framework from git"):
   *(Logging: a confirmed `--pull --apply` changes this vault's framework — log it as `framework`, never `export`.)*
1. **Preview:** `bash .claude/skills/export-template/export_template.sh --pull <repo>`. Show the user the
   listed framework files that would change (README/CLAUDE/Manual/skills, plus the `payload/` refresh).
   **Nothing is written yet.**
2. **Confirm — mandatory gate:** ask the user to approve overwriting those vault framework files. Remind
   them their knowledge (`wiki/ raw/ output/` (and your own `assets/` media)) and `.obsidian` config (bar
   `graph.json` when they choose `--with-graph`) are left untouched.
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
  persistent sources are the vault-root docs (`README.md`, `LICENSE.md`, `assets/`) and this
  skill's `payload/` (setup.sh, git dotfiles, demo) — both kept fresh by `pull --apply`.
- **Never publishes unreviewed:** the publish flow always shows the diff and waits for your explicit OK
  before `commit`/`push`; your git credentials stay yours.
- **Read-only on the vault except `pull --apply`** (build/push write only under OUT / the repo clone).
- **No knowledge or personal data shipped** — `wiki/**`, `raw/**`, logs, `wiki/user/**` are never copied;
  `wiki/` + `raw/` ship empty (`.gitkeep`); the demo lives in `examples/seed/` only.
- **Git policy baked in**: the shipped `.gitignore` tracks the framework and ignores all content, so a
  user's notes never get committed (matches CLAUDE.md §11).
- `export-template` **ships too** and syncs like any other skill — users need only its `--pull`
  (updating their framework copy); `--push` is the maintainer's publish path. Framework development
  happens in the maintainer's vault, so no contributor path ships.

## After building — verify + publish
See RUNBOOK.md §B (verify: content git-ignored; framework tracked; no personal leak) and
§C (publish: GitHub New repo → `git init/add/commit/remote/push` → mark as a Template repository).

## Private vault backup (agent-maintained)
The vault's *own* git repo (private remote) is the owner's full backup — knowledge included, no review
gate. Two triggers, one command (`git add -A && git commit -m "backup: YYYY-MM-DD — <one-phrase what>"
&& git push`, owner identity):
- **After every successful public publish** — step 7 of the publish flow above.
- **On request** ("back up the vault", "push the private repo") — any time, including wiki-only days:
  the commit simply carries whatever changed.
Routine backups are never logged in `wiki/log.md` — the log records brain changes, not bookkeeping.
This repo is distinct from the public framework clone; never point one remote at the other
(CLAUDE.md §11). The Obsidian Git plugin remains an optional extra for continuous timed auto-backups;
the publish/pull git steps above stay shell-driven because the framework repo is a separate clone,
**not** this vault.
