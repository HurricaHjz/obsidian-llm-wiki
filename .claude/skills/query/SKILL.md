---
name: query
description: >
  Answer questions against the local Obsidian wiki — not from model memory. Use when the user runs
  /query, or asks in natural language about "my notes / my wiki / what I've researched / my past
  decisions / what do I know about X". Always read wiki/index.md FIRST to locate pages, then read
  them in full, then answer with [[wikilink]] citations. If the wiki has nothing relevant, say so
  explicitly before giving any general-knowledge answer. Offers to file high-value answers back
  into wiki/syntheses/ so explorations compound.
user-invocable: true
---

# query — answer from the wiki, with citations

## Goal
Turn a question into a **deep read of the compiled wiki** and a synthesized, **cited** answer.
When the answer is valuable, **file it back** into the wiki so knowledge compounds.

## Triggers
- `/query <question>`
- Natural language: "what do my notes say about X", "what was my past decision on Y", "search my wiki for Z"
- Mentions of: my wiki / my notes / my knowledge base / what I've researched.

## Modes: depth & style (see CLAUDE.md → Processing modes)
Match answer depth to the mode (auto standard/concise; `research` is opt-in or ask-first).
**All modes stay token-efficient — `research` permits more depth, never filler.**
- **standard (DEFAULT)** — balanced, cited synthesis.
- **concise** — a tight, direct answer citing only the few key pages.
- **research** — rigorous and exhaustive: exact figures, verbatim quotes with refs, explicit treatment
  of agreements/contradictions across sources, and a short "limitations / gaps" note. Higher accuracy
  bar, still no filler. A filed synthesis uses academic structure + `mode: research`.

## Pipeline

### Step 1 — Read the global index (always first)
Read `wiki/index.md` and locate candidate pages across **Sources / Entities / Concepts / Syntheses**.

### Step 2 — Deep-read the targets (triage by confidence)
Open the most relevant pages in full with the read tool (or `obsidian-cli`). Follow `## Related`
links one hop out when it helps. **When candidates are many, first check their `confidence` cheaply
(one `grep "^confidence:" <candidate files>`, frontmatter only) and deep-read `authoritative`/`high`
first; pull in `medium` as needed; consult `low`/`very-low` only to fill gaps.** This is net
token-saving — it skips full reads of low-value pages.

### Step 3 — Synthesize with citations (weighted by confidence)
- Cite every page you draw from inline as `[[Page Name]]`.
- For a verbatim claim, use a `> blockquote`.
- Don't over-cite: one citation at the start and end of a passage from the same page is enough.
- **Weight by `confidence`:** resolve conflicts toward the higher tier (and, if tied, the newer
  `updated`); state `authoritative`/`high` plainly, but attribute and hedge `low`/`very-low`
  ("a promotional listing claims…", "an unverified transcript suggests…"); never let a `very-low` or
  `unverified` claim harden into an asserted fact. Optionally flag a weak citation inline, e.g.
  `[[X]] *(low-confidence)*` (only for `low`/`very-low`). The signal is already in frontmatter, so this is free.

### Step 4 — Degrade gracefully (two cases, never a bare refusal)
- **No coverage** — if `index.md` has nothing relevant and the question is general knowledge, say so first:
  > Nothing in the local wiki covers this — answering from general knowledge:
  …then answer. Never silently pretend the wiki had the answer.
- **Only low-confidence coverage** — if the wiki *does* cover it but only at `low`/`very-low`, **still
  give the substantive answer from those pages**, opening with an explicit warning, e.g.:
  > ⚠ Low-confidence: the only sources here are a promo listing and an auto-transcript — treat as provisional.
  Never refuse with a bare "I don't know".

### Step 5 — File high-value answers back
If the answer is more than ~2 paragraphs or is comparative/analytical, ask:
> This looks worth keeping — save it to `wiki/syntheses/`?

On yes, create `wiki/syntheses/<slug>.md` (kebab-case) with synthesis frontmatter, a
`## Sources Used` section listing every cited `[[page]]`, and register it under **Syntheses** in `index.md`.
Give it a **conservative inherited `confidence`** (a synthesis caps at `medium` as agent-derived; drop to
`low` if it rests mainly on `low` sources); never crystallise a `low`/`unverified` claim as asserted fact.

### Step 6 — Log it (only if you filed a synthesis)
**A pure inline answer is NOT logged** — logging is for brain-updating ops only (see CLAUDE.md §5).
**Only if Step 5 actually filed a synthesis**, append:
```markdown
## [YYYY-MM-DD] query | <short question>
- **Output**: filed [[synthesis-slug]]; updated [[index.md]]
```
Log a no-synthesis (inline-only) query **only if the user explicitly asks**.

## Hard constraints
- **Never answer substantive questions from memory** — read the wiki first.
- **Never** silently answer when the wiki lacks coverage — declare it.
- **Use `confidence`** to triage, weight and hedge; on only-`low` coverage, answer *with a warning*, never a bare refusal.
- Output in **British/UK English** with real `[[wikilink]]` citations.
