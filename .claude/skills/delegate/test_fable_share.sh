#!/usr/bin/env bash
# test_fable_share.sh — regression suite for fable-share.py (delegate skill, section 2a metering).
# Builds a synthetic harness project under a fresh mktemp -d and points the meter at it with
# --project-dir, so nothing outside that directory is read or touched. Every expected number is
# computed by hand below and asserted exactly. Each failure mode the script closes has its own leg:
# a planted case that must be caught, and — where a zero can be reported — a clean case that must
# report zero beside its control. The final leg is the stdout-only proof.
# Run:  bash test_fable_share.sh          (last line: PASS n/n or FAIL k/n; exit 0 only when clean)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/fable-share.py"
PY="${PYTHON:-python3}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "FAIL   — $1"; }

F="$(mktemp -d)"
cleanup(){ chmod -R u+w "$F" > /dev/null 2>&1; rm -rf "$F"; }
trap cleanup EXIT
# Snapshot the shipped home's own two files, so the last leg can prove the suite left them alone.
# Only these two are hashed: the rest of the directory may legitimately change under another editor.
HOME_BEFORE="$(shasum "$S" "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------- fixture -------------------
# Head session `sess`: one assistant call before the window, three inside (one of them written
# twice — a placeholder output count then the real one, which must win), one after; two models.
# Lanes L1 (two calls, one of them written twice, plus one call outside the window) and L2 (one).
# Hand-computed head expectations, over the FINAL record per message id inside the window:
#   m1 (100,200,300,1000)  m2 (50,0,5000,250)  m3 (10,20,30,7)
#   output 1000+250+7                                   = 1,257
#   flow   1600 + 5300 + 67                              = 6,967
#   peak   max(600, 5050, 60)                            = 5,050
#   calls 3 · raw assistant records 4 · models a:2 b:1 · efforts (over the 3 calls) max:2 high:1
# Lane expectations: L1 output 300+200 = 500 (the 9,999 call is outside the window), 2 calls,
# 3 records, efforts low:1 max:1 -> 2 distinct; L2 output 120, 1 call, 1 record, 1 distinct.
# Lane total 620 -> share 1257 / (1257+620) = 1257/1877 = 66.96855... -> 67.0%
# Sessions beyond `sess` plant one failure mode each; their expectations sit beside their legs.
mkdir -p "$F/proj/sess/subagents" "$F/proj/sess2/subagents" "$F/tmp/claude-1/proj/sess/tasks" \
         "$F/proj/lonely/subagents" "$F/tmp2/claude-9/proj/lonely/tasks"
"$PY" - "$F" <<'FIXTURE_HEREDOC_END' || { echo "FAIL   — fixture build"; echo "FAIL 0/0"; exit 1; }
import json, os, sys
root = sys.argv[1]
A, B = "claude-test-a", "claude-test-b"

def full(usage):
    return {"input_tokens": usage[0], "cache_creation_input_tokens": usage[1],
            "cache_read_input_tokens": usage[2], "output_tokens": usage[3]}

def asst(ts, mid, model, usage, effort, text=""):
    return {"type": "assistant", "timestamp": ts, "effort": effort,
            "message": {"id": mid, "model": model, "role": "assistant",
                        "content": [{"type": "text", "text": text}],
                        "usage": full(usage)}}

def user(ts, text):
    return {"type": "user", "timestamp": ts, "message": {"role": "user", "content": text}}

head = [
    asst("2026-01-01T00:00:00Z", "m-pre", A, (1000, 0, 0, 999), "max", "before the run"),
    user("2026-01-01T00:01:00Z", "START-RUN-MARKER please do the thing"),
    asst("2026-01-01T00:02:00Z", "m1", A, (100, 200, 300, 5), "max", "step one"),
    asst("2026-01-01T00:03:00Z", "m1", A, (100, 200, 300, 1000), "max", "step one, final"),
    asst("2026-01-01T00:04:00Z", "m2", B, (50, 0, 5000, 250), "max", "step two"),
    asst("2026-01-01T00:05:00Z", "m3", A, (10, 20, 30, 7), "high", "END-RUN-MARKER done"),
    asst("2026-01-01T00:06:00Z", "m-post", A, (1, 1, 1, 5000), "max", "after the run"),
    user("2026-01-01T00:07:00Z", "EMPTY-START-MARKER"),
    user("2026-01-01T00:08:00Z", "EMPTY-END-MARKER"),
]

def lane(agent_id, records):
    out = []
    for rec in records:
        rec = dict(rec)
        rec["agentId"] = agent_id
        rec["isSidechain"] = True
        out.append(rec)
    return out

l1 = lane("L1", [
    asst("2026-01-01T00:02:30Z", "l1a", A, (10, 10, 10, 3), "max"),
    asst("2026-01-01T00:02:40Z", "l1a", A, (10, 10, 10, 300), "max"),
    asst("2026-01-01T00:03:30Z", "l1b", A, (5, 5, 5, 200), "low"),
    asst("2026-01-01T23:00:00Z", "l1z", A, (1, 1, 1, 9999), "max"),
])
l2 = lane("L2", [asst("2026-01-01T00:04:30Z", "l2a", B, (7, 0, 0, 120), "max")])
l3 = lane("L3", [asst("2026-01-01T00:04:40Z", "l3a", B, (3, 0, 0, 44), "max")])

def dump(path, records):
    with open(path, "w", encoding="utf-8") as fh:
        for rec in records:
            fh.write(json.dumps(rec) + "\n")

