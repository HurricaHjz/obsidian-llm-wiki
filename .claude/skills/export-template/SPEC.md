# SPEC — target shape of the published template

What `export_template.sh` produces in `template-export/` (and what the public repo should look like).

## Final file tree (publishable repo)
```
obsidian-llm-wiki/                  (= template-export/)
├── README.md                  # onboarding: what it is · prerequisites · quick start → Manual
├── Manual.md                  # how to use it (beginner-first)
├── LICENSE.md                 # MIT — Mingjun (Jerry) Zhang, 2026
├── CONTRIBUTING.md
├── .gitignore                 # tracks the framework, ignores all knowledge/content
├── .gitattributes
├── setup.sh                   # first-run bootstrap (registries; --with-example; --reset)
├── CLAUDE.md                  # the agent's contract
├── .claude/skills/            # ingest · gather · query · output · lint · export-okf · export-template (ships with its payload/)
├── .obsidian/                 # graph.json, app.json, core-plugins.json, appearance.json ONLY
├── assets/                   # framework_demo.png (.gitkeep)  ← README screenshot (force-tracked); other media gitignored
├── output/                    # empty (.gitkeep)
├── raw/                       # 11 empty lanes (.gitkeep) — NO seed (content is gitignored)
│   └── 1-articles/ … 9-originals/ · archives/ · duplicates/
├── wiki/                      # 9 empty type folders (.gitkeep) — NO seed, NO index/log (gitignored)
│   └── concepts/ entities/ tools/ models/ benchmarks/ sources/ syntheses/ maps/ user/
└── examples/seed/             # the demo (TRACKED, separate from wiki/raw so .gitignore keeps it)
    ├── raw/2-papers/example-gpt4-and-mmlu.md
    └── wiki/{index.md, log.md, sources/, concepts/, entities/, models/, benchmarks/, maps/}
```

## Git tracking policy (the heart of this version)
- **Tracked (framework):** README, Manual, LICENSE.md, CONTRIBUTING, .gitignore, .gitattributes, setup.sh,
  CLAUDE.md, `.claude/skills/**`, `.obsidian/{graph,app,core-plugins,appearance}.json`, the `.gitkeep`
  skeleton, and `examples/`.
- **Ignored (local knowledge):** `wiki/**` (incl. `index.md`, `log.md`), `raw/**`, `assets/**` (bar the README screenshot),
  `output/**`, `okf-export/`, `template-export/`, plus `.obsidian/workspace*.json`/`plugins/`/`cache`.
- Net: a fresh clone ships **empty** (skeleton + demo only); when anyone uses it their content stays
  local, and `git push` shares only framework changes.

## KEEP / STRIP (copied from the live vault by the builder)
- **KEEP →** CLAUDE.md, Manual.md, `README.md`/`LICENSE.md`/`CONTRIBUTING.md` + `assets/` (from the vault root),
  `.claude/skills/**` — **every** skill, **incl. `export-template`** (the contributor publish tool, with its `payload/`),
  `.obsidian/{graph,app,core-plugins,appearance}.json`.
- **STRIP →** all `wiki/**`, `raw/**`, `assets/**` (bar the README screenshot), `output/**`, `okf-export/`, `wiki/user/**`, personal
  data, `.obsidian/workspace.json`/`plugins/`/`community-plugins.json`, `.claudian/`, `.git/`.

## Conventions the scaffold must preserve
- Every empty content dir keeps a `.gitkeep`.
- `raw/` lanes 1-articles…9-originals + archives + duplicates; `wiki/` type folders as above.
- The demo is the ONLY shipped content and lives in `examples/seed/` (never in `wiki/`/`raw/`).


## Push / pull round-trip (how repo and vault stay in sync)
The builder runs **one direction per invocation** (see SKILL.md):
- **push** (vault → repo): `copy_framework` (CLAUDE.md, Manual.md, skills, `.obsidian`, seed) +
  `copy_packaging` (`README.md`/`LICENSE.md`/`CONTRIBUTING.md` + `assets/` from the vault root; setup.sh + git
  dotfiles from `payload/`) + `make_skeleton` + `apply_fixes`.
- **pull** (repo → vault, with `--apply`): repo framework → vault (CLAUDE.md, Manual.md,
  `README.md`/`LICENSE.md`/`CONTRIBUTING.md`+`assets/`, all skills — copied **per-name**, incl.
  `export-template` itself (replacing the running script is Unix-safe)); repo setup.sh/git-dotfiles/seed → `payload/`.
- **Canonical sources:** `README.md`, `LICENSE.md`, `CONTRIBUTING.md` + `assets/` live at the **vault root**
  (visible, editable); the build machinery lives in `payload/`. Pull keeps both fresh so push never clobbers
  upstream edits.
- **Pull never writes** to `wiki/ raw/ output/` (and your own `assets/` media), never touches
  `.obsidian/{app,appearance,core-plugins}.json` (vault-specific), and pulls `.obsidian/graph.json` **only**
  with `--with-graph`.

## Graph exclusion
`.obsidian/app.json` `userIgnoreFilters` includes `examples/`, `template-export/`, `okf-export/`,
`output/`, `raw/`, `CLAUDE.md`, `Manual.md` so the demo + non-wiki files don't clutter the graph.

## The seed demo (purpose)
A 6-page AI/LLM-research mini-wiki (source → concept · entity · model · benchmark · map) so a first-time
cloner can `setup.sh --with-example`, see the colour-coded graph, run `/query`, and read a worked
`raw → wiki` compile. Deletable via `setup.sh --reset`. Safe general knowledge only.
