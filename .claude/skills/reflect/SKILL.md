---
name: reflect
description: >
  Sweep the current conversation for things worth keeping — knowledge and insight, working context
  (decisions, directions, preferences), method lessons, framework defects — and propose where each
  should be recorded, then write only what the owner approves. The test is future performance across
  ALL the owner's work (research, writing, funding, life), never framework development alone; an
  intuition the owner states counts. Defaults to the unrecorded essentials — the top few, load-bearing items, with the rest
  listed one line each; `--all` lifts the cap. Use ONLY on an explicit instruction: /reflect, "capture what we learned", "reflect on
  this session", "store the lessons from this". NEVER runs automatically and never fires from
  passive context. It is a SECOND lane beside the agent's ordinary in-flight filing, which is
  unchanged: this is the owner's own trigger for what that lane missed. Preview-and-approve every
  run; opt-in `--yes` writes only inside wiki/ under a create-and-append rule. `--cross
  <transcript>` runs the same bar over ANOTHER session's transcript via a read-only reflector
  lane (cross-reflection; see its section below).
user-invocable: true
---

# reflect — capture what a session learned, on the owner's word

The agent already files findings as it works — the in-flight lane is real and measured (see
`wiki/developments/reflect-skill-design.md`). **That lane is unchanged and ungated.** This skill is the *second* lane: an explicit trigger the owner owns, for the
times the first one did not fire. It removes model-dependence from the **trigger**, not from the quality
of the harvest — a weaker model still finds less; it just no longer has to think of looking.

**The test is always future performance, across everything the owner does** — research, writing, funding,
work and life as much as framework development. A hunch about a research direction, a preference learned
from how a draft was received, a decision and the reason behind it: each can be worth more to a future
session than any number of process notes. Do not read "essential" as "technical".

## Trigger — explicit only
`/reflect`, or an imperative addressed to the agent: "capture what we learned", "reflect on this
session", "store the lessons from this". **Passive context never fires it** — not an `<editor_selection>`,
not an `@`-mention, not a line in `IDEAS.md`. If a phrase like "we should remember that" appears in
passing, surface it and ask; do not start a run.

**Non-interactive runs** (headless, scheduled) propose and write nothing, unless `--yes` is set, in which
case the path rules below still bind.

## Pipeline

### Step 1 — Read the register's open entries
`wiki/developments/known-issues.md`, `## Open` only. Two reasons, both intrinsic: a candidate defect must
not duplicate an entry already there, and a lesson from this session sometimes **closes** one. Surface an
entry to the owner **only when a candidate touches it** — do not print the list every run.

### Step 2 — Sweep the visible conversation, and say how far it reaches
Collect candidates of four kinds. The first two matter most often; the last is the narrowest.
- **Knowledge & insight** — something established, corrected or discovered here that the wiki does not
  hold: a correction the owner made, a finding from a probe run in the conversation, a conclusion drawn
  across pages that sits on none of them, or **a stated intuition worth testing later**.
- **Working context** — how the owner works and where they are going: a decision and its reason, a
  direction taken or abandoned, a priority, a standing preference, a constraint that will recur. Usually
  `wiki/user/`, and usually invisible to any source-driven route.
- **Method / process lesson** — something about how to work that would change a future session.
- **Defect** — a fault in a framework surface (the schema, a skill, a script).

**Horizon, measured every run.** Earlier turns may have been compacted out of context, so measure the
boundary against the on-disk session transcript instead of asserting it: `echo` a fresh nonce in shell,
then grep for it under the harness transcript directory (Claude Code: `~/.claude/projects/<vault path,
separators as dashes>/*.jsonl`). The single file containing the nonce IS this session's record — the
transcript logs the probe itself, which is the positive control (CLAUDE.md §11). Count its human turns
with a filter **verified against the visible span** (every visible human turn must be matched; beware:
tool results AND harness task-notifications also carry `"type":"user"` and must both be excluded — the
notification miss overcounted 9 turns as 27, №103 cross-reflection P1, 2026-08-28), and report
`visible k of N recorded turns`. **Fallback** — no transcript, no unique nonce match, or a filter that fails its own check →
the unmeasured form: name the earliest visible turn and state that the boundary carries no control
this run. **Never report "nothing to capture this session"** — only "nothing in the visible span".
On `--full` (explicit request only), read the compacted-out remainder from the transcript file itself,
declaring the token cost before reading.

### Step 3 — Apply the bar, then keep only what matters
**The default is deliberately narrow: the unrecorded essentials, not everything noticed.** A long
session generates dozens of small observations; proposing them all buys the owner a review chore and
buries the two things that mattered.

A candidate survives only if all three hold:
1. **Evidenced** — it points at something that actually happened here: a command and its output, a
   correction, a file read, a review, **or the owner stating a judgement, hunch or preference**. The
   owner voicing an intuition *is* the event, and it is recordable — marked as a hypothesis and graded
   honestly by §4.6, not discarded for lacking proof. What fails this clause is *the agent's* own
   generality with no event behind it.
