---
name: ingest
description: >
  Compile inbox files in raw/ into the wiki (source + entity/concept/model/benchmark pages), update
  index + log, then sort the raw file into its category subfolder. Use on /ingest, when files are
  dropped into raw/, or "add this to my wiki / ingest this / file this source / process my inbox".
  Non-.md sources (PDF, PPTX, DOCX, XLSX, image, audio, HTML, CSV, EPUB, YouTube/web URL) are
  converted to Markdown first; runs a cheap de-dup check; supports standard/concise/research modes
  (research is opt-in or ask-first). Scans the raw/ ROOT only (or one given path); never edits raw
  file contents — only relocates them.
user-invocable: true
---

# ingest — compile raw sources into the wiki

You maintain a **persistent, compounding wiki** (see `CLAUDE.md`). `raw/` root is the **inbox**;
`wiki/` is the **compiled layer**. Work in **British/UK English**.

## Trigger logic
1. **`/ingest`** (no arg) → list every file in the **`raw/` root only** (exclude all subfolders;
   they are already processed), then process them at the pacing chosen in **Pacing** below.
2. **`/ingest <path>`** → process just that file (or a YouTube/web URL the user gives you).
3. **Implicit** → user says "add this to my wiki" / "ingest this" / "file this source".

## Pacing: auto (default), one-by-one, or batch
Read the mode from the user's words; **if they don't specify, default to `auto` and decide yourself.**
Do not ask which mode to use unless the choice is genuinely risky.

- **`auto` (DEFAULT)** — pick the cheapest path that preserves quality:
  - **Batch** in a single pass when the inbox is small (≲5 files), the sources overlap the existing
    wiki, or conflict risk is low.
  - **One-by-one** when there are many diverse/unfamiliar sources, conflict risk is high, or the
    source is long and dense.
  - Either way, **pause immediately** if a genuine knowledge conflict surfaces.
- **`one-by-one`** — user says "one at a time" / "let me review each", or names a single file.
- **`batch`** — user says "all at once" / "batch them" / "do them all".

### Token-efficiency rules (especially in batch — avoid redundant repetition)
- Read each source **once**; never re-read the whole wiki per file.
- Collect entities/concepts across **all** batched sources first, **dedupe**, then create/update each
  shared page **once** — not once per source.
- Update `index.md` and `log.md` **once** at the end of the batch (a single batch `log` entry is fine).
- Skip irrelevant/off-topic source material instead of compiling noise. Don't re-read pages you just wrote.

## Modes: depth & style (auto standard/concise; research is opt-in)
Modes set how deep/academic the output is (orthogonal to Pacing). **All modes are equally rigorous
and token-efficient — `research` only permits more depth where the material justifies it; never padding.**

- **standard (DEFAULT)** — articles, blogs, posts, docs. Run Steps 2–4 as written.
- **concise** — auto-pick for short/low-density sources (brief tweet, link dump, thin page): 1–3-sentence
  summary, create pages only for genuinely new entities/concepts, minimal bullets.
- **research** — important papers / primary publications, for accurate reuse in the user's own future
  work. **Opt-in only**: trigger via `/ingest --research <path>`, "research mode", or "this is an
  important paper". If you judge a source is a serious paper that warrants it, **ASK first**
  ("This looks like a key paper — process in research mode? It's deeper and longer.") and never enter
  it silently. In research mode:
  - Preserve exact figures (no rounding); quote critical claims verbatim with §/page refs; mark
    anything not directly stated as `unverified`; never infer numbers.
  - Replace the Step 3 source page with the **literature-note template** below.
  - Add academic frontmatter (`authors`, `year`, `venue`, `doi`, `mode: research`).
  - Cross-check findings against existing pages and flag confirmations/contradictions explicitly.

Overrides: `--research` / `--concise` / `--standard` force a mode; otherwise auto (standard, dropping to concise).

