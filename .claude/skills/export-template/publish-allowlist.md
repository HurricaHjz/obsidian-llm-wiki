# Publish-gate allowlist — adjudicated-benign matches

Lines the personal-strings gate may ignore, each with its one-line justification. Rules: an entry
describes the *framework line* that matches (never quotes personal data); entries must themselves be
public-safe (this file ships with the skill); add an entry only after a real adjudication, once,
permanently. Format: `- <matched string> :: <where it matches> :: <why benign>`.

- OneDrive :: CLAUDE.md §6 "external or OneDrive/git sync changes" :: names a sync service generically as a drift cause; no path or account data; public since v0.6.x (adjudicated 2026-07-21)
- OneDrive :: lint SKILL "When to run" — the same generic drift phrase :: identical wording and rationale as the §6 entry (adjudicated 2026-07-22)
- <repo owner handle> :: README + export-template RUNBOOK clone/remote URLs (github.com/<owner>/<repo>) :: the public repository's own address — it cannot be concealed from itself; contains no private data (adjudicated 2026-07-22)
- <licence holder's legal name> :: LICENSE.md copyright line, plus the RUNBOOK §A note and the SPEC tree annotation that describe the MIT licence :: the owner is the public MIT licensor — a licence requires the licensor's name, a deliberate owner decision at v0.1 (log 2026-06-24: "name only in the LICENSE"); no other personal data (adjudicated 2026-07-23)
