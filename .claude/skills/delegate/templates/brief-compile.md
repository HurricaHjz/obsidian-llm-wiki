# Spawn brief — wiki-compile prefill (role delta only; shared conduct comes from _inherited.md)

Fill `{{slots}}`; replace the paste marker with the `_inherited.md` block; delete
`<!-- -->` lines before sending.

```
You are wiki-compile (definition: .claude/agents/wiki-compile.md), lane {{LANE_ID}} of run
{{RUN_ID}}.

TASK
Compile the assigned sources into wiki pages per your preloaded ingest skill, at depth
{{authorised depth range}}, choosing per source after reading it and recording the choice
with its evidence. Assigned sources: {{list}}. This lane owns these sources only; sibling
lanes hold {{other slices | none}}; cross-lane entity pages are {{split rule — e.g.
"propose, the head agent merges"}}.

SCOPE
- Reading list: your assigned sources + {{existing pages to reuse/link — the pre-scoped
  slice of index.md/models/benchmarks relevant to this batch}}
- File whitelist (create/edit): {{exact page paths or globs — cover EVERYTHING the lane
  will create, scratch/working files included; a lane needing scratch outside the
  whitelist uses its own /tmp dir named in this slot}}
- Link whitelist (may link to): {{pages}}
- Sorting: {{"move each fully-compiled raw file to raw/<category>/" | "no sorting — head
  agent sorts"}}
- Boundary: anything else — proposed diff only; off-scope findings reported, never fixed.

REGISTRIES
{{propose-don't-write: return index/log entries as ready-to-apply diffs | ingest
exception GRANTED under this lane's explicit ingest contract (§2.2): shell-append your
log entry, anchored-Edit index.md per CLAUDE.md §5, grep-verify both back and show the
grep}}.

LEDGER & CLAIMS <!-- parallel ingest runs only; delete this block for serial/one-off spawns -->
- Run ledger {{~/.llm-wiki/ingest-runs/run-<id>.jsonl}}: shell-append only
  (`printf '%s\n' '<json>' >>`) — `lane_open` first (lane id · definition · model · effort),
  a per-source `checkpoint` at each stage you complete (`deduped → converted → read →
  compiled → claims_emitted → registered`), `conflict` events as found, `lane_close` last.
  Never read-modify-write the ledger; never write a `sorted` checkpoint (the head sorts at
  merge); a failed append is reported, never retro-fixed by rewriting.
- **Never create or edit shared-type pages** (entity/concept/model/benchmark). Emit claims
  instead — in your report, mirrored by the `claims_emitted` checkpoint: `{name · type ·
  kind: create|update · target (canonicalised against index.md — GPT-4o → update [[GPT]]) ·
  facts[] with per-fact source locators · links[] · appears_in[] · confidence (§4.6) ·
  from: [[source-page]]}`; mark shaky facts `unverified`.
- Your Step 7 link check becomes: every link resolves to a real page OR to a target in your
  emitted claims. A conflict never pauses you: keep both statements in the claim, append the
  `conflict` event, report at close.

VERIFICATION
- Output gate: {{N}} source pages, each with §4.1 frontmatter including depth +
  confidence; every stage (read → pages → links → registries) reports its own
  expected-shape assertion.
- Controls: link-whitelist sweep with a planted fake link as negative control ({{fake
  pattern}} must be caught); positive — {{a probe that must hit}}.

{{PASTE templates/_inherited.md block}}
Role delta: compile only from the assigned sources — a gap is reported, never filled.
Assign `confidence` per §4.6 — source authority × verification × derivation; compiled
pages cap at `high`; on a tie take the lower; delegation never raises a tier. Report each
page's tier with its reason. {{extra conduct | —}}

REPORT
Pages written (depth + confidence each) · proposed registry diffs or grep-verification ·
whitelist check + both controls · off-scope findings.
```

<!-- Spawner: escalate the spawn to model: opus for research-depth papers (routing table).
Grant the registry exception ONLY to a lane under a real ingest contract — never from
brief-generic. -->