### Research-mode source page (replaces the Step 3 template)
```markdown
---
title: "Paper: <Title>"
type: source
mode: research
confidence: high   # authoritative if peer-reviewed/published; see CLAUDE.md §4.6
tags: [paper, <field>]
authors: [<First Author>, <…>]
year: <YYYY>
venue: "<journal / conference>"
doi: "<DOI or stable URL>"
sources: [raw/2-papers/<file>.pdf, raw/2-papers/<file>.md]   # original + converted
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

## Citation
<full reference string>

## Research Question
## Methodology
## Key Findings
- <finding with exact figures, e.g. "+12.3 BLEU, p<0.01">
## Data / Setup
## Contributions
## Limitations & Threats to Validity
## Relation to Wiki
- Confirms [[…]]; contradicts [[…]] → flag a `## Conflicts / Open Questions` block on that page
## Key Quotes
> "<verbatim>" (§/p.)
## Open Questions / Follow-ups
## Related
- [[…]]
```

## Pipeline (per source)

### Pre-flight — De-dup: have I ingested this already? (one cheap shell call)
Step 6 (move-to-subfolder) is the **primary** guard: a root file is unprocessed by construction and
archived files are never re-scanned. The pre-flight only catches a doc that was **re-added**
(re-clipped, copied, or renamed). **Keep it minimal-token**: run it as ONE combined command that prints
*only* a match — so it costs ~nothing when there's no duplicate, and **its output does not grow with
wiki size** (grep for *this* file's hash, never dump all hashes; never read page contents):

```bash
f="<filename>"; u="<source: URL, or empty>"
{ find raw -mindepth 2 -name "$f" 2>/dev/null
  h=$(shasum -a 256 "raw/$f" 2>/dev/null | cut -c1-16); [ -n "$h" ] && grep -rl "$h" wiki/sources/ 2>/dev/null
  [ -n "$u" ] && grep -rl "$u" wiki/sources/ raw/*/ 2>/dev/null
} | sort -u      # empty = NEW → proceed;  any path printed = possible duplicate
```

**On a match, decide (don't blindly skip):**
- **Process it as an UPDATE** when there's something new to extract — the user gave extra instructions,
  a deeper **mode** is requested (e.g. `--research`), it's a newer/extended version, or it plausibly
  carries **new content** (e.g. an **OpenReview / peer-review page** with reviews, rebuttals, scores,
  decisions). Read it and **merge new findings into the EXISTING wiki pages** (don't create a redundant
  second source page). A genuinely different artifact — notably a **review** — gets its own page and is
  filed to `raw/7-reviews/` (Step 6).
- **Quarantine** to `raw/duplicates/` when it's **not useful** (truly redundant) OR the user says
  **"ignore duplicates"**. Move the file there — never leave dups in the inbox or delete them.
- No match (genuinely new) → proceed to Step 0. Record `source_url`/`source_hash` (Step 3) for next time.

> The shell check only catches *exact/near-exact* dups (name · byte-hash · URL). A **content duplicate
> in a different file** (same paper, different PDF/version; an OpenReview page) won't match — spot it
> while reading, then apply the same decision (update vs `duplicates`).

- **Cost**: one shell call, near-empty output → a few hundred tokens at most (<~1–3% of an ingest).
- **Opt-out**: `--no-dedup` (or "skip dedup") skips this pre-flight for bulk all-new loads. On by default (cheap).

### Step 0 — Normalize to Markdown (MarkItDown) — non-`.md` sources ONLY
**If the source is already `.md`, SKIP this entire step — do NOT invoke MarkItDown.** Conversion is
only for binary / non-Markdown inputs; running it on a `.md` file wastes tokens and adds nothing.

Otherwise (`.pdf`, `.pptx`, `.docx`, `.xlsx`, `.png`/`.jpg`, `.mp3`/`.wav`, `.html`, `.csv`, `.epub`,
… or a YouTube/web URL):

1. **Preflight the engine** (install once if missing — the console script is NOT on PATH here, so
   check *importability*, not `command -v`):
   `python3 -c "import markitdown" 2>/dev/null || pip3 install 'markitdown[all]'`
2. **Convert** (always use the module form — `python3 -m markitdown` — since the bare `markitdown`
   script isn't on PATH):
   - **Local file** → `python3 -m markitdown "<absolute path>" -o "raw/<stem>.md"`
   - **URL — capture the *original*, never a summary.** Route by type:
     - **Raw `.md` / text / code URL** (`raw.githubusercontent.com`, gist raw, `.txt`) → `curl -sL "<url>"` and save the bytes **verbatim**. **Do NOT use WebFetch** — it returns a model *summary*, not the source.
     - **Web page (article / repo / docs)** → `defuddle` (extracts the real main content as clean Markdown, not a summary). Use WebFetch *only* for a throwaway lookup where exact text is irrelevant — never for ingest.
     - **GitHub repo** → `curl -sL` the raw README/files (`raw.githubusercontent.com/<owner>/<repo>/<branch>/README.md`), or `gh api` / `gh repo view` if authenticated.
     - **YouTube / binary URL** → MarkItDown's Python API (its CLI only accepts file paths):
       `python3 -c "from markitdown import MarkItDown; open('raw/<stem>.md','w').write(MarkItDown().convert('<url>').text_content)"`
     - **Fallback — a web page none of the above can capture** (JS-heavy / anti-bot / empty or garbled result) → `curl -sL "https://r.jina.ai/<url>"` (Jina Reader renders server-side → clean Markdown). **Last resort only**; it routes the URL through a third party, so skip it for sensitive or login-walled pages.
     - **Opt-in `--verbatim` (byte-exact original).** When the user wants the *unaltered* source (research-grade provenance / exact quoting), `curl -sL "<url>" > raw/<stem>.md` (or `gh`) and keep the bytes **unmodified** — skip the step-3 defang/clean (raw/ is graph-excluded anyway). For an HTML page, `curl` it then `python3 -m markitdown` to convert deterministically (full content, no summary). Heavier on tokens → opt-in, not the default.
   - *(If a `markitdown-mcp` server is ever configured, the `markitdown` skill's `convert_to_markdown(uri)`
     tool becomes an equivalent alternative.)*
3. **Save** the Markdown into `raw/` as `<original-stem>.md` (use `<original-stem>.converted.md` if
   that name is taken). **This is the only time you may add a file to `raw/`.** Prepend provenance:
   ```yaml
   ---
   converted_from: <original filename or source URL>
   converted_by: markitdown
   converted_on: <YYYY-MM-DD>
   ---
   ```
   Then **sanitize the saved body** so it can never pollute the Obsidian graph (MarkItDown emits stray
   `[text](bareword)` links from math/citations, and sometimes control/binary bytes):
   ```bash
   perl -i -pe 's/[\x00-\x08\x0b\x0c\x0e-\x1f]//g; s{\[([^\]\n]*)\]\(([^)\n]*)\)}{ $2 =~ m{://|^#|mailto} ? "[$1]($2)" : "$1 ($2)" }ge; s/\[\[/[ [/g; s/\]\]/] ]/g' "raw/<stem>.md"
   ```
   (Strips control bytes; defangs `[a,b](z)`→`a,b (z)` and `[[x]]`→`[ [x] ]`; keeps real `https://` links. `raw/` is also graph-excluded — see CLAUDE.md §12.)
4. **Keep the original untouched.** The original and the converted `.md` are now a **pair**. For a
   URL source there is no local original — the converted `.md` is the only file; keep the URL in
   `converted_from`.
5. **Fallback if conversion is empty/garbled** (e.g. scanned, image-only PDF): read the original
   pages as images, or ask the user to OCR first. Never fabricate content.

> From here on, "the source" means the **converted `.md`** (for converted sources) or the original
> `.md` (for native-Markdown sources).

### Step 1 — Read the source
- Read the source Markdown in full.
- If it references images worth keeping, download them into `assets/` and read them separately
  (LLMs can't read inline-image Markdown in one pass).
- If the clip is mainly a **pointer to a richer primary source** (a docs page, repo, or article URL),
  **follow that link** and fetch the real source with the right tool (`defuddle`/WebFetch for a page,
  WebFetch for a `.md` URL, MarkItDown for a YouTube/binary URL) — compile from the source, not the stub.

### Step 2 — Extract & (if needed) translate
Pull out: **core thesis** (1–2 sentences), **entities** (people/companies), **tools** (software/apps/plugins/skills/services),
**concepts** (frameworks/methods/theories). Translate non-English content into British/UK English.

### Step 3 — Create the source summary → `wiki/sources/<slug>.md` (kebab-case)
```markdown
---
title: "Source: <Human Title>"
type: source
confidence: medium   # per CLAUDE.md §4.6 — reflects the source: peer-reviewed/expert→authoritative · preprint/official-doc/owner-work(default)→high · secondary→medium · promo/social/transcript→low (a user instruction can override the tier)
tags: [topic]
sources: [raw/2-papers/report.md, raw/2-papers/report.pdf]   # converted .md AND original; one entry if native .md or URL
source_url: "<original web URL if a clip — else omit>"        # de-dup
source_hash: "<sha256 prefix of the raw file>"                # de-dup
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

## Summary
[3–5 sentence core summary.]

## Key Takeaways
- ...

## Related
- [[EntityName]] — why related
- [[Concept Name]] — why related
```
**Dual provenance:** for a converted source, `sources:` must list **both** the converted `.md` and
the original (file path, or the URL for web/YouTube). Predict the post-sort paths (Step 6) so the
links don't break after the move.

### Step 4 — Network the knowledge (entities · tools · concepts · models · benchmarks)
For each entity → `wiki/entities/`, **tool** (software/app/plugin/skill/library/service) →
`wiki/tools/`, concept → `wiki/concepts/`, **model** (any LLM named — e.g. Qwen,
GPT, Llama) → `wiki/models/`, **benchmark** (any eval dataset named — e.g. AIME, GSM8K, GPQA) →
`wiki/benchmarks/` (Title Case filenames; a tool keeps its canonical lowercase where applicable):
1. **Page missing** → create it per the `CLAUDE.md` frontmatter + required sections (`## Definition /
   ## Key Points / ## Related`; model & benchmark pages also carry `## Appears in`); set its
   `confidence` per §4.6 (compiled pages **cap at `high`** — judge by corroboration across their sources).
2. **Page exists** → read it, then **incrementally merge** new info (don't clobber).
3. **Conflict found** → **pause**, report the conflict to the user, ask how to handle it
   (keep both under `## Conflicts / Open Questions`, overwrite, or skip), then continue.

**Models & benchmarks link bidirectionally** (CLAUDE.md §4.5): add this paper under the model/benchmark
page's `## Appears in`, and list the models/benchmarks the paper uses in the source page's `## Related`
(Obsidian backlinks then close the loop automatically). **Reuse** an existing model/benchmark page —
never duplicate one (fold `GPT-4`/`GPT-4o` into [[GPT]], `MATH500` into [[MATH]], `Qwen2.5` into [[Qwen]]).

A single source typically touches **10–15 wiki pages** via cross-links. No orphans — every page
gets a `## Related` section.

### Step 5 — Update the registries
- **First-run bootstrap**: if `wiki/index.md` or `wiki/log.md` is missing (a fresh clone), create it first
  — an empty `index.md` with the standard `## Sources / Entities / Tools / Models / Benchmarks / Concepts
  / Syntheses / Developments / Maps / User` headers, and a `log.md` seeded with one `setup` entry. On this
  same fresh-vault branch, **once**, ensure the graph colour palette: run
  `python3 .claude/skills/lint/apply-palette.py --apply` (idempotent — a no-op if the shipped palette is
  intact; restores it if a fresh clone had `colorGroups` wiped by Obsidian). If it prints `APPLIED…`, tell
  the user to reload Obsidian with the graph view closed. This runs **only** here (registries missing),
  never on a normal ingest. Then proceed.
- **`wiki/index.md`** → add each new page under Sources / Entities / Concepts with a one-line desc.
- **`wiki/log.md`** → append **via shell** (`cat >> wiki/log.md …`; never Read the whole file — it grows unbounded):
  ```markdown
  ## [YYYY-MM-DD] ingest | <short title>
  - **Changed**: created [[..]], [[..]]; updated [[index.md]]
  - **Converted**: <original> → <stem>.md via markitdown   (omit if source was native .md)
  - **Confidence**: <level(s) assigned, e.g. high>   (note any override of the §4.6 default)
  - **Conflicts**: none (or: conflict [[Page]], flagged/paused)
  ```

### Step 6 — Sort the raw source (this vault's archive design)
Only after Steps 3–5 are confirmed done, **move** the source out of the `raw/` root into the
matching category subfolder (use `obsidian-cli` or a shell `mv`; **never edit file contents**, though you MAY
rename an unwieldy auto-generated clip filename to a clean kebab-case slug as part of the move):

| Signal | → destination |
|--------|---------------|
| arxiv / PDF / formal paper / report | `raw/2-papers/` |
| tweet / X status / LinkedIn / Reddit / thread | `raw/6-social/` |
| Substack / personal blog / newsletter | `raw/5-blogs/` |
| docs / reference / GitHub repo / gist / tool manual | `raw/4-webinfo/` |
| news / magazine / long-form web article | `raw/1-articles/` |
| meeting / personal notes | `raw/3-notes/` |
| video / podcast / audio / lecture transcript | `raw/8-transcripts/` |
| peer review / OpenReview page / rebuttal / meta-review | `raw/7-reviews/` |
| owner-authored original work (research outline / draft / paper / thesis) | `raw/9-originals/` |
| none of the above / deprecated | `raw/archives/` |
| confirmed duplicate (ignored / not useful) | `raw/duplicates/` |

**If the source was converted in Step 0, move the original AND its converted `.md` together** into
the same subfolder, so they stay paired and the `sources:` links remain valid. After moving, the
`raw/` root should contain only still-unprocessed files.

### Step 7 — Self-check (leave the wiki lint-clean)
Before reporting done, verify your own output so a later `/lint` would find nothing to fix:
1. Every page you created/updated is registered in `index.md`.
2. Every `[[wikilink]]` you wrote resolves to a real page — or you created that page.
3. Every page you created has a `## Related` section and ≥1 inbound link from another page (no orphans).
4. Each `sources:` path points to the file's **post-sort** location.
5. Every page you created carries a valid `confidence` (except `map`), assigned per §4.6.

Fix any gap immediately. Scope this to the pages you touched — don't re-scan the whole wiki (efficiency).

> **A correct ingest is self-linting** — no follow-up `/lint` is needed. `/lint` exists for *drift*
> (manual edits, external/sync changes) and periodic *discovery* (gap pages, cross-corpus
> contradictions, stale claims) — things a single per-source ingest cannot guarantee.

### Step 8 — Report the new pages + confidence (for the user to check)
After the self-check, surface a short summary so the human can review the agent's trust assignments: list
each page **created or updated** with its assigned `confidence` (add a word of basis for any non-obvious
one — an `authoritative`, or a `low`/`very-low`). Invite the user to flag any to re-grade; confidence is a
one-line change. Example:

```
Ingested 1 source → 6 pages (review confidence):
- [[some-source-slug]] — high  (peer-reviewed paper)
- [[Some Concept]] — medium
- [[Some Entity]] — low  (single promo source)
Flag any you'd like re-graded.
```
This keeps the human in the loop on confidence — the one field the agent assigns by judgement.

## Hard constraints
- **Pace via the Pacing section** (default = `auto`). Keep the human in the loop for conflicts and
  large/uncertain batches; don't ask permission for small, low-risk, on-topic batches.
- **Never** modify or delete the text inside an existing raw file. The only permitted `raw/` writes
  are *relocating* a file (Step 6) and *adding* a MarkItDown-converted `.md` beside its original (Step 0).
- Convert every non-`.md` source with `markitdown` before reading it; never guess a binary file's contents.
- Every wiki page must have a `## Related` section (no orphans).
- Every wiki page (except `map`) carries a `confidence` — assign it per CLAUDE.md §4.6 (free, since you've already read the source).
- After ingesting, **report the created/updated pages with their `confidence`** so the user can review and re-grade (Step 8).
- **Refresh on write:** if qmd is active, refresh its index for the pages you created/updated (`qmd update && qmd embed`, incremental — the `qmd-search` hook); a no-op when qmd is dormant.
- Entities/Concepts = Title Case filenames; Sources/Syntheses = kebab-case.
- Write everything in **British/UK English** (US spelling only inside verbatim quotes, proper nouns, or code).
- Don't fabricate. Mark uncertain claims `unverified` and cite the source.