2. **Not already recorded** — check *everywhere* it could already live before proposing it: the
   destination page, `known-issues.md`, the relevant `developments/` doc, and a `grep` of `wiki/` for
   the claim. This is also what stops repeat runs re-proposing the same thing; there is no session
   cursor, and none can be built (the log carries no clock).
3. **Load-bearing** — one decidable question: *would a future session do the work worse without it?*
   That covers both halves — repeating a mistake, redoing work or answering wrongly, **and** missing a
   better approach, a known preference, or a direction already decided. If the honest answer is no, it
   is an observation, not a lesson. "Interesting" is not the bar; "would change what a future session
   does" is.

**Then rank and cut.** Order the survivors by that third test and **propose the top 5 at most**. List
every remaining survivor as a **one-line "seen, not proposed"** with its reason, so nothing is dropped
silently and the owner can pull one up. Where several candidates are variations of one underlying point,
merge them and propose the general form once — three symptoms of one fault are one lesson.

**Widening is explicit.** `--all`, or an instruction like "capture everything" / "don't filter", lifts
the cap and proposes every survivor. The bar itself never relaxes: an unevidenced or already-recorded
candidate is still not proposed, whatever the flag.

**Self-conduct.** A lesson about the agent's own behaviour is a candidate only if it **names the external
mechanism that caught it** — a printed control, a failing test, an owner correction, a reviewer. An
unwitnessed self-assessment has no witness and does not survive step 3.

**Probe discipline (2026-08-27).** A dedup grep never carries an exclusion filter — one filtered out the
very record that made a candidate redundant, manufacturing false novelty. And a probe's control is never
the claim under test: pair every 0-hit with a positive control that hits on the same surface (§11).

### Step 4 — Route it
In priority order. Say which rule sent it there.

| Destination | When | Note |
|---|---|---|
| A **rule** — `CLAUDE.md` or a skill | The lesson generalises, **and** it can tighten or replace an existing line | Contracts and skills are the surfaces actually read. But a rule that only *adds* a line feeds the always-on ratchet: report the byte delta and prefer a tightening |
| A **wiki page** (`concepts/`, `entities/`, `tools/`, `models/`, `benchmarks/`, `user/`) | Domain or research knowledge | New page or an addition to an existing one. `user/` is the owner's to curate — propose, never auto-write |
| A **`notes-*` synthesis** | A reusable procedure or a cross-page conclusion | `type: synthesis`, kebab-case, `notes-` prefix, `## Sources Used`, and `sources:` in frontmatter |
| `known-issues.md` | A framework defect out of scope to fix now | Entry format per §12 |
| **Discard** | Fails the bar, or is already recorded | Report it as discarded and why — a silent drop reads as "nothing found" |

**Contradictions.** A candidate that conflicts with something a page already claims never silently
overwrites it. Add a `## Conflicts / Open Questions` block keeping both statements and contrasting them
(CLAUDE.md §4.4), and say so at the preview. This is the common shape for an owner correction that
disagrees with a sourced claim.

**Sources.** A conversation here almost always rests on wiki pages, so cite them: `## Sources Used` plus
`sources:` in frontmatter. Where a finding is genuinely original with nothing prior to cite, that is a
legitimate page — say so plainly and let §4.6 grade it.

### Step 5 — Grade and attribute
**No confidence rule of its own.** Apply CLAUDE.md §4.6 to the evidence, not to who said it: the owner's
own work is `high` by default and drops if they state uncertainty; an inference from an `authoritative`
page inherits that standing; an extrapolation beyond the evidence is `very-low`. Record **provenance** in
the page — what the claim rests on — so a later reader can tell.

### Step 5b — Independent critique (default-on)
Before the preview, brief a subagent to **refute** the candidate table: per candidate — is the evidence
a real event in the recorded span, is it genuinely unrecorded (re-run the Step 3 destination checks),
is it load-bearing, and does a self-conduct item name a true external witness? A refuted candidate
moves to "seen, not proposed" with the refutation as its reason; an arguable refutation stays proposed
with the objection attached. **A refuted candidate's defensible residue is a NEW candidate**: it
re-enters at Step 3 and waits for the Step 6 preview like any other — never a direct write, however
broad the standing go (the missing salvage path let two refuted items ship pre-preview, №103 session,
recorded 2026-08-28). This is the bounded per-run witness self-reflection lacks (the
cross-session form is `## Cross-reflection` below). `--no-critic` skips it and the preview says "critic: skipped"; where the
harness offers no subagent mechanism, say "critic: unavailable". **The critic filters proposals; it
never approves writes — approval still terminates at the owner.**

### Step 6 — Preview, and get approval
One table, always, before any write:

