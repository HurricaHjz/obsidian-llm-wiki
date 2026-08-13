---
name: gather
description: >
  Web capture into raw/, two modes, one pipeline. SEED mode: given URL(s), fetch them and (optionally)
  the relevant links they cite. SEARCH mode: given a topic and no URL, web-search it, triage the hits,
  and present a dated shortlist for approval before anything is fetched — the vault's native
  deep-research entry (topic → sources → wiki; the cited report then comes from ingest + query/output).
  Use on /gather, "gather sources on <topic>", "search the web for X and save the sources",
  "deep-capture these links", "grab this article AND the repos/papers it cites". Preview-and-approve
  gates by default; conservative caps + a hard 100-page ceiling; expert flags (--search/--seed,
  --expand, --focus, --rounds, --max-pages, --include/--exclude, --same-domain, --yes, --ingest).
  Opt-in; does nothing until invoked. It only CAPTURES into raw/ — /ingest compiles. Writes only new
  raw files, their asset images and its own log entry (never edits existing raw content).
user-invocable: true
---

# gather — web capture into raw/ (seed mode + search mode)

## Goal
Turn either a set of links (seed mode) or a bare topic (search mode) into a high-quality set of
captured sources in `raw/`, without fan-out blow-ups, off-topic noise, or silent writes. `/ingest`
then compiles. Capture is document-granular — whole pages, verbatim; salience is ingest's job.

## Modes & routing (deterministic — any agent, any model, same result)
- ≥1 URL among the arguments → **seed mode**. Free text alongside = scope + focus.
- No URL, a topic/question present → **search mode**. The text is the **brief**: goal, any
  include/exclude criteria, recency expectations.
- Explicit `--seed` / `--search "<brief>"` overrides inference. Neither URL nor topic — or `--seed`
  with no URL — → **ask**. Out-of-range flag values are clamped to their bounds and the clamp is
  reported at the gate.
- Every run echoes its parsed **run-spec** (mode · seeds/brief · focus · expand · rounds · caps) at
  the first gate, so a misroute dies at the preview, never at capture.

| | Non-expert (defaults) | Expert (override) |
|---|---|---|
| Scope | search: results only (expand 0) · seed: 1 citation hop · ≤10 pages | `--expand 2`, `--max-pages 50`, `--same-domain`, or natural language ("two hops, only papers") |
| Confirmation | **always previews the plan + cost estimate and waits** | `--yes` skips previews for trusted runs |
| Link choice | built-in heuristics (consistent) | `--include a,b` / `--exclude c,d` / `--focus "<topic>"` |
| Ceiling | hard cap **100 pages — nobody can override** | same (protects the token budget) |

## Flags
`--search "<brief>"` · `--seed` · `--expand N` — citation hops beyond the fetched base (default:
seed 1 · search 0; `--max-depth` accepted as a legacy alias) · `--focus "<topic>"` — semantic
relevance filter (implied by the brief in search mode) · `--rounds N` — search-mode iterative
deepening (default 1, max 3) · `--max-pages N` (default 10; hard ceiling 100) · `--same-domain` ·
`--include a,b` / `--exclude c,d` (seed mode: URL substring patterns for the classifier · search
mode: domain names for the search engine, with non-domain patterns applied as substring
post-filters on the results) · `--yes` (skip Step-4 previews — the Discover gate always waits) ·
`--ingest` (compile after capturing).

## Pipeline
### 0 — Scope (both modes)
Parse args + natural language into the run-spec; NL intent maps to flags (*"two hops, only papers"*
→ `--expand 2 --include arxiv,doi,/paper`; *"only the parts about X"* → `--focus "X"`). Unstated →
the safe defaults above.

### 1 — Discover (search mode only)
1. Derive 3–6 query angles from the brief (distinct phrasings/aspects; recency terms where
   freshness matters). Run WebSearch per query, with `--include`/`--exclude` mapped to
   allowed/blocked domains. Pool ≤30 candidates.
2. Triage on result metadata — no capture fetches at this stage. Dedupe by URL; classify provenance
   (official docs / paper / repo / engineering blog / news / aggregator); date-check (≤6 WebFetch
   spot-checks per round on unclear finalists — throwaway reads, never capture; unknown → mark "date
   unverified"); score relevance against the brief. Drop junk (listicles, undated marketing,
   off-topic) — every drop listed with its reason.
3. Vault de-dup pre-check: grep shortlist URLs against `source_url`/`converted_from` in `raw/` and
   `wiki/` — matches are shown as "already in vault", not proposed.
4. Present the shortlist (≤12 — a menu, not a promise: approvals capture at most the `--max-pages`
   budget): numbered — title · provenance class · date · one-line relevance · likely raw/ category
   subfolder (informational; capture writes to the raw/ root, ingest sorts later) — headed by the
   run-spec, with a cost estimate and everything dropped or deduped. **GATE — never skipped, even
   with `--yes`**: discovered pages are unknowns and always get human curation. With `--expand 0`
   (the search default) this approval IS the capture approval → approved rows go straight to
   Step 5 (the approved pages themselves are the captures). With `--expand ≥ 1`, approved rows
   enter Steps 2–4 as seeds AND are captured at Step 5.