proj = os.path.join(root, "proj")
dump(os.path.join(proj, "sess.jsonl"), head)
dump(os.path.join(proj, "sess2.jsonl"), head)
dump(os.path.join(proj, "sess", "subagents", "agent-L1.jsonl"), l1)
dump(os.path.join(proj, "sess", "subagents", "agent-L2.jsonl"), l2)
dump(os.path.join(proj, "sess2", "subagents", "agent-L1.jsonl"), l1)

tasks = os.path.join(root, "tmp", "claude-1", "proj", "sess", "tasks")
os.symlink(os.path.join(proj, "sess", "subagents", "agent-L1.jsonl"),
           os.path.join(tasks, "L1sym.output"))          # the observed volatile-to-durable symlink
dump(os.path.join(tasks, "L1copy.output"), l1)            # a real copy: same agent id, different inode
dump(os.path.join(tasks, "L3.output"), l3)                # volatile-only lane, no durable twin
with open(os.path.join(tasks, "junk.output"), "w", encoding="utf-8") as fh:
    fh.write("not a transcript at all\njust text\n")      # observed: some .output files are plain text

# --- a transcript torn by a write in progress: the final line is half a record --------------
dump(os.path.join(proj, "torn.jsonl"),
     [user("2026-01-01T00:00:00Z", "MARK"), asst("2026-01-01T00:01:00Z", "t1", A, (1, 1, 1, 10), "max", "END")])
with open(os.path.join(proj, "torn.jsonl"), "a", encoding="utf-8") as fh:
    fh.write('{"type": "assistant", "timestamp": "2026-01-01T00:0')

# --- the contrast: an unparseable line in the MIDDLE, final line intact ----------------------
with open(os.path.join(proj, "corrupt.jsonl"), "w", encoding="utf-8") as fh:
    fh.write(json.dumps(user("2026-01-01T00:00:00Z", "MARK")) + "\n")
    fh.write('{"type": "assistant", this is not json\n')
    fh.write(json.dumps(asst("2026-01-01T00:01:00Z", "c1", A, (1, 1, 1, 10), "max", "END")) + "\n")

# --- malformed records: a non-object message, an unhashable id, a non-numeric usage value, a
#     partial usage dict, and a record with no message id at all.
#     output 4+10+20+6 = 40 · flow 10+15+23+12 = 60 · peak max(6,5,3,6) = 6 · 4 calls, 4 records
dump(os.path.join(proj, "malformed.jsonl"), [
    user("2026-01-01T00:00:00Z", "MAL-START"),
    {"type": "assistant", "timestamp": "2026-01-01T00:01:00Z", "effort": "max",
     "message": "a message that is not an object"},
    {"type": "assistant", "timestamp": "2026-01-01T00:02:00Z", "effort": "max",
     "message": {"id": ["a", "b"], "model": "m", "usage": full((1, 2, 3, 4))}},
    {"type": "assistant", "timestamp": "2026-01-01T00:03:00Z", "effort": "max",
     "message": {"id": "u1", "model": "m", "usage": {"input_tokens": "lots", "output_tokens": 9}}},
    {"type": "assistant", "timestamp": "2026-01-01T00:04:00Z", "effort": "max",
     "message": {"id": "u2", "model": "m", "usage": {"input_tokens": 5, "output_tokens": 10}}},
    {"type": "assistant", "timestamp": "2026-01-01T00:05:00Z", "effort": "max",
     "message": {"model": "m", "usage": full((1, 1, 1, 20))}},
    asst("2026-01-01T00:06:00Z", "u3", "m", (2, 2, 2, 6), "max", "MAL-END"),
])

# --- a transcript with no timestamps anywhere ------------------------------------------------
dump(os.path.join(proj, "nots.jsonl"), [
    {"type": "user", "message": {"role": "user", "content": "MARK"}},
    {"type": "assistant", "effort": "max",
     "message": {"id": "z", "model": "m", "usage": full((1, 0, 0, 9)),
                 "content": [{"type": "text", "text": "END"}]}}])

# --- a marker that matches more than one message on each side -------------------------------
#     window 0..3 · calls a1 + a2 -> output 30 · flow 36 · peak 3
dump(os.path.join(proj, "dupmark.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK one"),
    asst("2026-01-01T00:01:00Z", "a1", A, (1, 1, 1, 10), "max", "hello"),
    user("2026-01-01T00:02:00Z", "MARK two"),
    asst("2026-01-01T00:03:00Z", "a2", A, (1, 1, 1, 20), "max", "END here"),
    asst("2026-01-01T00:04:00Z", "a3", A, (1, 1, 1, 40), "max", "END again"),
])

# --- an end marker that exists only BEFORE the start marker ----------------------------------
dump(os.path.join(proj, "inverted.jsonl"), [
    asst("2026-01-01T00:00:00Z", "i0", A, (1, 1, 1, 5), "max", "FINISH-HERE"),
    user("2026-01-01T00:01:00Z", "BEGIN-HERE"),
    asst("2026-01-01T00:02:00Z", "i1", A, (1, 1, 1, 7), "max", "tail"),
])

# --- a session whose only lane sits wholly outside the window, beside a symlink loop, a
#     dangling link and a zero-byte .output in the volatile home.
dump(os.path.join(proj, "lonely.jsonl"),
     [user("2026-01-01T00:00:00Z", "MARK"), asst("2026-01-01T00:01:00Z", "x", A, (1, 1, 1, 100), "max", "END")])
