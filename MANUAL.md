# Manual: using your LLM second brain

> **What is this.** Your AI-built **second brain**: drop in your sources and the agent compiles them into a structured, self-maintaining knowledge base that answers questions, creates deliverables, and acts as a cited reference. 
>
> **What this manual covers.** How to use it day to day: the capture → compile → ask → maintain loop, the everyday commands (`/ingest`, `/query`, `/output`), and the advanced options. You rarely edit the wiki by hand; you work through the agent.

## What's in here

| Folder | What it holds |
|--------|---------------|
| `raw/` | **Your sources** (the inbox). Drop files, clips, or links here in almost any format: PDF, Word, PowerPoint, Excel, Markdown and plain text, CSV, HTML and web pages (articles, blogs, GitHub repos and gists), images (PNG/JPG), audio (MP3/WAV), EPUB, and YouTube links. Once processed, the agent files each into a numbered subfolder (`1-articles` … `9-originals`, `archives`, `duplicates`). |
| `wiki/` | **The compiled brain:** `concepts/ entities/ tools/ models/ benchmarks/ sources/ syntheses/ developments/ maps/ user/`, plus `index.md` (the catalogue) and `log.md` (history). |
| `wiki/user/` | **About you** — profile, research, works. The agent reads this for personal context; you curate it. |
| `output/` | **Deliverables** the agent writes on request — reports, briefs, decks. Kept separate from the brain. The root holds one-off pieces; subfolders (`user-notes/`, `fundings/`) hold standing documents the agent keeps up to date as the underlying knowledge changes. |
| `assets/` | Images and reference attachments — diagrams, screenshots, and *special* PDFs you want to link to. Source PDFs to **ingest** go in `raw/`, not here. |
| `IDEAS.md` | **Your scratchpad** — a copy-ready **TODO prompt queue** plus ideas and a monitor lane of standing cautions, jotted freely. The agent ignores it unless you explicitly point it there: *"maintain IDEAS.md"* tidies and reconciles it, *"run TODO 2"* executes a queued prompt and updates its status. |
| `attic/` | **Your cold storage** — retired files kept "just in case", each listed in `attic/MANIFEST.md`. The agent never opens it unless you explicitly ask; archived notes show **grey** in the graph. |
| `CUSTOMISATION.md` | **How your agent behaves** (vault root, seeded on first setup) — its name, output styles, task roles, and any standing preferences you add. Edit it, or just ask the agent. |
| `CLAUDE.md` | The rule-book the agent follows (you don't normally touch it). |
| `.claude/skills/` | The commands: `ingest`, `gather`, `query`, `output`, `reflect`, `lint`, `deep-lint`, `attic`, and `qmd-search` (plus `export-template` for framework updates). |

Every note in `wiki/` (except the navigational maps) also carries a **confidence level**, so you can see at a glance how far to trust it:

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
- `/ingest <file or https://…>` — a single file or web link; PDFs, documents, web pages, and YouTube are all handled. A platform link the capture chain cannot reach (an X post, a Reddit thread, a XiaoHongShu note) is reported with a ready, owner-gated option rather than improvised or silently skipped.
- `ingest this at research depth` — pin the thorough, academic treatment for an important paper: exact figures, verbatim quotes, methods, and limitations. Left unpinned, the agent decides per source after reading and shows you what it chose.
- Plain language works too: *"add this to my wiki."*
- After each ingest, the agent lists the new notes with their **confidence level**, so you can check the trust ratings and ask to re-grade any.

**`/query` — ask your knowledge base**
- `/query <question>` — for example, *"/query what do my notes say about calibration?"*
- Answers come **from your wiki**, with clickable `[[links]]` to the pages used, and can be filed back when worth keeping.

**`/reflect` — keep what a session taught you**
- `/reflect` — at the end of a working session, the agent sweeps the conversation for research insight, method lessons and any faults it found, then shows you a table of what it proposes to record and where. Nothing is written until you approve it. A critic subagent tries to knock down each proposal before you see it (`--no-critic` skips), and the report names how much of the session's record it could still see.
- It only ever runs when you ask. The agent already files findings as it works, and that carries on unchanged; this is your own trigger for the times it didn't.
- It tells you how far back it can still see, since a long session may have dropped its earliest turns, and it never claims to have swept the whole thing.
- Add `--yes` to let it write without waiting. It still shows you everything it wrote, and it may only add new pages or append to existing ones inside `wiki/` — never your own pages in `wiki/user/`, and never the rule-book.

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
- `/ingest --agent-convert <file>` — the agent itself transcribes a PDF or image to Markdown instead of the automatic converter, for precision on complex layouts (heavier on tokens, so opt-in). If an automatic conversion comes back empty or garbled, the agent offers this route with a cost estimate before anything else.
- `/ingest --depth concise,standard` — narrow the depths the agent may choose from for this run. It may use all three unless you narrow or pin.
- Capture is automatic by type: web pages via `defuddle`, Markdown and text via `curl`, audio/video/binary via MarkItDown, with **Jina Reader** as a fallback for awkward or JavaScript-heavy pages.

**`/gather` — capture from the web: links, or a whole topic**
- `/gather <url> [url2 …]` — fetches the page(s) **and the relevant sources they cite** (papers, repos, docs) into `raw/`, then hands off to `/ingest`. It **previews what it will fetch and asks first**, and caps how much it pulls. On documentation sites it also checks the site's sitemap, so the preview shows the host's whole inventory rather than just the pages the seed happens to link.
- `/gather --search "<topic>"` — no links needed: the agent web-searches the topic, triages the hits, and shows you a **dated shortlist to approve** before anything is fetched. If the topic is too vague to plan from, it asks up to three sharp questions first; each approval screen also shows which sub-questions of your topic are covered and which are still open. Add `--rounds 2` to let it search again for whatever the first haul left uncovered — later rounds never re-run earlier queries or re-present rows you already passed over as new. This is the vault's own deep-research route — after `/ingest`, ask `/query` or `/output` for the cited report. When a topic needs Chinese or community coverage, search mode can also query the enabled platform channels (Bilibili, V2EX) alongside web search, declared at the approval screen.
- With a bigger budget (say `--max-pages 40`) the menu stays small but every further ranked candidate is listed one per line, and you capture by **rule** — *"top 30 by relevance"*, with row-level tweaks if you like. A bare "approve" always means just the menu, and the search funnel (queries, pool, date checks) scales with the budget and is printed at the gate.
- Conservative by default (search mode captures just the approved results; link mode follows one citation hop; up to ten pages). Override with `--expand 2` (citation hops), `--focus "X"` (only material relevant to X), `--max-pages 50`, `--shortlist 10` (detailed rows at the gate), `--queries 8` (searches per round), `--same-domain`, `--include a,b` / `--exclude c,d`, `--yes` (skip the preview), or `--ingest` (compile afterwards) — or simply describe it: *"gather these, two hops, only the papers."*
- Runs keep themselves honest (v3.1): every capture goes through one script that enforces the caps, raw immutability and provenance; a per-run ledger tracks captures and your drops across rounds on bigger runs; and the gate adds the agent's advice ("~N worth capturing") — rows beyond your budget are marked, and capturing them just means raising the cap ("raise to 15, take top 15").
- The agent may also **suggest** a gather when a `/query` or `/output` run hits a real knowledge gap: a short brief (why · what · the exact command · cost) after its answer. It only ever runs on your explicit yes — say nothing and it reminds you once, then drops it; say no and it stays dropped for the session.

**`/lint` — health-check the wiki**
- Finds broken links, orphans, unindexed pages, and conflicts, and checks that no third-party installer has slipped an unsanctioned skill into the agent's skill folders. A normal `/ingest` self-cleans, so run this after hand-editing, after syncing between machines, or for a periodic review.

**`/deep-lint` — periodic deep maintenance**
- A heavier pass (roughly monthly, or when flags pile up) that does everything `/lint` does and also reconciles the staleness flags queries leave behind, audits **confidence** on changed and sampled pages rather than re-reading the whole vault, re-checks a capped, priority-ordered set of sources against their **live online versions**, reports whether the external capture tools (converters, yt-dlp and friends) have newer versions — report-only, upgrades stay your call — and reviews the IDEAS Monitor lane, updating the wiki where things changed. Token-bounded by design, and every cap it applies is stated in its report.

**The attic — retire files without deleting them**
- Say *"archive [[X]] to the attic"* (or `/attic archive X`) and the agent runs the full routine: it first folds anything still useful from the file into your live notes, shows you the list for approval, then moves the file into `attic/`, records what, where from and why in `attic/MANIFEST.md`, unindexes it, tidies every link, and verifies nothing still points in; *"restore X from the attic"* (`/attic restore X`) reverses it; *"what's in my attic?"* reads the manifest back to you.
- Archived notes stay in the graph in **grey**, so retired material remains visible without cluttering your live knowledge. The agent never opens the attic on its own — only when you ask. The monthly `/deep-lint` may *suggest* archive candidates (stale or superseded notes) as ready-to-run `/attic` commands but never moves anything itself, and the routine `/lint` guards the boundary by flagging any live note that still links into the attic.

**qmd — optional local semantic search (for large or fast-growing vaults)**
> Worth adding when your wiki is **already large enough that `index.md` is hard to scan**, *or* when you **expect it to grow very large**. In that case adopt it **early**: the index then builds up incrementally (one quick re-embed per note as you go) instead of as one slow bulk embed later, and you get search-by-meaning the whole way up.
- Once enabled, the agent **searches by meaning** (not just exact keywords) — but **only when it's actually needed**: when the normal `index.md` + keyword search comes up short for a question. It is **not** run on every search, and you don't have to ask for it — the agent decides when it genuinely helps (you *can* force it with `/qmd-search <query>`). Whenever qmd is off or absent, search silently falls back to the normal path.
- It stays **dormant and cost-free** until you install and enable it, runs **only as quick one-shot calls** (nothing is ever left running in the background), and the agent keeps its index fresh automatically as you add or change notes. Ask the agent to set it up when you're ready.

**Back up your vault — private repo**
- Your *entire* vault — notes and all — can back up to a **private** Git remote, giving you version history and sync across machines. Ask the agent to set it up once; after that it backs up automatically after every framework publish, and any time you say "back up my vault".
- This is **separate from sharing the framework**: the backup keeps *everything in a private repo*; the framework is published *stripped of your notes to a public repo*. Keep the two remotes distinct.
- The **Obsidian Git** plugin is an optional extra if you want continuous, timed auto-backups without asking the agent.

**`/export-template` — sync the framework with its repo**
> Most users need this only to **update**: `--pull` brings a newer framework version into your vault. `--push` publishes framework changes and is the maintainer's path. You never need either to capture sources or use your wiki.
- It packages the framework with **none** of your notes and syncs it with the public GitHub repo, one direction at a time. It always previews and asks before writing anything.
- A plain `git push` only syncs a single repository with its own remote. This skill instead carries framework changes between two separate repositories, your private vault and the public framework repo, and assembles the shareable demo. Your knowledge therefore stays in its own private, independently backed-up vault, while the framework itself stays shareable through the public repo.

**Modes and pacing**
- **Depth**: `concise` · `standard` · `research`. When ingesting, the agent picks a depth for each source **after reading it** and tells you which it chose and why, in the same report that lists confidence — so you can re-grade either with one word. Narrow what it may use with `/ingest --depth concise,standard`, or pin one for the whole run with `--research`, `--standard` or `--concise`. Asking a question is different: there `research` is opt-in or the agent asks first. All modes stay token-efficient.
- **Pacing** (how many at once): `auto` (default) · one at a time · in batches.

**Customisation — make the agent yours**
- Your agent's **name**, default **output style**, and **interaction preferences** live in `CUSTOMISATION.md`, seeded on first setup. Edit it — or just ask the agent — to change how it addresses you and how it writes.
- Those are only starter examples: the file is **open-ended**. Add any standing preference you want every session to honour — citation habits, formatting rules, tutoring style, anything — as new bullets or sections.
- **Deliverable defaults** (optional): a `## Deliverable defaults` section sets standing formats for `/output` documents — citation style, deck format, and so on. Leave it empty and the agent chooses per deliverable; whatever you write in the instruction always wins.
- **Roles**: say *"act as tutor"* (or any role you define under `## Roles`) to switch the agent's task context for the conversation; every reply opens with the active `role · style` status line, a claim the reply has to satisfy rather than a decoration. Roles shape how the agent works on your task and add to your global preferences; they never change your output style — how much you read stays your choice alone.
- **Output styles** shape conversation only, one ladder from most to least: `detailed` (everything the prompt makes relevant) · `balanced` (the default — the natural answer) · `brief` (a few fluent paragraphs, still a full answer) · `summary` (the minimum that fully answers). Say *"switch to brief"* for one session, or *"make summary my default"* to keep it. You can add your own styles too. A scoped wish such as *"more concise for the next 3 replies"* shows as `customised` in the status line while it lasts, then the style reverts on its own.
- Choosing a style **never** changes the wiki itself — your notes, their confidence ratings, and the agent's status reports stay exactly the same.

**More `/query` examples**
- `Compare [[A]] and [[B]] and save a table to syntheses.`
- `Where are the gaps in what I know about <X>? What should I read next?`
- `Turn [[topic]] into a Marp slide deck.`
- `Do a research-mode synthesis of <X> with exact ƒfigures and citations.`

---

## Graph view (colours)

The graph is **colour-coded by node type**, so the shape of your knowledge reads at a glance. Reopen the graph view after any setup change to load new colours. **A fresh vault's graph is empty** until you `/ingest` your first source (or load the demo with `bash setup.sh --with-example`). The colours appear as soon as there are notes to colour, and `setup.sh` or your first ingest applies the palette automatically. If the colours ever disappear later (Obsidian can rewrite its graph config), just ask the agent to restore your graph colours.

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
| ⚫ Charcoal     | Sources         | one summary per raw source (the bulk of nodes) |
| 🩷 Pink        | Syntheses       | knowledge the agent wrote itself, from a query, a reflect run, or its own reading |
| 🟤 Brown       | Developments    | this vault's own self-upgrade docs (design · plans · rollouts) |
| 🩶 Grey        | Attic           | retired files kept "just in case" (cold storage) |

New nodes colour themselves: each colour keys off the **type folder** (`wiki/models/`, …), so anything the agent files there is coloured automatically, with no manual tagging.

---
*This manual is stable. It changes only when the system's setup changes, not on every ingest or query.*