Guards: WebSearch unavailable → say so and ask for seed URLs — never substitute model memory. Zero
hits → print the queries run (proof the probe ran) and offer reformulations. Results are US-region
— note it when the topic suggests non-US sources (those may need direct URLs).

### 2 — Fetch the seed(s)
Capture each seed with the `ingest` Step-0 chain (`defuddle` for pages, `curl` for raw/`.md`,
`markitdown` for binaries, **Jina Reader fallback** if those fail). Save the seed Markdown to a
temp file for Step 3. Base pages (seeds, or search-mode approved results) are themselves captures:
they are written to `raw/` at Step 5 and count against the page caps. Seed mode with `--expand 0`
skips Steps 3–4 entirely — the given URLs are the whole capture set (batch-capture shorthand),
previewed once with the cost estimate unless `--yes`.

### 3 — Plan (the consistency engine — deterministic)
Run the classifier so every gather applies the SAME rules:
```bash
python3 .claude/skills/gather/gather_links.py <seed.md> --seed-url "<url>" \
        --max-pages <N> [--same-domain] [--include a,b] [--exclude c,d] --json
```
It returns `expand` (will fetch), `maybe` (ask) and `skip` (won't), with the page caps already
applied. (Heuristics live in that script — expand docs/papers/repos/READMEs/benchmarks; skip
nav/ads/login/social/logos.) With `--focus`, a labelled semantic pass runs AFTER the classifier:
each `expand`/`maybe` link is annotated for topical fit and demotions are proposed — both verdicts
shown side by side in the preview. The script's output is never altered; nothing is silently
dropped.

### 4 — Preview & confirm (DEFAULT — skip only with `--yes`)
Show the plan **and an estimated cost** ("will fetch N pages ≈ ~M k tokens to capture + compile;
ask about K; skipping J" — assume ≈4k tokens per captured page and ≈2× that to compile, and state
the assumption), headed by the run-spec. Invite the user to **approve / prune / adjust caps /
reclassify** the `maybe`s and any focus demotions; promotions count against `--max-pages` — the
run never exceeds it. Under `--yes` this preview is skipped with the conservative disposition:
`maybe` links skipped, focus demotions applied. This is both the footgun guard and the curation
step — the human stays in control.

### 5 — Capture (into raw/)
Fetch each APPROVED link with the same chain (→ Jina fallback). For each, write `raw/<slug>.md`
with provenance frontmatter (`converted_from` / `converted_by` / `converted_on`, plus `source_url`
so ingest's de-dup keeps working), download body images to `assets/` with relative paths, and
**sanitize** as in `ingest` Step 0. Respect `--max-pages` and the hard **100-page ceiling**
(cumulative across rounds and hops: each repeat invocation of the classifier is passed the
REMAINING budget — `--max-pages` minus pages already captured this run). For `--expand > 1`,
repeat Steps 3–5 on the newly captured pages, **re-previewing each hop** (unless `--yes`). Never
edit existing raw files — only add new ones.

### 6 — Rounds (search mode, `--rounds > 1`)
From the round's captured material, list the brief's open gaps (subtopics still uncovered —
derived from what was already read; no re-reads). No gaps → stop early and say so. Otherwise
derive next-round queries from the gaps and re-enter Step 1; every round gets the same gate and
shares the cumulative caps.

### 7 — Hand off to ingest
The captures now sit in the `raw/` inbox. Offer to run `/ingest` to compile them (or chain
automatically with `--ingest`). Report what was captured, skipped, and the running page/cost
total. For a synthesised report on the topic, follow with `/query` (filed into the wiki) or
`/output` (a deliverable) — discovery + capture here, reporting there.

## Hard constraints
- **Preview-and-confirm by default.** Only `--yes` skips it. Always show the page count + cost.
- **Caps are real**: never exceed `--max-pages` or the non-overridable **100-page ceiling**; and
  **no silent caps** — every cap hit, drop, demotion and dedup is reported at a gate.
- **Raw immutability**: only *add* new captures to `raw/` (CLAUDE.md §3.1's "converted `.md`" provision);
  never edit or delete existing raw bytes.
- **Capture, don't summarise**: use `defuddle`/`curl`/`markitdown`/Jina (verbatim/extraction).
  WebFetch is triage-only (throwaway spot-checks) — never a capture path. Never fill gaps with
  invented content; mark anything uncertain `unverified`.
- **Privacy/safety**: skip anything behind a login or obviously private; the Jina fallback routes
  URLs through a third party, so don't use it for sensitive links.
- **British/UK English**; translate non-English captures, noting the translation in the provenance
  frontmatter. Don't compile here — that's `/ingest`'s job.

## Logging
After a completed capture run, append one `gather` entry to `wiki/log.md` via shell (`cat >>`):
mode, seed URL(s) or the brief + the queries run (and rounds), pages captured, where they landed
in `raw/`, and that the batch awaits `/ingest`. A preview-only or aborted run (nothing captured)
is not logged.

## Relationship to the other skills
- **`gather`** → builds the *Raw layer* (search-driven or seed-driven multi-link capture into `raw/`).
- **`ingest`** → *compiles* `raw/` into linked `wiki/` pages (run it after gather).
- **`query` / `output`** → the reporting half of deep research: cited answers/deliverables from
  the compiled pages. gather + ingest + query/output together replace external deep-research tools.