dump(os.path.join(proj, "lonely", "subagents", "agent-OUT.jsonl"),
     lane("OUT", [asst("2026-01-01T05:00:00Z", "q", A, (1, 1, 1, 7), "max")]))
# --- a session file that exists but is empty (a session that never wrote a record) -----------
open(os.path.join(proj, "blank.jsonl"), "w", encoding="utf-8").close()

odd = os.path.join(root, "tmp2", "claude-9", "proj", "lonely", "tasks")
os.symlink(os.path.join(odd, "loopB.output"), os.path.join(odd, "loopA.output"))
os.symlink(os.path.join(odd, "loopA.output"), os.path.join(odd, "loopB.output"))
os.symlink(os.path.join(proj, "no-such-file.jsonl"), os.path.join(odd, "dangling.output"))
open(os.path.join(odd, "empty.output"), "w", encoding="utf-8").close()
FIXTURE_HEREDOC_END

BASE=("--project-dir" "$F/proj" "--session" "sess" "--start" "START-RUN-MARKER" "--end" "END-RUN-MARKER")
HEADLINE='fable share: head 1,257 out / 6,967 flow / 5,050 peak'
ERRFILE="$F/stderr.txt"

run(){ OUT="$("$PY" "$S" "$@" 2>&1)"; RC=$?; }
runo(){ OUT="$("$PY" "$S" "$@" 2>"$ERRFILE")"; RC=$?; ERR="$(cat "$ERRFILE")"; }
runx(){ local exe="$1"; shift; OUT="$("$PY" "$exe" "$@" 2>"$ERRFILE")"; RC=$?; ERR="$(cat "$ERRFILE")"; }
has(){ printf '%s\n' "$OUT" | grep -Fq -- "$1"; }
line(){ printf '%s\n' "$OUT" | grep -Fqx -- "$1"; }

# 1 — the head arithmetic, including the placeholder-then-final rule and both window edges.
run "${BASE[@]}" --lanes none
if [ "$RC" = 0 ] && line "$HEADLINE · lanes not scanned · share n/a"; then
  ok "head output/flow/peak: final usage record wins, out-of-window calls excluded"
else no "head output/flow/peak  [exit $RC] $OUT"; fi

# 2 — the head header: call count, deduplication, model split, effort mix (both over the calls).
if [ "$RC" = 0 ] && has "head: 3 calls (4 assistant records) · models claude-test-a:2, claude-test-b:1 · efforts high:1, max:2"; then
  ok "head header reports 3 calls from 4 records, both models, the effort mix over the calls"
else no "head header  [exit $RC] $OUT"; fi

# 3 — --lanes none says why no share is asserted, and prints no lane figure at all.
if [ "$RC" = 0 ] && line "lanes: not scanned (--lanes none), so the share is not asserted" \
   && ! has "control:" && ! has "head data:"; then
  ok "--lanes none states why the share is not asserted; no lane control, no data anomalies"
else no "--lanes none header  [exit $RC] $OUT"; fi

# 4 — the dedup rule is load-bearing: mutating it to keep the FIRST record must change the figure.
#     (Control for leg 1: without this, leg 1 could pass on an unrelated coincidence.)
"$PY" - "$S" "$F/mutant-dedup.py" "$F/mutant-raise.py" <<'MUTATE_HEREDOC_END'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
dedup_old, dedup_new = "        final[key] = row\n", "        final.setdefault(key, row)\n"
raise_old = "    args = ap.parse_args()\n"
raise_new = raise_old + '    raise RuntimeError("planted crash")\n'
assert dedup_old in src and raise_old in src, "mutation anchors drifted"
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(dedup_old, dedup_new, 1))
open(sys.argv[3], "w", encoding="utf-8").write(src.replace(raise_old, raise_new, 1))
MUTATE_HEREDOC_END
MUTOK=$?
runx "$F/mutant-dedup.py" "${BASE[@]}" --lanes none
if [ "$MUTOK" = 0 ] && [ "$RC" = 0 ] && has "head 262 out" && ! has "head 1,257 out"; then
  ok "dedup mutation control: keeping the first record per id yields 262, so leg 1 binds the rule"
else no "dedup mutation control  [mutate $MUTOK] [exit $RC] $OUT"; fi

# 5 — durable lane discovery, totals and share.
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp-empty"
if [ "$RC" = 0 ] && line "$HEADLINE · lanes 620 out (claude-test-a:2, claude-test-b:1) · share 67.0%" \
   && has "lanes: 2 in window · control: 2 candidate transcripts scanned (2 durable, 0 volatile, 2 unique after de-duplication)"; then
  ok "lane discovery in the durable home: totals, model split, share, scan control"
else no "durable lane discovery  [exit $RC] $OUT"; fi

# 6 — per-lane attribution lines, including each lane's own window filter and effort count.
if [ "$RC" = 0 ] \
   && line "  lane L1: models claude-test-a:2 · 2 calls (3 records) · 500 out · efforts 2 (low:1, max:1)" \
   && line "  lane L2: models claude-test-b:1 · 1 call (1 record) · 120 out · efforts 1 (max:1)"; then
  ok "per-lane lines: models, calls, records, output, distinct effort values"
else no "per-lane lines  [exit $RC] $OUT"; fi

# 7 — explicit globs replace discovery, and the scan control says so (0 durable, 0 volatile).
run --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
    --lanes "$F/proj/sess/subagents/agent-L*.jsonl"
