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
  Big budgets flow through a ranked policy gate (--shortlist, --queries tune the funnel); a
  per-run ledger plus a scripted sole write path harden caps, raw immutability and provenance
  (v3.1). Opt-in; does nothing until invoked. It only CAPTURES into raw/ — /ingest compiles.
  Writes only new
  raw files, their asset images and its own log entry (never edits existing raw content).
user-invocable: true
---

# gather — web capture into raw/ (seed mode + search mode)

## Goal
Turn either a set of links (seed mode) or a bare topic (search mode) into a high-quality set of
captured sources in `raw/`, without fan-out blow-ups, off-topic noise, or silent writes. `/ingest`
then compiles. Capture is document-granular — whole pages, verbatim; salience is ingest's job.

**The whole logic in three lines** (the minimal model; single-letter symbols live in the scripts):
- **Two inputs**: the owner's page budget, and the topic's uncovered sub-questions (round 1: the
  brief's facets; later rounds: the open gaps — same thing, next moment).
- **One funnel**: search wide → rank a pool → show a menu → the owner approves → capture.
- **Three principles**: numbers bound, never oblige (every cap is a cap, not a quota); nothing is
  written without the owner's yes, and noes outlive yeses (drops persist, rules don't); judgement
  declares itself, arithmetic is scripted (the agent states sub-questions/relevance/advice, the
  scripts derive and print every number).

## Modes & routing (deterministic — any agent, any model, same result)
- ≥1 URL among the arguments → **seed mode**. Free text alongside = scope + focus.
- No URL, a topic/question present → **search mode**. The text is the **brief**: goal, any
  include/exclude criteria, recency expectations.
- Explicit `--seed` / `--search "<brief>"` overrides inference. Neither URL nor topic — or `--seed`
  with no URL — → **ask**. Out-of-range flag values are clamped to their bounds and the clamp is
  reported at the gate.
