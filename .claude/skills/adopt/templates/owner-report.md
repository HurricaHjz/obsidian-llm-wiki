# /adopt — owner report (step 2)

Fill every cell from the fingerprint and the assessment; one row per add-on (a skill collection gets one row per picked skill, the parent pinned once). The owner approves, amends the level, or stops here (`--assess-only`).

| What | Channel | Level (reason) | Always-on cost | Risks | What changes in the system | Acceptance probe |
|---|---|---|---|---|---|---|
| {{what}} | {{channel}} | {{level}} — {{reason}} | {{cost}} | {{risks}} | {{changes}} | {{probe}} |

**Columns.**
- **What** — the add-on in one clause: name, publisher, pin (commit or tag), licence.
- **Channel** — `user-level skill` (symlink or wrapper under `~/.claude/skills`), `plugin` (floating; a `hooks.json` reaches every session), `CLI tool` (pin-by-class), `connector` (rows only), or `knowledge only` (the README is ingested, nothing installed).
- **Level (reason)** — `auto` · `propose-first` · `by-name`, the most restrictive clause winning: the fingerprint's mechanical floor (a hook or a network primitive in code → at least `propose-first`), then the assignment rule (`by-name` when it substitutes for a vault workflow's job or runs arbitrary user code; `propose-first` when a run has an external effect, or the owner wants it offered; `auto` when it serves inside a vault workflow). Token cost never decides a level.
- **Always-on cost** — the description bytes the listing carries per request (`auto`: the upstream description; `propose-first`: the wrapper's short description; `by-name`: 0 B).
- **Risks** — exec and network primitives by file class, hooks, licence terms (a non-commercial licence is referenced in place, never copied), an upstream working-directory or write habit, prompt-shaped files that must stay data.
- **What changes in the system** — any of: a **tool row** (the register, a tool page, a source page) · an **instinct** (a standing behaviour worth adopting → a proposed CUSTOMISATION or role delta, gated as today) · an **upgrade hint** (a framework idea → a `wiki/developments/` note; IDEAS.md only on "queue it") · **knowledge** (ingest the README; the residual when nothing else applies).
- **Acceptance probe** — the scripted legs (`adopt_acceptance.py`) plus the head's headless probes: listing present for `auto` and `propose-first`, absent for `by-name`; `/name` answers a fact only the upstream file holds.

**Decision asked of the owner:** approve as proposed · amend the level (say which) · stop after the assessment.