if [ "$RC" = 0 ] && line "$HEADLINE · lanes 620 out (claude-test-a:2, claude-test-b:1) · share 67.0%" \
   && has "lanes: 2 in window · control: 2 candidate transcripts scanned (0 durable, 0 volatile, 2 unique after de-duplication)"; then
  ok "explicit lane globs meter the same figures and report their own scan control"
else no "explicit lane globs  [exit $RC] $OUT"; fi

# 8 — both lane homes, de-duplicated by content identity (symlink by path, copy by agent id),
#     with a plain-text .output tolerated. Lane total 500+120+44 = 664 -> 1257/1921 = 65.4%.
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp"
if [ "$RC" = 0 ] && line "$HEADLINE · lanes 664 out (claude-test-a:2, claude-test-b:2) · share 65.4%" \
   && has "lanes: 3 in window · control: 6 candidate transcripts scanned (2 durable, 4 volatile, 5 unique after de-duplication) · 1 dropped as a duplicate identity" \
   && line "  lane L3: models claude-test-b:1 · 1 call (1 record) · 44 out · efforts 1 (max:1)"; then
  ok "volatile home scanned; symlink and copied duplicates dropped and counted; junk .output tolerated"
else no "volatile home and de-duplication  [exit $RC] $OUT"; fi

# 9 — the baseline delta line: negative, positive, and a baseline of zero (not treated as absent).
run "${BASE[@]}" --lanes none --baseline-output 2000
if [ "$RC" = 0 ] && line "head output delta vs baseline: -743"; then
  ok "baseline delta, negative"; else no "baseline delta negative  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes none --baseline-output 1000
if [ "$RC" = 0 ] && line "head output delta vs baseline: +257"; then
  ok "baseline delta, positive"; else no "baseline delta positive  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes none --baseline-output 0
if [ "$RC" = 0 ] && line "head output delta vs baseline: +1,257"; then
  ok "baseline delta with --baseline-output 0: the whole head output, not a suppressed line"
else no "baseline delta zero  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes none
if [ "$RC" = 0 ] && ! has "delta vs baseline"; then
  ok "no delta line without --baseline-output (control for the three legs above)"
else no "delta line suppressed  [exit $RC] $OUT"; fi

# 10 — a marker that matches nothing is a broken premise, never a number.
run --project-dir "$F/proj" --session sess --start "NO-SUCH-MARKER" --end "END-RUN-MARKER" --lanes none
if [ "$RC" = 2 ] && line "fable share: unmetered (start marker not found: NO-SUCH-MARKER)" && ! has "head 1,257"; then
  ok "a missing start marker prints unmetered and exits 2"
else no "missing start marker  [exit $RC] $OUT"; fi
run "${BASE[@]/END-RUN-MARKER/NO-SUCH-END}" --lanes none
if [ "$RC" = 2 ] && line "fable share: unmetered (end marker not found: NO-SUCH-END)"; then
  ok "a missing end marker prints unmetered and exits 2"
else no "missing end marker  [exit $RC] $OUT"; fi

# 11 — a missing session transcript, and a missing project directory, are broken premises; the
#      second diagnoses a wrong derivation by naming the sibling directory that holds the session.
run --project-dir "$F/proj" --session no-such-session --lanes none
if [ "$RC" = 2 ] && has "fable share: unmetered (session transcript not found:" \
   && has "no sibling directory holds it either"; then
  ok "a missing session transcript prints unmetered, exits 2, and says no sibling holds it"
else no "missing session transcript  [exit $RC] $OUT"; fi
run --project-dir "$F/proj-not-here" --session sess --lanes none
if [ "$RC" = 2 ] && has "fable share: unmetered (project directory not found (given):" \
   && has "$F/proj holds that session; pass it as --project-dir"; then
  ok "a missing project directory names the sibling that does hold the session"
else no "missing project directory  [exit $RC] $OUT"; fi

# 11b — a session file that exists but holds nothing is a broken premise, with its line count.
run --project-dir "$F/proj" --session blank --lanes none
if [ "$RC" = 2 ] && has "fable share: unmetered (session transcript holds no parseable records:" \
   && has "(0 unparseable line(s))"; then
  ok "an empty session transcript prints unmetered and exits 2, reporting zero unparseable lines"
else no "empty session transcript  [exit $RC] $OUT"; fi

# 12 — a window holding no assistant record is a broken premise (the end marker here matches a
#      user record, so this also exercises the any-record-type fallback).
run --project-dir "$F/proj" --session sess --start "EMPTY-START-MARKER" --end "EMPTY-END-MARKER" --lanes none
if [ "$RC" = 2 ] && has "fable share: unmetered (no assistant records with usage in the window"; then
  ok "an empty window prints unmetered and exits 2"
else no "empty window  [exit $RC] $OUT"; fi

# 13 — expect-lanes: mismatch fails the premise, match passes it, a higher count fails, and 0
#      is an assertion in its own right rather than an absent value.
run --project-dir "$F/proj" --session sess2 --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
    --lanes auto --tmp-root "$F/tmp-empty" --expect-lanes 2
if [ "$RC" = 2 ] && line "fable share: unmetered (expected 2 lane transcripts in the window, found 1)"; then
  ok "expect-lanes 2 with one lane present prints unmetered and exits 2"
else no "expect-lanes mismatch  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp-empty" --expect-lanes 2
if [ "$RC" = 0 ] && has "share 67.0%" && has "lanes: 2 in window (matches --expect-lanes 2)"; then
  ok "expect-lanes 2 with two lanes present meters normally and says the check ran (flag control)"