- Every run echoes its parsed **run-spec** (mode · seeds/brief · focus · expand · rounds · caps;
  search mode adds the brief's facet list and the `funnel_knobs.py` block) at the first gate, so a
  misroute dies at the preview, never at capture. A mid-run constraint change (caps, date window,
  focus, mode — at an open gate or between rounds) re-echoes the FULL updated run-spec, never just
  the changed value.

| | Non-expert (defaults) | Expert (override) |
|---|---|---|
| Scope | search: results only (expand 0) · seed: 1 citation hop · ≤10 pages | `--expand 2`, `--max-pages 50`, `--same-domain`, or natural language ("two hops, only papers") |
| Confirmation | **always previews the plan + cost estimate and waits** | `--yes` skips previews for trusted runs (the search Discover gate still waits) |
| Link choice | built-in heuristics (consistent) | `--include a,b` / `--exclude c,d` / `--focus "<topic>"` |
| Ceiling | hard cap **100 pages — nobody can override** | same (protects the token budget) |

## Flags
`--search "<brief>"` · `--seed` · `--expand N` — citation hops beyond the fetched base (default:
seed 1 · search 0; no fixed clamp — the page caps bound it; `--max-depth` accepted as a legacy
alias) · `--focus "<topic>"` — semantic
relevance filter (implied by the brief in search mode) · `--rounds N` — search-mode iterative
deepening (default 1, max 3) · `--max-pages N` (default 10; hard ceiling 100) · `--shortlist N` —
full-detail rows at the Discover gate (search mode; default min(12, remaining budget); clamp ≤20) ·
`--queries N` — search queries per round (search mode; default 2 per brief facet within 3–12;
clamp ≤12) · `--same-domain` ·
`--include a,b` / `--exclude c,d` (seed mode: URL substring patterns for the classifier · search
mode: domain names for the search engine, with non-domain patterns applied as substring
post-filters on the results) · `--yes` (skip Step-4 previews — the Discover gate always waits) ·
`--ingest` (compile after capturing) · `--no-ledger` (limit the run ledger to write-path
bookkeeping; its cross-round authority is otherwise auto-on when `--rounds > 1` or budget ≥ 30).

## Pipeline
### 0 — Scope (both modes)
Parse args + natural language into the run-spec; NL intent maps to flags (*"two hops, only papers"*
→ `--expand 2 --include arxiv,doi,/paper`; *"only the parts about X"* → `--focus "X"`; *"show me
10"* → `--shortlist 10`). Unstated → the safe defaults above. Then two mechanical set-ups, both
declared in the run-spec echo:
- **Engine preflight**: verify the capture chain (`defuddle`, `markitdown`, `gh`) is available and
  declare any substitution up front ("defuddle absent → Jina fallback" — third-party routing is
  consented before capture, not reported after).
- **Run ledger**: every run inits one (`python3 .claude/skills/gather/run_ledger.py init
  --id <run-id> --budget <N>`) — the write path requires it. Its cross-round AUTHORITY (feeding
  `funnel_knobs.py --ledger-id`, the mismatch rule, resume) engages when `--rounds > 1` or the
  budget ≥ 30, unless `--no-ledger`. The ledger is evidence, never authority over the owner: on
  any ledger-versus-memory mismatch STOP and ask; if the file goes missing mid-run, fall back to
  model memory and DECLARE the fallback at the next gate.

### 1 — Discover (search mode only)
1. State the brief's **facets** (its distinct sub-questions — the list is printed in the run-spec
   echo), then fix the round's knobs deterministically:
   ```bash
   python3 .claude/skills/gather/funnel_knobs.py --max-pages <N> --facets <F> \
           [--shortlist N] [--queries N] [--pages-captured N | --ledger-id ID] \
           [--advice N] [--date-window] [--json]
   ```
   (Queries = 2/sub-question within 3–12 · menu = min(12, remaining budget), `--shortlist` ≤20 ·
   pool = min(60, max(3×menu, ⌈1.5×remaining⌉)) · date-check policy · a "reachable this round
   ≤pool — consider --rounds" warning when the remaining budget exceeds the pool. Every clamp is
   reported and the block is echoed VERBATIM at the gate; the gate echo re-runs it with
   `--advice <N>` once triage has produced the worth-capturing count.) Derive that many query
   angles (distinct
   phrasings/aspects; recency terms where freshness matters) and run WebSearch per query, with
   `--include`/`--exclude` mapped to allowed/blocked domains. The pool holds the top candidates
   by triage score, up to the pool value — a cap, not a quota: underfill is reported, with
   `--queries`/`--rounds` suggested.
2. Triage on result metadata — no capture fetches at this stage. Dedupe by URL; classify provenance
   (official docs / paper / repo / engineering blog / news / aggregator); score relevance against
   the brief; run ≤6 throwaway WebFetch date checks per round on unclear finalists (never a
   capture path; unknown → mark "date unverified"). From the scored pool, state the **advice
   count** — how many look genuinely worth capturing — for the gate's `--advice` echo. A **hard
   date window** — an explicit
   user-stated cutoff ("2026-04 onwards", "last three months"; a mere freshness preference like
   "recent work" is NOT one) — instead date-verifies EVERY menu row pre-gate, the overrun
   past the ≤6 baseline declared at the gate, and rule-selected below-menu rows are date-checked
   at capture: out-of-window pages are discarded unwritten, the spent fetch reported, and the
   shortfall NOT auto-backfilled — offer a follow-up rule or round instead. Drop junk (listicles,
   undated marketing, off-topic) — every drop listed with its reason.
3. Vault de-dup pre-check — mechanised: `python3 .claude/skills/gather/capture_write.py dedup
   --urls <candidates> --control <known-present URL>` scans `source_url`/`converted_from` across
   `raw/` + `wiki/`; the control URL must hit or the scan aborts (proof the probe ran, CLAUDE.md
   §11; `--allow-no-control` only for a provably fresh vault, declared). Matches are shown as
   "already in vault", not proposed.
4. Present the **Discover gate**, headed by the run-spec + funnel block + the LITERAL queries run:
   - **Menu** (the shortlist: full-detail rows — a menu, not a promise): numbered — title ·
     provenance class · date (✓ = page-verified) · one-line relevance · likely raw/ category
     subfolder (informational; capture writes to the raw/ root, ingest sorts later).
   - **Advice line**: "of the <pool> ranked, ~N look genuinely worth capturing" — the agent's
     judged count from the triage scores, echoed via `--advice` in the funnel block. Advice
     widens what is SHOWN below, never what a rule may buy.
   - **Ranked remainder** (shown when the remaining budget OR the advice count exceeds the menu):
     pool candidates as one-liners — rank · title · provenance · date · relevance —
     rule-selectable. Rows beyond the remaining budget carry the block's marker ("rows beyond №R
     need an explicit budget raise"): rules always cap at the remaining budget, and capturing a
     marked row needs an explicit raise — a mid-run constraint change that re-echoes the FULL
     run-spec, the 100-page ceiling binding as ever. When neither budget nor advice exceeds the
     menu, candidates below the cutoff are summarised in one line ("+K ranked below — say 'show
     all'"), never silently dropped.
   - Everything dropped or deduped, with reasons; a cost estimate for the menu and, when the
     remainder is shown, for a full-budget rule.
   **GATE — never skipped, even with `--yes`**: discovered pages are unknowns and always get
   human curation. Approval semantics, pinned: a bare "approve" captures the MENU ONLY (the
   gate's prompt line says so; if an explicit `--shortlist` made the menu exceed the remaining
   budget, it captures the menu's top rows up to the budget, clamp reported). For more, give a
   rule ("top N by relevance"; N > remaining budget
   is clamped and reported), a rule plus curation ("top 25, drop 9, add 31"), or row-by-row
   choices. Before capturing, echo the RESOLVED set in one line (rows · count · cost) and record
   it in the ledger (`run_ledger.py add-gate`; every explicit drop → `add-drop`); an
   ambiguous rule is asked back, never guessed. A rule NEVER carries across rounds — each round's
   gate is fresh ("same rule" must be said); an explicit DROP does persist — a row the user
   dropped at an earlier gate this run stays out of every later menu and rule resolution,
   re-listed only among the drops ("dropped at round 1") if a later search re-surfaces it, and
   re-entering only when named explicitly. With `--expand 0` (the search default) this approval
   IS the capture approval → approved rows go straight to Step 5 (the approved pages themselves
   are the captures). With `--expand ≥ 1`, approved rows enter Steps 2–4 as seeds AND are
   captured at Step 5.

Guards: WebSearch unavailable → say so and ask for seed URLs — never substitute model memory. Zero
hits → print the queries run (proof the probe ran) and offer reformulations. Results are US-region
— note it when the topic suggests non-US sources (those may need direct URLs). When search returns
only secondary coverage of a known primary artefact (a repo, a paper), a declared **locate probe**
is permitted — ≤2 per round (a `gh` search, an arXiv listing lookup), discovery only, never a
capture path, reported at the gate like every other pre-consent spend.

### 2 — Fetch the seed(s)
Capture each seed with the `ingest` Step-0 chain (`defuddle` for pages, `curl` for raw/`.md`,
`markitdown` for binaries, **Jina Reader fallback** if those fail). Save the seed Markdown to a
temp file for Step 3 (outside the vault, e.g. `/tmp` — not a vault write). Base pages (seeds, or
search-mode approved results) are themselves captures: they are written to `raw/` at Step 5 and
count against the page caps. Seed mode with `--expand 0` skips Steps 3–4 entirely — the given
URLs are the whole capture set (batch-capture shorthand), previewed once with the cost estimate
BEFORE anything is fetched (unless `--yes`).

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

### 4 — Preview & confirm (DEFAULT for expansion hops — skip only with `--yes`; the `--expand 0` paths above carry their own approval)
Show the plan **and an estimated cost** ("will fetch N pages ≈ ~M k tokens to capture + compile;
ask about K; skipping J" — assume ≈4k tokens per captured page and ≈2× that to compile, and state
the assumption), headed by the run-spec. Invite the user to **approve / prune / adjust caps /
reclassify** the `maybe`s and any focus demotions; promotions count against `--max-pages` — the
run never exceeds it. Under `--yes` this preview is skipped with the conservative disposition:
`maybe` links skipped, focus demotions applied. This is both the footgun guard and the curation
step — the human stays in control.

### 5 — Capture (into raw/)
Fetch each APPROVED link with the same chain (→ Jina fallback). A page whose whole chain fails
(Jina included) is reported — URL, engines tried — and its slot is never auto-backfilled from
the ranked remainder; offer a follow-up rule or round instead (the date-window discard rule,
mirrored). Write each captured page through the SOLE write path:
```bash
python3 .claude/skills/gather/capture_write.py write --url <url> --engine <engine> \
        --ledger-id <run-id> [--title T] < fetched.md
```
It enforces the budget and the 100 ceiling against the ledger, refuses any existing path (raw
immutability, mechanical), sanitises (ingest Step-0 rules, tested), writes `raw/<slug>.md` with
full provenance frontmatter (`converted_from`/`converted_by`/`converted_on` + `source_url` so
ingest's de-dup keeps working), and appends the capture to the ledger in one step. If the script
is missing or broken, STOP and ask — never hand-write a capture around it. Download body images
to `assets/` with relative paths. Respect `--max-pages` and the hard **100-page ceiling**
(cumulative across rounds and hops: each repeat invocation of the classifier is passed the
REMAINING budget — `--max-pages` minus pages already captured this run). For `--expand > 1`,
repeat Steps 3–5 on the newly captured pages, **re-previewing each hop** (unless `--yes`). Never
edit existing raw files — only add new ones.

### 6 — Rounds (search mode, `--rounds > 1`)
From the round's captured material, list the brief's open gaps (subtopics still uncovered —
derived from what was already read; no re-reads). No gaps → stop early and say so. Otherwise
re-enter Step 1, re-running `funnel_knobs.py` with `--ledger-id <run-id>` (the ledger supplies
pages-captured; a ledger-versus-memory mismatch → STOP and ask; ledger authority off → the
`--pages-captured` flag, stated) AND `--facets` = the number
of open gaps: the gap list IS that round's facet list (printed at its gate), and the gap-derived
queries ARE that round's Step-1.1 derivation (2 per gap, within the band). Every knob recomputes
from the REMAINING budget, so later rounds shrink naturally. Every round gets the same gate under
the same semantics and shares the cumulative caps; no approval rule carries over from an earlier
round (explicit drops DO persist — Step 1.4).

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
  never edit or delete existing raw bytes — mechanically enforced: `capture_write.py` is the sole
  write path and refuses existing paths.
- **Capture, don't summarise**: use `defuddle`/`curl`/`markitdown`/Jina (verbatim/extraction).
  WebFetch is triage-only (throwaway date checks) — never a capture path. Never fill gaps with
  invented content; mark anything uncertain `unverified`.
- **Privacy/safety**: skip anything behind a login or obviously private; the Jina fallback routes
  URLs through a third party, so don't use it for sensitive links.
- **British/UK English**; translate non-English captures, noting the translation in the provenance
  frontmatter. Don't compile here — that's `/ingest`'s job.

## Logging
After a completed capture run, append one `gather` entry to `wiki/log.md` via shell (`cat >>`):
mode, seed URL(s) or the brief + the queries run (and rounds), any policy rule approved at the
gate, pages captured, where they landed in `raw/`, and that the batch awaits `/ingest`. A
preview-only or aborted run (nothing captured) is not logged. After the entry, the run ledger
(`/tmp/gather-run-<id>.json`) may be deleted — run-scoped scratch, never knowledge.

## Relationship to the other skills
- **`gather`** → builds the *Raw layer* (search-driven or seed-driven multi-link capture into `raw/`).
- **`ingest`** → *compiles* `raw/` into linked `wiki/` pages (run it after gather).
- **`query` / `output`** → the reporting half of deep research: cited answers/deliverables from
  the compiled pages. gather + ingest + query/output together replace external deep-research tools.