```
Reflect — visible from turn N ("<first few words>"); earlier turns may have been compacted.
| # | Candidate | Evidence | → Destination | Tier | Edit |
Seen, not proposed (3): <one line each, with why it did not make the cut>
Discarded: 2 (already recorded ×1, no event behind it ×1)
Proposed rules: 1 · always-on cost +180 bytes
```

The owner approves per item ("1 and 3", "all but 2"). **Nothing is written without approval**, except
under `--yes` below.

### Step 7 — Write, log, report
- Write only the approved items. Every new page gets `## Related` and an `index.md` entry (§4.4, §5).
- **Log by what changed, never by which command ran**: `synthesis` for knowledge written into the wiki,
  `framework` for a contract or `developments/` change, nothing for a register append (§12 exempts it).
  A run that changes nothing logs nothing.
- Report what was written, where, at what tier, and what was discarded.

### Step 8 — Recommend, don't queue (owner-added 2026-08-27)
Close the report with next-action recommendations derived ONLY from what this run shipped, corrected or
left undecided — an open decision surfaced, a stale premise fixed, a watch worth setting. A short ranked
list: action · whose decision it is · when it becomes urgent. Where a written page ships, mirror it as a
`## Next` section **worded as recommendations with their reasons** — findings, never instructions to
future agents (§2.2 discipline applies to pages as to reports). Nothing self-executes; nothing enters
IDEAS.md unless the owner says "queue it" (normal IDEAS rules then apply). A run with nothing genuinely
open recommends nothing — no forced next.

## Cross-reflection (`--cross`) — one agent reflects on another's session

**Trigger, explicit only:** `/reflect --cross <transcript-path | session-id>`, or the owner accepting
a workflow-end proposal (the delegate skill §5 owns that policy: the head may propose once, cost
declared first, never auto-run). **Target:** a finished session's transcript, or the current
session's transcript as of spawn — the live-write race is declared in the report; the pilot tested
the finished case only (dated caveat: `wiki/developments/cross-reflection-pilot.md`).

**Mechanism.** The head agent spawns a READ-ONLY reflector lane (delegate skill,
`templates/brief-reflector.md`) that applies Steps 1–5 to the target transcript. The lane extracts
the transcript's human turns and assistant prose (tool-result records excluded) to /tmp and reads
that extraction in full, reporting "read k of N turns". **Horizon control** (replaces Step 2's
nonce, which only proves one's *own* session): target file exists and is non-zero; human-turn count
verified against the extraction; coverage declared, never claimed complete.

**Witness ruling.** Proposer ≠ behaving agent, so a transcript-grounded observation (file + line)
IS the external witness Step 3's self-conduct rule demands — cross mode is where unwitnessed
conduct faults become recordable.

**Scope v1:** the head transcript only; lane-internal events appear only as the lane reports
embedded in it. **Output:** findings, never writes — the FULL named candidate table including every
discard with the page that killed it (an aggregate count hides the dedup evidence). Step 5b is not
re-run on cross output — duplicative cost, since the head's re-verify widens instead: dedup checks
AND a re-read of each cited transcript span before the preview. Owner approval stays line-by-line;
the head writes approved items. **`--yes` never applies to cross runs.**

## `--yes` — opt-in auto-approval (off by default)
Set per run (`/reflect --yes`) or as a standing owner setting. It means **writing without waiting, never
writing without telling**: the step 6 table and the step 7 report still appear.

Bounded **by path, not by judgement**:
- **May**: create pages in `wiki/concepts/`, `wiki/entities/`, `wiki/tools/`, `wiki/models/`,
  `wiki/benchmarks/`, `wiki/syntheses/`; **append** to an existing wiki page or to `index.md`.
- **Never**: `wiki/user/` (the owner curates it, CLAUDE.md §1) · `wiki/developments/` and
  `known-issues.md` (a framework surface, and a register append logs nothing, so an unapproved one would
  leave no trace at all) · `CLAUDE.md`, `.claude/**`, `CUSTOMISATION.md`, `MANUAL.md`, `README.md` ·
  anything outside `wiki/` · **rewriting** any existing page — appends only.
- Every auto-approved write **is logged**, so it is always traceable.

> **One stated judgement call.** `wiki/syntheses/` also carries `query` Step 5's ask. The owner's standing
> opt-in *is* the consent that ask exists to collect, given in advance, and it binds **only reflect's own
> writes** — `query` keeps asking when `query` runs. This is stated here in plain sight rather than
> applied silently.

## Hard constraints
- **Explicit trigger only.** Never automatic; passive context never fires it.
- **Never claim a complete sweep.** Only a bounded one, with the boundary named.
- **Never invent a lesson.** Every candidate carries the event it came from.
- **Default narrow.** The unrecorded essentials only, at most five, the rest named in one line. Widen
  only on an explicit instruction; never widen the bar itself.
- **The in-flight lane is not weakened.** This is not a place to defer to: if something is worth filing
  while working, file it then, exactly as now.
- **Approval terminates at the owner.** A subagent may propose; it may never approve.
- Write in British/UK English.