else no "expect-lanes match  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp-empty" --expect-lanes 5
if [ "$RC" = 2 ] && line "fable share: unmetered (expected 5 lane transcripts in the window, found 2)"; then
  ok "expect-lanes higher than the number found prints unmetered and exits 2"
else no "expect-lanes too high  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp-empty" --expect-lanes 0
if [ "$RC" = 2 ] && line "fable share: unmetered (expected 0 lane transcripts in the window, found 2)"; then
  ok "expect-lanes 0 with lanes present prints unmetered and exits 2"
else no "expect-lanes 0 with lanes present  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes none --expect-lanes 0
if [ "$RC" = 2 ] && line "fable share: unmetered (--expect-lanes 0 cannot be checked with --lanes none)"; then
  ok "expect-lanes 0 alongside --lanes none is a contradiction, not a silent pass"
else no "expect-lanes 0 with --lanes none  [exit $RC] $OUT"; fi

# 14 — a lane scan that reaches no readable transcript is a broken premise, because a lane total
#      of zero would otherwise be a claim with a zero control behind it. --expect-lanes 0 is the
#      deliberate assertion that there were none, and then the share is asserted.
run --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
    --lanes "$F/nothing/*.jsonl"
if [ "$RC" = 2 ] && has "fable share: unmetered (no readable lane transcript found (0 candidate(s), 0 skipped) under:" \
   && has "--expect-lanes 0 to assert there were none" && ! has "share 100.0%"; then
  ok "an empty lane scan prints unmetered rather than a 100% share off a zero control"
else no "empty lane scan  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
    --lanes "$F/nothing/*.jsonl" --expect-lanes 0
if [ "$RC" = 0 ] && line "$HEADLINE · lanes 0 out (none) · share 100.0%" \
   && has "lanes: 0 in window (matches --expect-lanes 0)"; then
  ok "--expect-lanes 0 turns the same empty scan into an asserted 100% share"
else no "empty lane scan with --expect-lanes 0  [exit $RC] $OUT"; fi

# 15 — candidates that cannot be transcripts (a symlink loop, a dangling link) are skipped and
#      counted; a zero-byte .output parses to nothing; a lane wholly outside the window is not
#      counted, and the control says how many candidates had no records in the window.
run --project-dir "$F/proj" --session lonely --start MARK --end END --lanes auto --tmp-root "$F/tmp2"
if [ "$RC" = 0 ] && has "control: 5 candidate transcripts scanned (1 durable, 4 volatile, 2 unique after de-duplication) · 3 skipped (not a regular file)"; then
  ok "a symlink loop and a dangling link are skipped as candidates and counted, never crash"
else no "symlink loop and dangling link  [exit $RC] $OUT"; fi
if [ "$RC" = 0 ] && has "· 2 with no records in the window" \
   && line "fable share: head 100 out / 103 flow / 3 peak · lanes 0 out (none) · share 100.0%"; then
  ok "a zero-byte .output and a lane wholly outside the window contribute nothing, and are counted"
else no "out-of-window lane and zero-byte output  [exit $RC] $OUT"; fi

# 16 — a transcript torn by a write in progress: the figures still meter, the count is reported,
#      and the final-line wording appears only when the final line is the torn one.
run --project-dir "$F/proj" --session torn --start MARK --end END --lanes none
if [ "$RC" = 0 ] && has "fable share: head 10 out / 13 flow / 3 peak" \
   && has "· 1 session line unparseable (the final one: a transcript read mid-write looks like this)"; then
  ok "a truncated final line is tolerated, metered and named as a mid-write read"
else no "torn final line  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session corrupt --start MARK --end END --lanes none
if [ "$RC" = 0 ] && has "fable share: head 10 out / 13 flow / 3 peak" \
   && has "· 1 session line unparseable" && ! has "the final one"; then
  ok "an unparseable line in the middle is counted without the mid-write wording (control)"
else no "mid-file corrupt line  [exit $RC] $OUT"; fi

# 17 — malformed records: none crashes, each is counted, and the clean fixture stays silent.
run --project-dir "$F/proj" --session malformed --start MAL-START --end MAL-END --lanes none
if [ "$RC" = 0 ] && line "fable share: head 40 out / 60 flow / 6 peak · lanes not scanned · share n/a"; then
  ok "a non-object message, an unhashable id and a non-numeric usage value meter without a crash"
else no "malformed records  [exit $RC] $OUT"; fi
if [ "$RC" = 0 ] && has "head: 4 calls (4 assistant records) · models m:4 · efforts max:4"; then
  ok "an id-less record counts as its own call; the non-object message and unusable usage do not"
else no "malformed record counts  [exit $RC] $OUT"; fi
if [ "$RC" = 0 ] && line "head data: 1 assistant record with unusable usage skipped · 1 call missing a usage field (counted as 0)"; then
  ok "unusable and partial usage are reported rather than silently summed"
else no "malformed record reporting  [exit $RC] $OUT"; fi

# 18 — timestamps: a transcript with none still meters the head, but cannot select lane records.
run --project-dir "$F/proj" --session nots --start MARK --end END --lanes none
if [ "$RC" = 0 ] && has "no timestamp -> no timestamp" \
   && line "fable share: head 9 out / 10 flow / 1 peak · lanes not scanned · share n/a"; then
  ok "a transcript with no timestamps meters the head and says the window has none"
else no "no timestamps, head  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session nots --start MARK --end END --lanes auto
if [ "$RC" = 2 ] && line "fable share: unmetered (the window carries no timestamps, so lane records cannot be selected)"; then
  ok "with no timestamps, lane selection is a broken premise rather than a guess"
