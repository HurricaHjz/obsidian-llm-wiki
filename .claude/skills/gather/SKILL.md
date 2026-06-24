---
name: gather
description: >
  Deep Raw-layer capture: collect a whole topic's web sources at once. Given a seed URL (or a few),
  fetch it, find the relevant links it cites (papers/repos/docs), and — after showing you a preview you
  approve — capture those too into raw/, with images localised, ready for /ingest. Use when the user runs
  /gather, or says "gather sources on X", "deep-capture these links", "grab this article AND the repos/
  papers it cites". Safe by default (conservative caps + preview + a hard ceiling) for non-experts;
  fully overridable (depth/pages/include/exclude/--yes) for experts. Opt-in; does nothing until invoked.
  It only CAPTURES into raw/ — the normal /ingest skill then compiles. Read-only except for adding new
  raw files (never edits existing raw content).
user-invocable: true
---

# gather — deep Raw-layer capture (seed + the relevant links it cites)

## Goal
Strengthen the **Raw layer** (the real bottleneck of the LLM-Wiki pattern — see [[laozhang-web-pack-skill]]):
turn one seed link into a high-quality set of captured sources by following the links it cites, **without**
fan-out blow-ups or off-topic noise. Output lands in `raw/`; `/ingest` then compiles it. Inspired by the
[[web-pack]] tool, adapted to this vault's rules.

**Dual-mode — one command, two speeds:**

| | Non-expert (defaults) | Expert (override) |
|---|---|---|
| Scope | depth 1 · ≤10 pages · content-links only | `--max-depth 2`, `--max-pages 50`, `--same-domain`, or natural language ("two hops, only papers") |
| Confirmation | **always previews the plan + cost estimate and waits** | `--yes` skips the preview for trusted runs |
| Link choice | the built-in heuristics (consistent) | `--include a,b` / `--exclude c,d`, or "also follow the blog links / skip GitHub" |
| Ceiling | hard cap **100 pages — nobody can override** | same (protects the token budget) |

## Triggers
`/gather <url ...> [flags]` · "gather sources on <topic>" · "deep-capture these links" ·
"ingest this and also grab the repos/papers it cites".

## Pipeline
### 0 — Scope
Parse the seed URL(s) + flags. Translate any natural-language intent into flags (e.g. *"go two hops, only
papers"* → `--max-depth 2 --include arxiv,doi,/paper`). Unstated → use the safe defaults above.

### 1 — Fetch the seed(s)
Capture each seed with the `ingest` Step-0 chain (`defuddle` for pages, `curl` for raw/`.md`,
`markitdown` for binaries, **Jina Reader fallback** if those fail). Save the seed Markdown to a temp file.

### 2 — Plan (the consistency engine — deterministic)
Run the classifier so every gather applies the SAME rules:
```bash
python3 .claude/skills/gather/gather_links.py <seed.md> --seed-url "<url>" \
        --max-pages <N> [--same-domain] [--include a,b] [--exclude c,d] --json
```
It returns `expand` (will fetch), `maybe` (ask), `skip` (won't), already capped. (Heuristics live in that
script — expand docs/papers/repos/READMEs/benchmarks; skip nav/ads/login/social/logos.)

### 3 — Preview & confirm (DEFAULT — skip only with `--yes`)
Show the plan **and an estimated cost** ("will fetch N pages ≈ ~M k tokens to capture + compile; ask
about K; skipping J"). Invite the user to **approve / prune / adjust caps / reclassify** the `maybe`s.
This is both the footgun guard and the curation step — the human stays in control.

### 4 — Capture (into raw/)
Fetch each APPROVED link with the same chain (→ Jina fallback). For each, write `raw/<slug>.md` with
provenance frontmatter (`converted_from` / `converted_by` / `converted_on`), download body images to
`assets/` with relative paths, and **sanitize** as in `ingest` Step 0. Respect `--max-pages` and the hard
**100-page ceiling**. For `--max-depth > 1`, repeat steps 2–4 on the newly captured pages, **re-previewing
each hop** (unless `--yes`). Never edit existing raw files — only add new ones.

### 5 — Hand off to ingest
The captures now sit in the `raw/` inbox. Offer to run `/ingest` to compile them (or chain automatically
with `--ingest`). Report what was captured, skipped, and the running page/cost total.

## Flags
`--max-depth N` (default 1) · `--max-pages N` (default 10; hard ceiling 100) · `--same-domain` ·
`--include a,b` · `--exclude c,d` · `--yes` (skip previews) · `--ingest` (compile after capturing).

## Hard constraints
- **Preview-and-confirm by default.** Only `--yes` skips it. Always show the page count + cost estimate.
- **Caps are real**: never exceed `--max-pages`, and never exceed the non-overridable **100-page ceiling**.
- **Raw immutability**: only *add* new captures to `raw/` (the §3.1 "converted `.md`" provision); never
  edit or delete existing raw bytes.
- **Capture, don't summarise**: use `defuddle`/`curl`/`markitdown`/Jina (verbatim/extraction). Never fill
  gaps with invented content; mark anything uncertain `unverified`.
- **Privacy/safety**: skip anything behind a login or obviously private; the Jina fallback routes URLs
  through a third party, so don't use it for sensitive links.
- **British/UK English**; translate non-English captures. Don't compile here — that's `/ingest`'s job.

## Relationship to the other skills
- **`gather`** → builds the *Raw layer* (deep multi-link capture into `raw/`).
- **`ingest`** → *compiles* `raw/` into linked `wiki/` pages (run it after gather).
- **[[web-pack]]** (wiki tool page) → the external Skill that inspired this; **[[Jina Reader]]** → the fallback fetcher.
