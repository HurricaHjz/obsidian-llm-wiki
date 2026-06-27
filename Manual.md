# Manual: using your LLM second brain

> **What is this.** Your AI-built **second brain**: drop in your sources and the agent compiles them into a structured, self-maintaining knowledge base that answers questions, creates deliverables, and acts as a cited reference. 
>
> **What this manual covers.** How to use it day to day: the capture → compile → ask → maintain loop, the everyday commands (`/ingest`, `/query`, `/output`), and the advanced options. You rarely edit the wiki by hand; you work through the agent.

## What's in here

| Folder | What it holds |
|--------|---------------|
| `raw/` | **Your sources** (the inbox). Drop files, clips, or links here in almost any format: PDF, Word, PowerPoint, Excel, Markdown and plain text, CSV, HTML and web pages (articles, blogs, GitHub repos and gists), images (PNG/JPG), audio (MP3/WAV), EPUB, and YouTube links. Once processed, the agent files each into a numbered subfolder (`1-articles` … `9-originals`, `archives`, `duplicates`). |
| `wiki/` | **The compiled brain:** `concepts/ entities/ tools/ models/ benchmarks/ sources/ syntheses/ developments/ maps/ user/`, plus `index.md` (the catalogue) and `log.md` (history). |
| `wiki/user/` | **About you** — profile, research, works. The agent reads this for context; you curate it. |
| `output/` | **Deliverables** the agent writes on request — reports, briefs, decks. Kept separate from the brain. |
| `assets/` | Images and reference attachments — diagrams, screenshots, and *special* PDFs you want to link to. Source PDFs to **ingest** go in `raw/`, not here. |
| `CLAUDE.md` | The rule-book the agent follows (you don't normally touch it). |
| `.claude/skills/` | The commands: `ingest`, `gather`, `query`, `output`, `lint`, `deep-lint`, `export-okf` (plus `export-template` for contributors). |

Every note in `wiki/` also carries a **confidence level**, so you can see at a glance how far to trust it:

| Level           | What it means                                                                              |
| --------------- | ------------------------------------------------------------------------------------------ |
| `authoritative` | Peer-reviewed or published work, expert reviews, and verified sources — the highest trust. |
| `high`          | Faithful summaries, preprints, and official documentation, or your own work by default.    |
| `medium`        | Reputable secondary sources, or notes corroborated across several sources — the default.   |
| `low`           | A single promotional, social, or auto-transcribed source; treat with care.                 |
| `very-low`      | Speculative or unverified material, flagged for caution.                                   |

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
- After each ingest, the agent lists the new notes with their **confidence level**, so you can check the trust ratings and ask to re-grade any.

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

**`/deep-lint` — monthly deep maintenance**
- A heavier, roughly monthly pass that does everything `/lint` does and also audits every page's **confidence level**, flags stale claims, and re-checks your sources against their **live online versions**, updating the wiki where they have changed. Token-intensive by design, so run it about once a month rather than routinely.

**qmd — optional local semantic search (for large or fast-growing vaults)**
> Worth adding when your wiki is **already large enough that `index.md` is hard to scan**, *or* when you **expect it to grow very large** — in that case adopt it **early**: the index then builds up incrementally (one quick re-embed per note as you go) instead of as one slow bulk embed later, and you get search-by-meaning the whole way up.
- Once enabled, the agent **searches by meaning** (not just exact keywords) — but **only when it's actually needed**: when the normal `index.md` + keyword search comes up short for a question. It is **not** run on every search, and you don't have to ask for it — the agent decides when it genuinely helps (you *can* force it with `/qmd-search <query>`). Whenever qmd is off or absent, search silently falls back to the normal path.
- It stays **dormant and cost-free** until you install and enable it, runs **only as quick one-shot calls** (nothing is ever left running in the background), and the agent keeps its index fresh automatically as you add or change notes. Ask the agent to set it up when you're ready.

**`/export-okf` — export a portable copy**
- Turns the wiki into a portable **OKF** bundle in `okf-export/`, to share with other tools. Read-only on your vault.

**Back up your vault — Obsidian Git (optional)**
- The **Obsidian Git** plugin saves your *entire* vault — notes and all — to a **private** Git remote, giving you version history and sync across machines. Set it up once (a private repo + the plugin's backup command).
- This is **separate from sharing the framework**: Obsidian Git backs up *everything to a private repo*; the framework is published *stripped of your notes to a public repo*. Keep the two remotes distinct.

**`/export-template` — publish framework changes (contributors only)**
> ⚠️ **For developers/contributors only.** If you are not planning to contribute changes to the framework itself, **ignore this skill** — you never need it to capture sources or use your wiki.
- It packages the framework with **none** of your notes and syncs it with the public GitHub repo: `--push` publishes your framework changes, `--pull` updates your framework from upstream. It always previews and asks before writing anything, one direction at a time.
- A plain `git push` only syncs a single repository with its own remote. This skill instead carries framework changes between two separate repositories, your private vault and the public framework repo, and assembles the shareable demo. Your knowledge therefore stays in its own private, independently backed-up vault, while your framework improvements still reach the public repo.

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

| Colour         | Node type       | What it is                                     |
| -------------- | --------------- | ---------------------------------------------- |
| ⚪ White        | `index` · `log` | the registry hubs that anchor the graph        |
| 🟡 Gold        | Maps            | navigational hubs (Maps of Content)            |
| 🔵 Blue        | Concepts        | abstractions — methods, theories, principles   |
| 🟢 Green       | Entities        | people & organisations                         |
| 🟠 Orange      | Tools           | software, apps, plugins, skills, services      |
| 🟦 Oxford blue | User            | **about you** — profile, research, works       |
| 🔴 Red         | Models          | LLMs (Qwen, GPT, …)                            |
| 🟣 Purple      | Benchmarks      | evaluation datasets (AIME, GSM8K, …)           |
| ⚫ Grey         | Sources         | one summary per raw source (the bulk of nodes) |
| 🩷 Pink        | Syntheses       | answers filed back from your queries           |
| 🟤 Brown       | Developments    | this vault's own self-upgrade docs (design · plans · rollouts) |

New nodes colour themselves: each colour keys off the **type folder** (`wiki/models/`, …), so anything the agent files there is coloured automatically — no manual tagging.

---
*This manual is stable — it changes only when the system's setup changes, not on every ingest or query.*