else no "no timestamps, lanes  [exit $RC] $OUT"; fi

# 19 — a marker matching more than once takes the first match and reports the others on both sides.
run --project-dir "$F/proj" --session dupmark --start MARK --end END --lanes none
if [ "$RC" = 0 ] && has 'start = marker "MARK" in a user message · 1 further match later, first taken' \
   && has 'end = marker "END" in an assistant reply · 1 further match later, first taken' \
   && line "fable share: head 30 out / 36 flow / 3 peak · lanes not scanned · share n/a"; then
  ok "a repeated marker reports its further matches instead of silently shifting the window"
else no "repeated markers  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes none
if [ "$RC" = 0 ] && ! has "further match"; then
  ok "a marker matching once reports no further matches (control for the leg above)"
else no "single-match marker  [exit $RC] $OUT"; fi

# 20 — an inverted window, by marker and by timestamp.
run --project-dir "$F/proj" --session inverted --start BEGIN-HERE --end FINISH-HERE --lanes none
if [ "$RC" = 2 ] && line "fable share: unmetered (end marker matches only at or before the start bound (1 earlier match): FINISH-HERE)"; then
  ok "an end marker occurring only before the start bound is diagnosed, not reported as missing"
else no "end marker before start  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session dupmark --start "2026-01-01T00:03:00Z" --end "2026-01-01T00:01:00Z" --lanes none
if [ "$RC" = 2 ] && line "fable share: unmetered (the end bound precedes the start bound)"; then
  ok "an inverted timestamp window prints unmetered and exits 2"
else no "inverted timestamp window  [exit $RC] $OUT"; fi

# 21 — flag hygiene: a negative baseline or expectation cannot yield a meaningful figure, and the
#      session id is a bare id (a pasted file name is accepted, a path is not).
run "${BASE[@]}" --lanes none --baseline-output -50
if [ "$RC" = 2 ] && line "fable share: unmetered (--baseline-output cannot be negative: -50)"; then
  ok "a negative baseline is refused instead of printing a nonsense delta"
else no "negative baseline  [exit $RC] $OUT"; fi
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp-empty" --expect-lanes -1
if [ "$RC" = 2 ] && line "fable share: unmetered (--expect-lanes cannot be negative: -1)"; then
  ok "a negative lane expectation is refused"
else no "negative expect-lanes  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session sess.jsonl --start "START-RUN-MARKER" --end "END-RUN-MARKER" --lanes none
if [ "$RC" = 0 ] && line "$HEADLINE · lanes not scanned · share n/a"; then
  ok "a session given as a pasted transcript file name resolves to the same figures"
else no "session with .jsonl suffix  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session "sub/sess" --lanes none
if [ "$RC" = 2 ] && has "fable share: unmetered (session must be a bare session id, not a path:"; then
  ok "a session given as a path is refused"
else no "session as a path  [exit $RC] $OUT"; fi

# 22 — the project-directory derivation: one hyphen per character outside [A-Za-z0-9-], checked
#      against an independent shell derivation of the fixture path (the positive control) and
#      against a path carrying a space, non-ASCII letters and an @.
DERIVED="$("$PY" - "$S" "$F" <<'DERIVE_HEREDOC_END'
import importlib.util, sys
sys.dont_write_bytecode = True     # importing the script must not leave a cache in its shipped home
spec = importlib.util.spec_from_file_location("fable_share_under_test", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.derive_project_dir(sys.argv[2]))
print(mod.derive_project_dir("/a b/Ünïcodé/@vault"))
DERIVE_HEREDOC_END
)"
SHELL_SLUG="$(printf '%s' "$F" | sed 's/[^A-Za-z0-9-]/-/g')"
PY_SLUG="$(printf '%s\n' "$DERIVED" | sed -n '1p')"
UNI_SLUG="$(printf '%s\n' "$DERIVED" | sed -n '2p')"
if [ -n "$SHELL_SLUG" ] && [ "$PY_SLUG" = "$HOME/.claude/projects/$SHELL_SLUG" ] \
   && [ "$UNI_SLUG" = "$HOME/.claude/projects/-a-b--n-cod---vault" ]; then
  ok "project-dir derivation: hyphen per non-alphanumeric, unicode and spaces included (control: an independent shell derivation of the fixture path agrees)"
else no "project-dir derivation  [shell $SHELL_SLUG] [py $PY_SLUG] [uni $UNI_SLUG]"; fi

