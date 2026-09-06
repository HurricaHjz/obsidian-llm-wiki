# Publish-gate allowlist — adjudicated-benign matches

Lines the personal-strings gate may ignore, each with its one-line justification. Rules: an entry
describes the *framework line* that matches (never quotes personal data); entries must themselves be
public-safe (this file ships with the skill); add an entry only after a real adjudication, once,
permanently; a provisional entry (an owner-ruled deferral of a class fix to a named release, 2026-09-06)
names its per-file counts and its expiry release, is removed by the release that fixes its class, and a
hit outside its files or above its counts stays unallowlisted. Format:
`- <matched string> :: <where it matches> :: <why benign>`.

- OneDrive :: CLAUDE.md §6 "external or OneDrive/git sync changes" :: names a sync service generically as a drift cause; no path or account data; public since v0.6.x (adjudicated 2026-07-21)
- OneDrive :: lint SKILL "When to run" — the same generic drift phrase :: identical wording and rationale as the §6 entry (adjudicated 2026-07-22)
- <repo owner handle> :: README + export-template RUNBOOK clone/remote URLs (github.com/<owner>/<repo>) :: the public repository's own address — it cannot be concealed from itself; contains no private data (adjudicated 2026-07-22)
- <licence holder's legal name> :: LICENSE.md copyright line, plus the SPEC tree annotation that describes the MIT licence :: the owner is the public MIT licensor — a licence requires the licensor's name, a deliberate owner decision at v0.1 (log 2026-06-24: "name only in the LICENSE"); no other personal data (adjudicated 2026-07-23)
- <agent name> :: PROVISIONAL, expires at v1.0 — the agent-name-prefixed environment variables, four default paths and a few prose mentions in `delegate/handsoff.py` (31), `delegate/test_handsoff.sh` (33), `delegate/SKILL.md` (5), `delegate/fable-share.py` (2), `delegate/test_fable_share.sh` (1), `setup.sh` (1) and `export-template/payload/setup.sh` (1); a hit in any other file, or above a count, is unallowlisted :: the agent's name is user-space config (`agent_name` in CUSTOMISATION), not personal data; the rename to `LLM_WIKI_*` with a dual read is deferred to v1.0 by owner ruling 2026-09-06 (known-issues, the 2026-09-06 name entry), and that release removes this line
