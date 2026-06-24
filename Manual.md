# Manual — using your LLM second brain

> **What this is.** A self-maintaining knowledge base. **You** capture sources — articles, papers, notes,
> links — and ask questions; **an AI agent** reads each source once, compiles it into linked, structured
> notes, and keeps everything cross-referenced. Rather than re-reading everything on every query, it
> **compiles knowledge once and reuses it**, so your notes *compound* instead of piling up.
> (Pattern: Andrej Karpathy's LLM Wiki.) You rarely edit the wiki by hand — you work through the agent.

## What's in here

| Folder | What it holds |
|--------|---------------|
| `raw/` | **Your sources.** Drop files, clips, or links into the root — that is the inbox. Once a source is processed, the agent files it into a numbered subfolder (`1-articles` … `9-originals`, `archives`, `duplicates`). |
| `wiki/` | **The compiled brain:** `concepts/ entities/ tools/ models/ benchmarks/ sources/ syntheses/ maps/ user/`, plus `index.md` (the catalogue) and `log.md` (history). |
| `wiki/user/` | **About you** — profile, research, works. The agent reads this for context; you curate it. |
| `output/` | **Deliverables** the agent writes on request — reports, briefs, decks. Kept separate from the brain. |
| `assets/` | Images, PDFs, and other attachments. |
| `CLAUDE.md` | The rule-book the agent follows (you don't normally touch it). |
| `.claude/skills/` | The commands: `ingest`, `gather`, `query`, `output`, `lint`, `export-okf`. |

## The loop

**Capture** (drop a file, clip, or URL into `raw/`) → **Compile** (`/ingest`) → **Ask** (`/query`) →
**Maintain** (`/lint`). Good answers get filed back, so the wiki compounds over time.

## Everyday commands

Type these to the agent, in the Claudian panel or Claude Code.

**`/ingest` — turn sources into wiki notes**
- `/ingest` — process everything new in `raw/`.
- `/ingest <file or https://…>` — a single file or web link; PDFs, documents, web pages, and YouTube are all handled.
- `ingest this in research mode` — a thorough, academic note for an important paper, with exact figures, verbatim quotes, methods, and limitations.
- Plain language works too: *"add this to my wiki."*

**`/query` — ask your knowledge base**
- `/query <question>` — for example, *"/query what do my notes say about calibration?"*
- Answers come **from your wiki**, with clickable `[[links]]` to the pages used, and can be filed back when worth keeping.

**`/output` — produce a polished deliverable**
- `/output <what you want>` — for example, *"/output a one-page brief on X for a non-expert."*
- Writes a grounded, **cited** document into `output/`; it cites what it draws on and does not invent facts.

## Rules of thumb

- **You curate and ask; the agent writes the wiki.** Change notes through the agent rather than by hand.
- Keep anything **about you** — bio, research, works — in `wiki/user/`, starting with `About Me`.
- `raw/` is your source of truth: the agent files and sorts your sources but never rewrites them.
- Keep Obsidian open, and explore through the **graph view** and **backlinks**.
- The agent runs on API credits, so it is worth being deliberate about very large jobs.

---

## Advanced

**Deeper `/ingest` options**
- `/ingest --verbatim <url>` — save the **exact** page rather than a cleaned version, for precise quoting.
- `/ingest --no-dedup` — skip the automatic "already ingested?" check when loading material you know is new.
- Capture is automatic by type: web pages via `defuddle`, Markdown and text via `curl`, audio/video/binary via MarkItDown, with **Jina Reader** as a fallback for awkward or JavaScript-heavy pages.

**`/gather` — deep-capture a whole topic**
- `/gather <url> [url2 …]` — fetches a starting page **and the relevant sources it cites** (papers, repos, docs) into `raw/`, then hands off to `/ingest`. It **previews what it will fetch and asks first**, and caps how much it pulls.
- Conservative by default (one hop, up to ten pages). Override with `--max-depth 2`, `--max-pages 50`, `--same-domain`, `--include a,b` / `--exclude c,d`, `--yes` (skip the preview), or `--ingest` (compile afterwards) — or simply describe it: *"gather these, two hops, only the papers."*

**`/lint` — health-check the wiki**
- Finds broken links, orphans, unindexed pages, and conflicts. A normal `/ingest` self-cleans, so run this after hand-editing, after syncing between machines, or for a periodic review.

**`/export-okf` — export a portable copy**
- Turns the wiki into a portable **OKF** bundle in `okf-export/`, to share with other tools. Read-only on your vault.

**Back up your vault — Obsidian Git (optional)**
- The **Obsidian Git** plugin saves your *entire* vault — notes and all — to a **private** Git remote, giving you version history and sync across machines. Set it up once (a private repo + the plugin's backup command).
- This is **separate from sharing the framework**: Obsidian Git backs up *everything to a private repo*; the framework is published *stripped of your notes to a public repo*. Keep the two remotes distinct.

**Modes and pacing**
- **Modes** (depth): `standard` (default) · `concise` (thin sources, automatic) · `research` (papers — say "research mode", or the agent asks first). All stay token-efficient.
- **Pacing** (how many at once): `auto` (default) · one at a time · in batches.

**More `/query` examples**
- `Compare [[A]] and [[B]] and save a table to syntheses.`
- `Where are the gaps in what I know about <X>? What should I read next?`
- `Turn [[topic]] into a Marp slide deck.`
- `Do a research-mode synthesis of <X> with exact ƒfigures and citations.`

---

## Graph view (colours)

The graph is **colour-coded by node type**, so the shape of your knowledge reads at a glance. Reopen the
graph view after any setup change to load new colours.

| Colour | Node type | What it is |
|--------|-----------|------------|
| ⚪ White | `index` · `log` | the registry hubs that anchor the graph |
| 🟡 Gold | Maps | navigational hubs (Maps of Content) |
| 🔵 Blue | Concepts | abstractions — methods, theories, principles |
| 🟢 Green | Entities | people & organisations |
| 🟠 Orange | Tools | software, apps, plugins, skills, services |
| 🟦 Oxford blue | User | **about you** — profile, research, works |
| 🔴 Red | Models | LLMs (Qwen, GPT, …) |
| 🟣 Purple | Benchmarks | evaluation datasets (AIME, GSM8K, …) |
| ⚫ Grey | Sources | one summary per raw source (the bulk of nodes) |
| 🩷 Pink | Syntheses | answers filed back from your queries |

New nodes colour themselves: each colour keys off the **type folder** (`wiki/models/`, …), so anything the agent files there is coloured automatically — no manual tagging.

---
*This manual is stable — it changes only when the system's setup changes, not on every ingest or query.*
