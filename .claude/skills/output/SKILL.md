---
name: output
description: >
  Produce a user-facing DELIVERABLE (report, brief, literature review, slide deck, table, email,
  outline, …) into the output/ directory — grounded in the wiki and strictly following the user's
  instruction. Use when the user runs /output, or says "write/draft/produce/generate me a <X> about
  <Y>", "make a <report/brief/deck/email/table> from my notes/wiki", or "turn [[topic]] into <format>
  in output/". Distinct from `query` (answers inline or files a cited synthesis INTO the wiki) and
  `export-okf` (exports the whole vault). The deliverable goes to output/, cites the wiki pages it
  draws on, clearly labels any general-knowledge content, and NEVER fabricates facts, figures, quotes
  or citations.
user-invocable: true
---

# output — generate a grounded deliverable into `output/`

## Goal
Turn a user instruction + the compiled wiki into a **deliverable file in `output/`** that (a) **follows
the instruction exactly** (format, scope, length, audience, style), (b) is **grounded** in the wiki and
**cited**, and (c) **never hallucinates**. This operationalises the vault's own calibration ethos
([[RLCR]], [[behaviorally-calibrated-rl-hallucination]], [[Calibration]]): be accurate, be calibrated,
and **abstain when unsure** rather than confabulate.

## Triggers
- `/output <instruction>`
- "write / draft / produce / generate me a <deliverable> about <X>", "make a <report / brief / deck /
  table / email> from my notes", "turn [[topic]] into <format>".

## Pipeline

### Step 1 — Pin the instruction (no drift)
Extract a small **spec** from the user's words: *deliverable type · topic/scope · format · length/size ·
audience · tone · must-include / must-exclude · citation style · output filename*. If a **material**
detail is missing or genuinely ambiguous, ask **1–2 crisp questions**; otherwise proceed with sensible
defaults **and state them**. Never silently widen, narrow, or reinterpret the ask.

### Step 2 — Ground in the wiki (read first, like `query`)
Read `wiki/index.md`, then deep-read the relevant pages (follow `## Related` one hop). Collect the
facts you will use **together with the page each comes from** (for citation). The deliverable is built
from compiled knowledge — *not guessed*. Consult `wiki/user/` for personal context when the deliverable
is about, or for, the owner. **Triage by `confidence` as `query` does**: lean on `authoritative`/`high`
pages for load-bearing claims; the field is already in frontmatter, so this is free. If the catalogue
under-covers and qmd is active (the `qmd-search` skill, dormant unless installed), use it as the semantic
fallback to locate relevant pages, then deep-read; otherwise `grep`.

### Step 3 — Separate grounded · general · unknown (anti-hallucination core)
Classify every claim before you write it:
- **Grounded in the wiki** → cite the page(s) inline as `[[Page]]` (or the requested citation style); weight by the page's `confidence` — state `authoritative`/`high` plainly, but attribute and hedge any claim resting only on `low`/`very-low` pages.
- **General knowledge** the instruction needs but the wiki lacks → include **only if clearly labelled**
  (e.g. *"(general knowledge — not from the wiki)"*). Never present it as wiki-sourced.
- **Unknown / unverifiable** → **do not invent it.** Omit and note the gap, or mark a factual claim
  `unverified`. **Never fabricate facts, numbers, quotes, or citations.** Prefer quoting the raw source
  over paraphrasing when precision matters.
- If the instruction needs something neither the wiki nor safe general knowledge can support, **say so**
  in the deliverable / report rather than fill the gap with invention.

### Step 4 — Produce the deliverable, strictly to spec
Write exactly what was asked, in the requested **format and length**: a Markdown report/brief/review
(default), a **Marp** deck (`marp: true` frontmatter), a table, an email, a Canvas via the `json-canvas`
skill, etc. Use **British/UK English**; keep verbatim quotes exact; honour must-include/exclude. Default
citations are inline `[[wikilinks]]` (clickable in Obsidian); use a footnote/bibliography style instead
if the deliverable is external-facing or the user asks.

### Step 5 — Write to `output/<slug>.<ext>` (never into `wiki/`)
Save to **`output/`** (the deliverables layer — *not* the knowledge graph). Filename = a clean
kebab-case slug + correct extension. Do **not** modify `wiki/` or `raw/`. (If the user wants the result
compounded back into the knowledge base, that's a `query` synthesis, not an `output`.)

### Step 6 — Report + grounding note
State the path written, then a 2–3-line **grounding note**: which wiki pages it draws on, what (if
anything) is labelled general-knowledge, and any gaps flagged or questions still open.

## Hard constraints
- **Follow the instruction exactly** — format, length, scope, inclusions/exclusions. Use defaults only
  when unstated, and state them when used.
- **No hallucination.** Grounded → cite; general → label; unknown → omit / flag / abstain. **Never
  invent facts, figures, quotes, or citations.**
- **Weight by `confidence`.** Prefer higher-confidence wiki pages for key claims; attribute and hedge anything resting only on `low`/`very-low` pages.
- **Write only to `output/`.** Never edit `wiki/` or `raw/`. Outputs are deliverables, not knowledge.
- **British/UK English** and all other CLAUDE.md rules apply.
- **Not logged by default** — a deliverable is not a brain-update (CLAUDE.md §5). Log only if the user
  asks, or if the run also files a wiki page.

## Relationship to the other skills
- **`query`** → answers a question (inline, or a cited **synthesis filed into the wiki** to compound knowledge).
- **`output`** → produces a **standalone deliverable into `output/`** for use outside the wiki.
- **`export-okf`** → exports the **whole vault** as a portable OKF bundle.