# 23 — the JSON structure the head consumes.
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp-empty" --format json
if [ "$RC" = 0 ] && printf '%s' "$OUT" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
assert d["head"]["output"] == 1257, d["head"]
assert d["head"]["flow"] == 6967 and d["head"]["peak"] == 5050 and d["head"]["calls"] == 3
assert d["head"]["unusable_usage_records"] == 0 and d["head"]["partial_usage_calls"] == 0
assert d["lane_totals"]["output"] == 620 and d["lane_totals"]["lanes"] == 2
assert abs(d["share"] - 1257 / 1877) < 1e-12, d["share"]
assert d["share_basis"] == "head output / (head + lane output)", d["share_basis"]
assert [l["name"] for l in d["lanes"]] == ["L1", "L2"]
assert d["lanes"][0]["distinct_efforts"] == 2 and d["lanes"][1]["distinct_efforts"] == 1
assert d["lanes"][0]["unparseable_lines"] == 0 and d["lanes"][0]["tail_truncated"] is False
assert d["session_tail_truncated"] is False and d["unparseable_session_lines"] == 0
assert d["window"]["start_marker_matches"] == 1 and d["window"]["end_marker_matches"] == 1
assert d["lane_scan"]["skipped"] == 0 and d["lane_scan"]["no_window_records"] == 0
assert d["line"].endswith("share 67.0%"), d["line"]
'; then ok "JSON format carries the same figures, per-lane detail, the diagnostics and the summary line"
else no "JSON format  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session malformed --start MAL-START --end MAL-END --lanes none --format json
if [ "$RC" = 0 ] && printf '%s' "$OUT" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
assert d["head"]["unusable_usage_records"] == 1 and d["head"]["partial_usage_calls"] == 1, d["head"]
assert d["share"] is None and d["share_basis"].startswith("not asserted"), d["share_basis"]
'; then ok "JSON carries the malformed-record counts and says why no share is asserted"
else no "JSON diagnostics  [exit $RC] $OUT"; fi

# 24 — JSON mode still refuses to print a number on a broken premise.
run --project-dir "$F/proj" --session sess --start "NO-SUCH-MARKER" --lanes none --format json
if [ "$RC" = 2 ] && line "fable share: unmetered (start marker not found: NO-SUCH-MARKER)"; then
  ok "JSON mode prints the unmetered line and exits 2 on a broken premise"
else no "JSON broken premise  [exit $RC] $OUT"; fi

# 25 — the summary lines are byte-exact in shape, in every mode.
shape(){ printf '%s\n' "$OUT" | "$PY" -c '
import re, sys
want = sys.argv[1]
pats = {
 "lanes": r"^fable share: head [\d,]+ out / [\d,]+ flow / [\d,]+ peak · lanes [\d,]+ out \([^)]+\) · share (\d+\.\d%|n/a)$",
 "none":  r"^fable share: head [\d,]+ out / [\d,]+ flow / [\d,]+ peak · lanes not scanned · share n/a$",
 "delta": r"^head output delta vs baseline: [+-][\d,]+$",
 "unmet": r"^fable share: unmetered \(.+\)$",
}
lines = sys.stdin.read().splitlines()
sys.exit(0 if any(re.match(pats[want], l) for l in lines) else 1)
' "$1"; }
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp" --baseline-output 100
S1=0; shape lanes || S1=1; shape delta || S1=1
run "${BASE[@]}" --lanes none
shape none || S1=1
run --project-dir "$F/proj" --session sess --start "NO-SUCH-MARKER" --lanes none
shape unmet || S1=1
run "${BASE[@]}" --lanes none
NEG=0; shape lanes && NEG=1     # control: the scanned-lane shape must NOT match the --lanes none line
if [ "$S1" = 0 ] && [ "$NEG" = 0 ]; then
  ok "summary lines match their exact shapes in all three modes (control: the shapes discriminate)"
else no "summary line shapes  [shapes $S1] [discriminates $NEG] $OUT"; fi

# 26 — every broken premise prints exactly one stdout line, in the unmetered shape, with no figure.
premise_bad(){
  runo "$@"
  local n; n=$(printf '%s\n' "$OUT" | grep -c .)
  [ "$RC" = 2 ] && [ "$n" = 1 ] \
    && printf '%s\n' "$OUT" | grep -Eq '^fable share: unmetered \(.+\)$' \
    && ! printf '%s\n' "$OUT" | grep -q 'fable share: head'
}
BAD=0
check(){ if premise_bad "$@"; then :; else BAD=$((BAD+1)); echo "       not a clean premise failure: [$*]"; fi; }
check --project-dir "$F/proj" --session sess --start NO-SUCH --lanes none
check --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end NO-SUCH --lanes none
check --project-dir "$F/proj" --session nope --lanes none
check --project-dir "$F/proj" --session blank --lanes none
check --project-dir "$F/proj-not-here" --session sess --lanes none
check --project-dir "$F/proj" --session sess --start EMPTY-START-MARKER --end EMPTY-END-MARKER --lanes none
check --project-dir "$F/proj" --session nots --start MARK --end END --lanes auto
check --project-dir "$F/proj" --session inverted --start BEGIN-HERE --end FINISH-HERE --lanes none
check --project-dir "$F/proj" --session dupmark --start "2026-01-01T00:03:00Z" --end "2026-01-01T00:01:00Z" --lanes none
check --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" --lanes "$F/nothing/*.jsonl"
check --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" --lanes none --expect-lanes 1
check --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" --lanes none --baseline-output -1
check --project-dir "$F/proj" --session "sub/sess" --lanes none
check --project-dir "$F/proj" --session sess --start "2026-13-45 not a date" --lanes none
CTRL=1; premise_bad "${BASE[@]}" --lanes none && CTRL=0
if [ "$BAD" = 0 ] && [ "$CTRL" = 1 ]; then
  ok "14 broken premises each print one unmetered line with no figure (control: a metered run fails the same check)"
else no "premise failure shape  [bad $BAD] [control $CTRL]"; fi

# 27 — the belt: an unforeseen error is reported as a broken premise, never as a traceback on
#      stdout and never as a metered run.
runx "$F/mutant-raise.py" "${BASE[@]}" --lanes none
if [ "$RC" = 2 ] && line "fable share: unmetered (unexpected error, see stderr: RuntimeError: planted crash)" \
   && printf '%s\n' "$ERR" | grep -q "Traceback"; then
  ok "a planted crash prints the unmetered line on stdout with its traceback on stderr, exit 2"
else no "unexpected-error belt  [exit $RC] $OUT"; fi

# 28 — stdout-only proof: run every mode against read-only copies of the fixture AND of the
#      script home, comparing checksum manifests before and after, then grep the source for the
#      write patterns the shared spec bans.
RO="$F/ro"; ROHOME="$F/rohome"
mkdir -p "$RO" "$ROHOME"
cp -R "$F/proj" "$RO/proj"
cp "$S" "$ROHOME/fable-share.py"
manifest(){ find "$1" -type f -exec shasum {} \; | sort; }
# Positive control for the comparison itself: a read-only tree cannot record a rejected write,
# so prove on a writable scratch copy that the manifest actually notices a changed byte.
SCRATCH="$F/scratch"; mkdir -p "$SCRATCH"; printf 'a\n' > "$SCRATCH/probe"
M1="$(manifest "$SCRATCH")"; printf 'b\n' > "$SCRATCH/probe"; M2="$(manifest "$SCRATCH")"
if [ -n "$M1" ] && [ "$M1" != "$M2" ]; then ok "manifest comparison detects a changed byte (control for the leg below)"
else no "manifest comparison is insensitive — the stdout-only leg below would be vacuous"; fi
chmod -R a-w "$RO" "$ROHOME"
BEFORE="$(manifest "$RO"; manifest "$ROHOME")"
RM=("$PY" "$ROHOME/fable-share.py" --project-dir "$RO/proj")
"${RM[@]}" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
      --lanes auto --tmp-root "$F/tmp-empty" > /dev/null 2>&1
"${RM[@]}" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
      --lanes none --format json --baseline-output 10 > /dev/null 2>&1
"${RM[@]}" --session malformed --start MAL-START --end MAL-END --lanes none > /dev/null 2>&1
"${RM[@]}" --session torn --start MARK --end END --lanes none > /dev/null 2>&1
"${RM[@]}" --session lonely --start MARK --end END --lanes auto --tmp-root "$F/tmp2" > /dev/null 2>&1
"${RM[@]}" --session nope --lanes none > /dev/null 2>&1
"$PY" "$ROHOME/fable-share.py" --project-dir "$RO/proj-not-here" --session sess --lanes none > /dev/null 2>&1
AFTER="$(manifest "$RO"; manifest "$ROHOME")"
WRITES=0
for pat in 'open\([^)]*['"'"'"][wax]' '\bwrite_text\b' '\bwritelines\b' '\.write\(' \
           '\bos\.(remove|unlink|rename|replace|mkdir|makedirs|rmdir)\b' '\bshutil\.' \
           '\b(subprocess|Popen)\b' '\bos\.system\b'; do
  if grep -nE -- "$pat" "$S" | grep -v '^[0-9]*: *#'; then WRITES=$((WRITES+1)); fi
done
CONTROL="$(grep -cE -- 'open\(' "$S")"
if [ "$BEFORE" = "$AFTER" ] && [ "$WRITES" = 0 ] && [ "$CONTROL" -gt 0 ] && [ -n "$BEFORE" ]; then
  ok "stdout-only: read-only fixture and script home unchanged after seven runs; no write pattern in the source (control: $CONTROL read-mode open calls found by the same grep)"
else no "stdout-only proof  [manifest changed: $([ "$BEFORE" = "$AFTER" ] && echo no || echo yes); write patterns: $WRITES; control opens: $CONTROL]"; fi
# The write-pattern grep must itself be able to fail: plant every banned pattern in a copy.
PLANT="$F/planted.py"
{ cat "$S"; printf '\n# planted for the control below\nopen("x", "w")\nos.remove("x")\nshutil.copy("x", "y")\nsubprocess.run(["true"])\n'; } > "$PLANT"
PWRITES=0
for pat in 'open\([^)]*['"'"'"][wax]' '\bos\.(remove|unlink|rename|replace|mkdir|makedirs|rmdir)\b' \
           '\bshutil\.' '\b(subprocess|Popen)\b'; do
  if grep -qnE -- "$pat" "$PLANT"; then PWRITES=$((PWRITES+1)); fi
done
if [ "$PWRITES" = 4 ]; then
  ok "write-pattern grep control: all four planted write patterns are caught in a copy of the source"
else no "write-pattern grep is blind  [caught $PWRITES of 4]"; fi
chmod -R u+w "$RO" "$ROHOME"

# 29 — the suite itself leaves the shipped home alone: the two files are byte-identical and no
#      bytecode cache appeared (importing the script for leg 22 would write one by default).
mkdir -p "$F/fakehome/__pycache__"                     # control: the -d test must discriminate
HOME_AFTER="$(shasum "$S" "${BASH_SOURCE[0]}")"
if [ -n "$HOME_BEFORE" ] && [ "$HOME_BEFORE" = "$HOME_AFTER" ] && [ ! -d "$HERE/__pycache__" ] \
   && [ -d "$F/fakehome/__pycache__" ]; then
  ok "the suite leaves its own home untouched: both files unchanged, no bytecode cache (controls: the byte-change control above, and a planted __pycache__ the same test does see)"
else no "suite wrote into the script home  [changed: $([ "$HOME_BEFORE" = "$HOME_AFTER" ] && echo no || echo yes); pycache: $([ -d "$HERE/__pycache__" ] && echo yes || echo no)]"; fi

TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then echo "PASS $PASS/$TOTAL"; else echo "FAIL $FAIL/$TOTAL"; exit 1; fi
