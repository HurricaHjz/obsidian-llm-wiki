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
# Snapshot the shipped home's own three files, so the last leg can prove the suite left them
# alone. Only these are hashed: the rest of the directory may legitimately change under
# another editor.
HOME_BEFORE="$(shasum "$S" "$HERE/prices.json" "${BASH_SOURCE[0]}")"

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
"$PY" - "$F" "$HERE" <<'FIXTURE_HEREDOC_END' || { echo "FAIL   — fixture build"; echo "FAIL 0/0"; exit 1; }
import json, os, sys
root = sys.argv[1]
A, B = "claude-test-fable-a", "claude-test-opus-b"

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
     "message": {"id": ["a", "b"], "model": "claude-test-sonnet-m", "usage": full((1, 2, 3, 4))}},
    {"type": "assistant", "timestamp": "2026-01-01T00:03:00Z", "effort": "max",
     "message": {"id": "u1", "model": "claude-test-sonnet-m", "usage": {"input_tokens": "lots", "output_tokens": 9}}},
    {"type": "assistant", "timestamp": "2026-01-01T00:04:00Z", "effort": "max",
     "message": {"id": "u2", "model": "claude-test-sonnet-m", "usage": {"input_tokens": 5, "output_tokens": 10}}},
    {"type": "assistant", "timestamp": "2026-01-01T00:05:00Z", "effort": "max",
     "message": {"model": "claude-test-sonnet-m", "usage": full((1, 1, 1, 20))}},
    asst("2026-01-01T00:06:00Z", "u3", "claude-test-sonnet-m", (2, 2, 2, 6), "max", "MAL-END"),
])

# --- a transcript with no timestamps anywhere ------------------------------------------------
dump(os.path.join(proj, "nots.jsonl"), [
    {"type": "user", "message": {"role": "user", "content": "MARK"}},
    {"type": "assistant", "effort": "max",
     "message": {"id": "z", "model": "claude-test-sonnet-m", "usage": full((1, 0, 0, 9)),
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

# ============================ billing fixtures ==============================================
# Everything below feeds the billed line. The price table under test is the shipped
# prices.json (fable $10/$50, read 0.025x; opus $5/$25, read 0.1x; writes 1.25x at 5 minutes
# and 2x at 1 hour), so every model id here carries a family substring; the one that must not
# be billable lives in its own session.
FAB, OPU = "claude-test-fable-a", "claude-test-opus-b"

def usage(inp, w5, w1, read, out, sub=True):
    """A usage dict with the two cache_creation tier fields, or without them (the fallback)."""
    block = {"input_tokens": inp, "cache_creation_input_tokens": w5 + w1,
             "cache_read_input_tokens": read, "output_tokens": out}
    if sub:
        block["cache_creation"] = {"ephemeral_5m_input_tokens": w5,
                                   "ephemeral_1h_input_tokens": w1}
    return block

def call(ts, mid, model, use, effort="max", text="", blocks=None):
    content = [{"type": "text", "text": text}] if blocks is None else blocks
    return {"type": "assistant", "timestamp": ts, "effort": effort,
            "message": {"id": mid, "model": model, "role": "assistant",
                        "content": content, "usage": use}}

def tool(name, ident):
    return {"type": "tool_use", "id": ident, "name": name, "input": {}}

# --- tiered: 5-minute and 1-hour writes mixed, plus one record with no tier sub-object -----
#     t1 fable  in 1,000 · read 400,000 · w5 150,000 · w1 50,000 · out 50,000
#        0.01 + 400000*10*0.025/1e6 (0.10) + 150000*10*1.25/1e6 (1.875) + 50000*10*2/1e6 (1.00)
#        + 50000*50/1e6 (2.50)                                                     = 5.485
#     t2 opus   in 500 · read 800,000 · w5 0 · w1 100,000 · out 20,000
#        0.0025 + 800000*5*0.1/1e6 (0.40) + 100000*5*2/1e6 (1.00) + 20000*25/1e6 (0.50) = 1.9025
#     t3 fable, NO cache_creation sub-object: its 80,000 write falls back to the 5-minute rate
#        0.001 + 80000*10*1.25/1e6 (1.00) + 100*50/1e6 (0.005)                     = 1.006
#     fable 5.485 + 1.006 = 6.491 -> $6.49 · opus $1.90 · head 8.3935 -> $8.39
#     No call rewrites the previous context (100,000 < 0.9*601,000; 80,000 < 0.9*900,500).
dump(os.path.join(proj, "tiered.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "t1", FAB, usage(1000, 150000, 50000, 400000, 50000)),
    call("2026-01-01T00:02:00Z", "t2", OPU, usage(500, 0, 100000, 800000, 20000)),
    call("2026-01-01T00:03:00Z", "t3", FAB, usage(100, 80000, 0, 0, 100, sub=False), text="END"),
])

# --- rewrite: one call that rewrites its predecessor's whole context and one that does not --
#     r1 w5 100,000 -> context 100,010 · r2 w5 95,000 >= 0.9*100,010 (90,009): a rewrite
#     r3 w5 1,000 against r2's context of 95,000: not a rewrite (the negative control)
#     rewrite dollars = r2's writes only: 95,000*10*1.25/1e6 = 1.1875 -> $1.19
#     head = 1.2551 (r1) + 1.19 (r2) + 0.03805 (r3) = 2.48315 -> $2.48
dump(os.path.join(proj, "rewrite.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "r1", FAB, usage(10, 100000, 0, 0, 100)),
    call("2026-01-01T00:02:00Z", "r2", FAB, usage(0, 95000, 0, 0, 50)),
    call("2026-01-01T00:03:00Z", "r3", FAB, usage(5, 1000, 0, 100000, 10), text="END"),
])

# --- long turn versus rewrite: what the previous-context test alone cannot tell apart -------
#     Each call's own context is input + cache read + cache write; a rewrite writes at least
#     0.9 of BOTH it and the previous call's context.
#     g1 in 1,000 · w5 100,000                first call, never a rewrite · context 101,000
#     g2 w5 200,000 · read 100,000            200,000 >= 0.9*101,000 (previous) but only
#                                             0.667 of its own 300,000            NOT a rewrite
#     g3 w5 300,000 · read 0                  300,000 >= 0.9*300,000 both ways        REWRITE
#     g4 every usage field zero               a call recording no context at all (the observed
#                                             shape: four zeros) · context 0
#     g5 w5 140,000 · read 0                  1.00 of its own context and >= 0.9*0 previous:
#                                             the rewrite the truthy guard dropped    REWRITE
#     g6 w5 132,000 · read 140,000            132,000 >= 0.9*140,000 (previous) but only
#                                             0.485 of its own 272,000            NOT a rewrite
#     rewrites 2 of 5 non-first calls, four of which carry a six-figure write; priced on g3
#     and g5's writes alone: (300,000+140,000)*10*1.25/1e6 = 5.50                      -> $5.50
#     head: in 1,000 (0.01) · read 240,000 (0.06) · w5 872,000 (10.90) · out 450 (0.0225)
#           = 10.9925                                                                 -> $10.99
#     Under the rule shipped until 2026-09-05 (previous context alone, truthy guard): g2, g3
#     and g6 count and g5 does not -> 3 rewrites, (200,000+300,000+132,000)*12.5/1e6 = $7.90.
dump(os.path.join(proj, "longturn.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "g1", FAB, usage(1000, 100000, 0, 0, 100)),
    call("2026-01-01T00:02:00Z", "g2", FAB, usage(0, 200000, 0, 100000, 100)),
    call("2026-01-01T00:03:00Z", "g3", FAB, usage(0, 300000, 0, 0, 100)),
    call("2026-01-01T00:04:00Z", "g4", FAB, usage(0, 0, 0, 0, 0)),
    call("2026-01-01T00:05:00Z", "g5", FAB, usage(0, 140000, 0, 0, 50)),
    call("2026-01-01T00:06:00Z", "g6", FAB, usage(0, 132000, 0, 140000, 100), text="END"),
])

# --- tools: blocks spread over a message's records, one of them repeated ---------------------
#     tu1 carries blocks a, b and a again (the repeat must not count twice) plus c on its
#     final record -> 3 distinct blocks; tu2 none; 2 calls -> 1.50 tool uses per call.
#     Its lane repeats the same trap: 2 records, blocks x, y and x, then z -> 3 over 1 call.
dump(os.path.join(proj, "tools.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "tu1", FAB, usage(10, 10, 0, 0, 1),
         blocks=[tool("Bash", "blk-a"), tool("Read", "blk-b")]),
    call("2026-01-01T00:01:30Z", "tu1", FAB, usage(10, 10, 0, 0, 90),
         blocks=[tool("Bash", "blk-a"), tool("Grep", "blk-c")]),
    call("2026-01-01T00:03:00Z", "tu2", FAB, usage(10, 0, 0, 10, 10), text="END"),
])
os.makedirs(os.path.join(proj, "tools", "subagents"), exist_ok=True)
dump(os.path.join(proj, "tools", "subagents", "agent-TL.jsonl"), lane("TL", [
    call("2026-01-01T00:02:00Z", "tl1", OPU, usage(5, 5, 0, 0, 1),
         blocks=[tool("Bash", "blk-x"), tool("Read", "blk-y")]),
    call("2026-01-01T00:02:10Z", "tl1", OPU, usage(5, 5, 0, 0, 40),
         blocks=[tool("Bash", "blk-x"), tool("Edit", "blk-z")]),
]))

# --- spawn: one in-session lane by agent id, one headless lane by session id -----------------
dump(os.path.join(proj, "spawn.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "s1", FAB, usage(10, 1000, 0, 0, 100)),
    call("2026-01-01T00:04:00Z", "s2", FAB, usage(10, 0, 0, 1000, 50), text="END"),
])
os.makedirs(os.path.join(proj, "spawn", "subagents"), exist_ok=True)
dump(os.path.join(proj, "spawn", "subagents", "agent-INS1.jsonl"), lane("INS1", [
    call("2026-01-01T00:02:00Z", "i1", OPU, usage(10, 2000, 0, 0, 200))]))
# The headless lane's own top-level transcript, in a DIFFERENT project directory under the
# fixture projects root: found by session id, never by guessing a directory.
other = os.path.join(root, "projects", "other-project")
os.makedirs(other, exist_ok=True)
dump(os.path.join(other, "headless-1.jsonl"), [
    call("2026-01-01T00:02:30Z", "h1", OPU, usage(10, 3000, 0, 0, 300))])

# --- a second head session of the same run, and a record partitioned across the two ---------
#     Partition A (run-open, session `spawn`): A-INS resolves to agent-INS1, A-GONE never
#     spawned. Partition B (run-resume, session `spawn2`): B-HDL resolves to the headless
#     transcript, B-GONE never spawned. Metering spawn2 with a glob pointed at A-INS's own
#     transcript is how the "another session of this run" report is exercised.
dump(os.path.join(proj, "spawn2.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "q1", FAB, usage(10, 1000, 0, 0, 100)),
    call("2026-01-01T00:04:00Z", "q2", FAB, usage(10, 0, 0, 1000, 50), text="END"),
])
dump(os.path.join(root, "record-two.jsonl"), [
    {"event": "run-open", "run": "fixture-run", "session": "spawn"},
    {"event": "lane-open", "lane": "A-INS", "reason": "instrument rule (a): blind independence"},
    {"event": "lane-spawned", "lane": "A-INS", "agent_id": "agent-INS1"},
    {"event": "lane-open", "lane": "A-GONE", "reason": "instrument rule (c): a lane never spawned"},
    {"event": "run-resume", "run": "fixture-run", "session": "spawn2"},
    {"event": "lane-open", "lane": "B-HDL", "reason": "instrument rule (b)+(d): breadth and context"},
    {"event": "lane-spawned", "lane": "B-HDL", "session_id": "headless-1"},
    {"event": "lane-open", "lane": "B-GONE", "reason": "a reason naming no letter at all"},
])
# The same record with a marker that names no session: nothing may be assigned to it.
dump(os.path.join(root, "record-nosession.jsonl"), [
    {"event": "run-open", "run": "fixture-run"},
    {"event": "lane-open", "lane": "N-1", "reason": "instrument rule (a): blind independence"},
    {"event": "lane-spawned", "lane": "N-1", "agent_id": "agent-INS1"},
])

# --- a lane opened under head `spawn` and resumed under head `spawn2` (the wrapper's
#     lane-resumed event, the same lane session id): two calls before the resume, two from it.
#     Both heads' windows (MARK 00:00 to END 00:04) cover all four calls, so the window alone
#     would bill the whole lane to spawn and nothing to spawn2; the resume's timestamp splits it.
#     v1 opus in 2,000 (0.010) · w5 96,000 (0.600) · out 10,000 (0.250)                  = 0.860
#     v2 opus in 2,000 (0.010) · read 200,000 (0.100) · out 10,000 (0.250)               = 0.360
#     v3 opus in 2,000 (0.010) · read 200,000 (0.100) · w5 200,000 (1.250) · out 20,000 (0.500) = 1.860
#     v4 opus in 2,000 (0.010) · read 400,000 (0.200) · out 20,000 (0.500)               = 0.710
#     spawn's share v1+v2 = 1.220 -> $1.22 · spawn2's share v3+v4 = 2.570 -> $2.57 · the whole
#     lane 3.790 -> $3.79, which the two shares sum to. No call rewrites its predecessor (v3's
#     200,000 write is under 0.9 of its own 402,000 context).
dump(os.path.join(other, "resumed-1.jsonl"), [
    call("2026-01-01T00:01:30Z", "v1", OPU, usage(2000, 96000, 0, 0, 10000)),
    call("2026-01-01T00:02:00Z", "v2", OPU, usage(2000, 0, 0, 200000, 10000)),
    call("2026-01-01T00:03:00Z", "v3", OPU, usage(2000, 200000, 0, 200000, 20000)),
    call("2026-01-01T00:03:30Z", "v4", OPU, usage(2000, 0, 0, 400000, 20000)),
])
shared = [
    {"ts": "2026-01-01T00:00:00Z", "event": "run-open", "run": "fixture-run", "session": "spawn"},
    {"ts": "2026-01-01T00:01:00Z", "event": "lane-open", "lane": "R-SHARED",
     "reason": "instrument rule (a): blind independence"},
    {"ts": "2026-01-01T00:01:00Z", "event": "lane-spawned", "lane": "R-SHARED", "session_id": "resumed-1"},
    {"ts": "2026-01-01T00:02:10Z", "event": "lane-closed", "lane": "R-SHARED", "session_id": "resumed-1",
     "exit_class": "limit", "total_cost_usd": 1.0},
    {"ts": "2026-01-01T00:02:20Z", "event": "run-resume", "run": "fixture-run", "session": "spawn2"},
]
resumed = [
    {"ts": "2026-01-01T00:02:30Z", "event": "lane-resumed", "lane": "R-SHARED", "session_id": "resumed-1",
     "resume_n": 1},
    {"ts": "2026-01-01T00:03:40Z", "event": "lane-closed", "lane": "R-SHARED", "session_id": "resumed-1",
     "exit_class": "completed", "total_cost_usd": 2.0, "resumed": True},
]
dump(os.path.join(root, "record-resumed.jsonl"), shared + resumed)
dump(os.path.join(root, "record-unresumed.jsonl"), shared)      # the control: no resume at all
nots = [dict(rec) for rec in resumed]
del nots[0]["ts"]                                                # a resume with no timestamp
dump(os.path.join(root, "record-resumed-nots.jsonl"), shared + nots)

# No run marker at all: one partition, matched against whatever session is metered. This is
# the shape the meter read before run markers, and the control for the partition legs.
record = [
    {"event": "lane-open", "lane": "L-INS", "reason": "instrument rule (a): blind independence"},
    {"event": "lane-spawned", "lane": "L-INS", "agent_id": "agent-INS1"},
    {"event": "lane-open", "lane": "L-HDL", "reason": "instrument rule (b)+(d): breadth and context"},
    {"event": "lane-spawned", "lane": "L-HDL", "session_id": "headless-1"},
]
gone = {"event": "lane-open", "lane": "L-GONE", "reason": "a reason naming no letter at all"}
dump(os.path.join(root, "record-clean.jsonl"), record)
dump(os.path.join(root, "record-gap.jsonl"), record + [gone])
# A record whose only events are unparseable or carry no lane-open: a broken premise.
with open(os.path.join(root, "record-empty.jsonl"), "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"event": "run-open", "run": "fixture-run"}) + "\n")

# --- unknown: a model id no family matches -> unbilled, never a zero -------------------------
dump(os.path.join(proj, "unknown.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "x1", "mystery-model-9", usage(10, 10, 0, 0, 100), text="END"),
])
# --- mixed: one priced family plus one stray id (a <synthetic> record) -> priced, stray named ---
dump(os.path.join(proj, "mixed.jsonl"), [
    user("2026-01-01T00:00:00Z", "MARK"),
    call("2026-01-01T00:01:00Z", "m1", "claude-test-sonnet-m", usage(10, 10, 0, 0, 100)),
    call("2026-01-01T00:02:00Z", "m2", "<synthetic>", usage(1, 0, 0, 0, 1), text="END"),
])

# --- price tables: one corrupted rate, the same corruption re-dated, and a zeroed rate -------
with open(os.path.join(sys.argv[2], "prices.json"), encoding="utf-8") as fh:
    shipped = json.load(fh)
def priced(change, date=None):
    table = json.loads(json.dumps(shipped))
    table["families"]["fable"].update(change)
    if date:
        table["prices_date"] = date
    return table
def dump_json(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)
dump_json(os.path.join(root, "prices-corrupt.json"), priced({"input": 12.0}))
dump_json(os.path.join(root, "prices-redated.json"), priced({"input": 12.0}, "2099-01-01"))
dump_json(os.path.join(root, "prices-zeroed.json"), priced({"output": 0}))
with open(os.path.join(root, "prices-notjson.json"), "w", encoding="utf-8") as fh:
    fh.write("this is not a price table\n")

# --- fixture vaults: a delegation line, none, and the pre-rename mode line -------------------
os.makedirs(os.path.join(root, "vaultA"), exist_ok=True)
with open(os.path.join(root, "vaultA", "CUSTOMISATION.md"), "w", encoding="utf-8") as fh:
    fh.write("## Settings\n- **style**: balanced\n- **delegation**: multi - the opt-in lane regime\n")
os.makedirs(os.path.join(root, "vaultB"), exist_ok=True)
with open(os.path.join(root, "vaultB", "CUSTOMISATION.md"), "w", encoding="utf-8") as fh:
    fh.write("## Settings\n- **style**: balanced\n")   # no delegation line: unstated
os.makedirs(os.path.join(root, "vaultC"), exist_ok=True)
with open(os.path.join(root, "vaultC", "CUSTOMISATION.md"), "w", encoding="utf-8") as fh:
    fh.write("## Settings\n- **style**: balanced\n- **mode**: multi - the pre-rename line\n")

# --- session state files as role-style-anchor.py keeps them, keyed by the head session id ----
def state(dirname, **keys):
    os.makedirs(os.path.join(root, dirname), exist_ok=True)
    base = {"agent": "x", "role": "generalist", "style": "balanced", "sid": "tiered"}
    base.update(keys)
    with open(os.path.join(root, dirname, "tiered.json"), "w", encoding="utf-8") as fh:
        json.dump(base, fh)
state("state", delegation="multi", delegation_src="head", delegation_scope="run",
      delegation_reason="batch of 6", delegation_run="fixture-run")
state("state-auto", delegation="auto", delegation_src="owner", delegation_scope="session")
os.makedirs(os.path.join(root, "state-bad"), exist_ok=True)
with open(os.path.join(root, "state-bad", "tiered.json"), "w", encoding="utf-8") as fh:
    fh.write("not json\n")
FIXTURE_HEREDOC_END

PRICES="$HERE/prices.json"
BASE=("--project-dir" "$F/proj" "--session" "sess" "--start" "START-RUN-MARKER" "--end" "END-RUN-MARKER"
      "--prices" "$PRICES" "--vault" "$F")
HEADLINE='fable share: head 1,257 out / 6,967 flow / 5,050 peak'
ERRFILE="$F/stderr.txt"

# Every run points the state-file read at a directory that does not exist, so the real
# ~/.cache/aimyth/role-style is never consulted; a leg that wants a state file passes its own
# --state-dir after, and the last one given wins.
run(){ OUT="$("$PY" "$S" --state-dir "$F/state-none" "$@" 2>&1)"; RC=$?; }
runo(){ OUT="$("$PY" "$S" --state-dir "$F/state-none" "$@" 2>"$ERRFILE")"; RC=$?; ERR="$(cat "$ERRFILE")"; }
runx(){ local exe="$1"; shift; OUT="$("$PY" "$exe" --state-dir "$F/state-none" "$@" 2>"$ERRFILE")"; RC=$?; ERR="$(cat "$ERRFILE")"; }
has(){ printf '%s\n' "$OUT" | grep -Fq -- "$1"; }
line(){ printf '%s\n' "$OUT" | grep -Fqx -- "$1"; }

# 1 — the head arithmetic, including the placeholder-then-final rule and both window edges.
run "${BASE[@]}" --lanes none
if [ "$RC" = 0 ] && line "$HEADLINE · lanes not scanned · share n/a"; then
  ok "head output/flow/peak: final usage record wins, out-of-window calls excluded"
else no "head output/flow/peak  [exit $RC] $OUT"; fi

# 2 — the head header: call count, deduplication, model split, effort mix (both over the calls).
if [ "$RC" = 0 ] && has "head: 3 calls (4 assistant records) · models claude-test-fable-a:2, claude-test-opus-b:1 · efforts high:1, max:2"; then
  ok "head header reports 3 calls from 4 records, both models, the effort mix over the calls"
else no "head header  [exit $RC] $OUT"; fi

# 3 — --lanes none says why no share is asserted, and prints no lane figure at all.
if [ "$RC" = 0 ] && line "lanes: not scanned (--lanes none), so the share is not asserted" \
   && ! has "candidate transcript" && ! has "head data:"; then
  ok "--lanes none states why the share is not asserted; no lane control, no data anomalies"
else no "--lanes none header  [exit $RC] $OUT"; fi

# 4 — the dedup rule is load-bearing: mutating it to keep the FIRST record must change the figure.
#     (Control for leg 1: without this, leg 1 could pass on an unrelated coincidence.)
"$PY" - "$S" "$F/mutant-dedup.py" "$F/mutant-raise.py" "$F/mutant-tier.py" \
      "$F/mutant-rewrite.py" <<'MUTATE_HEREDOC_END'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
dedup_old, dedup_new = "        final[key] = row\n", "        final.setdefault(key, row)\n"
raise_old = "    args = ap.parse_args()\n"
raise_new = raise_old + '    raise RuntimeError("planted crash")\n'
# The tier mutation makes every cache write count at the 5-minute rate, which is what the
# meter did before the tier fields were read: the control for the tier-correct legs.
tier_old = "    if isinstance(block, dict) and (TIER_5M in block or TIER_1H in block):\n"
tier_new = "    if False:\n"
# The rewrite mutation restores the classifier shipped until 2026-09-05 — the previous call's
# context alone, behind a truthy guard — which is what legs 32b and 32c bind.
rew_old = ("        elif (context and cache_write >= REWRITE_FRACTION * context\n"
           "              and cache_write >= REWRITE_FRACTION * previous_context):\n")
rew_new = "        elif previous_context and cache_write >= REWRITE_FRACTION * previous_context:\n"
assert dedup_old in src and raise_old in src and tier_old in src and rew_old in src, \
    "mutation anchors drifted"
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(dedup_old, dedup_new, 1))
open(sys.argv[3], "w", encoding="utf-8").write(src.replace(raise_old, raise_new, 1))
open(sys.argv[4], "w", encoding="utf-8").write(src.replace(tier_old, tier_new, 1))
open(sys.argv[5], "w", encoding="utf-8").write(src.replace(rew_old, rew_new, 1))
MUTATE_HEREDOC_END
MUTOK=$?
runx "$F/mutant-dedup.py" "${BASE[@]}" --lanes none
if [ "$MUTOK" = 0 ] && [ "$RC" = 0 ] && has "head 262 out" && ! has "head 1,257 out"; then
  ok "dedup mutation control: keeping the first record per id yields 262, so leg 1 binds the rule"
else no "dedup mutation control  [mutate $MUTOK] [exit $RC] $OUT"; fi

# 5 — durable lane discovery, totals and share.
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp-empty"
if [ "$RC" = 0 ] && line "$HEADLINE · lanes 620 out (claude-test-fable-a:2, claude-test-opus-b:1) · share 67.0%" \
   && has "lanes: 2 in window · control: 2 candidate transcripts scanned (2 durable, 0 volatile, 2 unique after de-duplication)"; then
  ok "lane discovery in the durable home: totals, model split, share, scan control"
else no "durable lane discovery  [exit $RC] $OUT"; fi

# 6 — per-lane attribution lines, including each lane's own window filter and effort count.
if [ "$RC" = 0 ] \
   && line "  lane L1: models claude-test-fable-a:2 · 2 calls (3 records) · 500 out · efforts 2 (low:1, max:1)" \
   && line "  lane L2: models claude-test-opus-b:1 · 1 call (1 record) · 120 out · efforts 1 (max:1)"; then
  ok "per-lane lines: models, calls, records, output, distinct effort values"
else no "per-lane lines  [exit $RC] $OUT"; fi

# 7 — explicit globs replace discovery, and the scan control says so (0 durable, 0 volatile).
run --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
    --lanes "$F/proj/sess/subagents/agent-L*.jsonl"
if [ "$RC" = 0 ] && line "$HEADLINE · lanes 620 out (claude-test-fable-a:2, claude-test-opus-b:1) · share 67.0%" \
   && has "lanes: 2 in window · control: 2 candidate transcripts scanned (0 durable, 0 volatile, 2 unique after de-duplication)"; then
  ok "explicit lane globs meter the same figures and report their own scan control"
else no "explicit lane globs  [exit $RC] $OUT"; fi

# 8 — both lane homes, de-duplicated by content identity (symlink by path, copy by agent id),
#     with a plain-text .output tolerated. Lane total 500+120+44 = 664 -> 1257/1921 = 65.4%.
run "${BASE[@]}" --lanes auto --tmp-root "$F/tmp"
if [ "$RC" = 0 ] && line "$HEADLINE · lanes 664 out (claude-test-fable-a:2, claude-test-opus-b:2) · share 65.4%" \
   && has "lanes: 3 in window · control: 6 candidate transcripts scanned (2 durable, 4 volatile, 5 unique after de-duplication) · 1 dropped as a duplicate identity" \
   && line "  lane L3: models claude-test-opus-b:1 · 1 call (1 record) · 44 out · efforts 1 (max:1)"; then
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
if [ "$RC" = 0 ] && has "head: 4 calls (4 assistant records) · models claude-test-sonnet-m:4 · efforts max:4"; then
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
check --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" --lanes none --delegation multi
check --project-dir "$F/proj" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" --lanes none --delegation-src head
CTRL=1; premise_bad "${BASE[@]}" --lanes none && CTRL=0
if [ "$BAD" = 0 ] && [ "$CTRL" = 1 ]; then
  ok "16 broken premises each print one unmetered line with no figure (control: a metered run fails the same check)"
else no "premise failure shape  [bad $BAD] [control $CTRL]"; fi

# 27 — the belt: an unforeseen error is reported as a broken premise, never as a traceback on
#      stdout and never as a metered run.
runx "$F/mutant-raise.py" "${BASE[@]}" --lanes none
if [ "$RC" = 2 ] && line "fable share: unmetered (unexpected error, see stderr: RuntimeError: planted crash)" \
   && printf '%s\n' "$ERR" | grep -q "Traceback"; then
  ok "a planted crash prints the unmetered line on stdout with its traceback on stderr, exit 2"
else no "unexpected-error belt  [exit $RC] $OUT"; fi

# ============================ the billed line ===============================================
# Every dollar asserted below is hand-computed beside its fixture (see the billing fixtures),
# never read back from the script. TB is the tiered fixture's base invocation.
TB=("--project-dir" "$F/proj" "--session" "tiered" "--start" "MARK" "--end" "END"
    "--lanes" "none" "--prices" "$PRICES" "--vault" "$F")

# 28 — the billed line in text, tier-correct, with the per-model rows and the fallback report.
run "${TB[@]}"
if [ "$RC" = 0 ] && has "billed (list, prices 2026-09-03): head \$8.39 · lanes not scanned · session \$8.39" \
   && line "  claude-test-fable-a (fable): 2 calls · in 1,100 · read 400,000 · write 5m 230,000 / 1h 50,000 · out 50,100 · tools 0 · \$6.49" \
   && line "  claude-test-opus-b (opus): 1 call · in 500 · read 800,000 · write 5m 0 / 1h 100,000 · out 20,000 · tools 0 · \$1.90"; then
  ok "billed line and per-model rows: 5-minute and 1-hour writes priced apart, tokens printed beside dollars"
else no "tiered billed line  [exit $RC] $OUT"; fi
if [ "$RC" = 0 ] && has "1 call with no cache_creation tier, counted at the 5-minute rate" \
   && has "fixture \$17.10 matches the hand-computed anchor for 2026-09-03"; then
  ok "the untiered-write fallback is counted and reported, and the price control ran"
else no "untiered fallback report  [exit $RC] $OUT"; fi

# 29 — the tier fields are load-bearing: pricing every write at the 5-minute rate must change
#      the figure (control for leg 28; without it leg 28 could pass on an unrelated sum).
#      Both 1-hour writes drop a tier: fable 50,000 (1.00 -> 0.625) and opus 100,000
#      (1.00 -> 0.625), so 8.3935 - 0.75 = 7.6435 -> $7.64.
runx "$F/mutant-tier.py" "${TB[@]}"
if [ "$RC" = 0 ] && has "head \$7.64" && ! has "head \$8.39"; then
  ok "tier mutation control: writes all at the 5-minute rate yield \$7.64, so leg 28 binds the tier fields"
else no "tier mutation control  [exit $RC] $OUT"; fi

# 30 — the same figures in JSON, under billed and per_agent.
run "${TB[@]}" --format json
if [ "$RC" = 0 ] && printf '%s' "$OUT" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
b = d["billed"]
assert b["prices_date"] == "2026-09-03", b["prices_date"]
assert abs(b["head_usd"] - 8.3935) < 1e-9, b["head_usd"]
assert b["lanes_usd"] is None and abs(b["session_usd"] - 8.3935) < 1e-9, b
assert b["untiered_write_records"] == 1, b["untiered_write_records"]
assert b["rewrites"] == 0 and b["rewrites_usd"] == 0.0, b
assert b["delegation"] == "unstated" and b["delegation_src"] is None and b["baseline"] == "none", b
assert b["delegation_from"].startswith("no CUSTOMISATION.md at "), b["delegation_from"]
assert b["reason_tally"] is None and b["lanes_recorded"] is None, b
fab = b["per_model"]["claude-test-fable-a"]
assert fab["write_5m"] == 230000 and fab["write_1h"] == 50000, fab
assert abs(fab["usd"] - 6.491) < 1e-9, fab["usd"]
assert [a["label"] for a in d["per_agent"]] == ["head"], d["per_agent"]
assert d["per_agent"][0]["calls"] == 3 and d["per_agent"][0]["kind"] == "head"
assert d["line"].startswith("fable share: head 70,100 out"), d["line"]
'; then ok "JSON carries the billed object and the per_agent array with the same figures"
else no "JSON billed object  [exit $RC] $OUT"; fi

# 31 — --per-agent: one row per agent, the head and both lanes, with the record's own labels.
#      head prefix 10+1,000 = 1,010 · L-INS 10+2,000 · L-HDL 10+3,000
SP=("--project-dir" "$F/proj" "--session" "spawn" "--start" "MARK" "--end" "END"
    "--prices" "$PRICES" "--vault" "$F" "--projects-root" "$F/projects")
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-clean.jsonl" --per-agent
if [ "$RC" = 0 ] \
   && line "  head  · claude-test-fable-a:2 · 2 calls · prefix 1,010 · peak 1,010 · out 150 · tools 0 · \$0.02" \
   && line "  L-INS · claude-test-opus-b:1 · 1 call · prefix 2,010 · peak 2,010 · out 200 · tools 0 · \$0.02" \
   && line "  L-HDL · claude-test-opus-b:1 · 1 call · prefix 3,010 · peak 3,010 · out 300 · tools 0 · \$0.03"; then
  ok "--per-agent prints the head and every lane with label, models, calls, first-call prefix, peak, output, tool uses and dollars"
else no "--per-agent rows  [exit $RC] $OUT"; fi
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-clean.jsonl"
if [ "$RC" = 0 ] && ! has "per-agent (label"; then
  ok "no per-agent table without the flag (control for the leg above)"
else no "per-agent table suppressed  [exit $RC] $OUT"; fi

# 32 — the rewrite classifier: one call that rewrites the whole previous context and one that
#      does not, so the count is 1 of 2 non-first calls, priced on the rewrite's writes alone.
run --project-dir "$F/proj" --session rewrite --start MARK --end END --lanes none \
    --prices "$PRICES" --vault "$F"
if [ "$RC" = 0 ] && has "head \$2.48" && has "rewrites 1 (\$1.19)" \
   && has "head: 3 calls"; then
  ok "rewrite classifier: the 95,000-token rewrite of a 100,010-token context counts, the 1,000-token write does not (1 of 2 non-first calls)"
else no "rewrite classifier  [exit $RC] $OUT"; fi
run "${TB[@]}"
if [ "$RC" = 0 ] && has "rewrites 0 (\$0.00)"; then
  ok "a fixture with no full-context rewrite reports zero rewrites (control: the leg above is not counting every call)"
else no "rewrite negative control  [exit $RC] $OUT"; fi

# 32b — the classifier keys on BOTH contexts: a long turn that reads its prefix from the cache
#       and appends a large tool result is not a rewrite, and a rewrite whose predecessor
#       recorded no context still is. 2 of 5 non-first calls, four of them six-figure writes.
LT=("--project-dir" "$F/proj" "--session" "longturn" "--start" "MARK" "--end" "END"
    "--lanes" "none" "--prices" "$PRICES" "--vault" "$F")
run "${LT[@]}"
if [ "$RC" = 0 ] && has "head \$10.99" && has "rewrites 2 (\$5.50)" && has "head: 6 calls"; then
  ok "rewrite classifier, both halves: 2 rewrites of 5 non-first calls (4 carry a six-figure write), \$5.50 priced on their writes alone; the 200,000- and 132,000-token long-turn writes are not counted"
else no "rewrite classifier, both halves  [exit $RC] $OUT"; fi

# 32c — the pre-2026-09-05 rule is what leg 32b binds: keying on the previous context alone
#       counts the two long-turn writes and its truthy guard drops g5, giving 3 (\$7.90).
runx "$F/mutant-rewrite.py" "${LT[@]}"
if [ "$RC" = 0 ] && has "rewrites 3 (\$7.90)" && ! has "rewrites 2 (\$5.50)"; then
  ok "rewrite mutation control: the previous-context-only rule yields 3 (\$7.90) on the same fixture, so leg 32b binds the own-context half and the dropped guard"
else no "rewrite mutation control  [exit $RC] $OUT"; fi

# 33 — tool uses per call, over blocks spread across a message's records, one block repeated.
run --project-dir "$F/proj" --session tools --start MARK --end END --lanes auto \
    --tmp-root "$F/tmp-empty" --prices "$PRICES" --vault "$F"
if [ "$RC" = 0 ] && has "tool uses/call head 1.50 lanes 3.00" \
   && has "· tools 3 · "; then
  ok "tool uses per call: 3 distinct blocks over 2 head calls and 3 over 1 lane call, a repeated block id counted once"
else no "tool uses per call  [exit $RC] $OUT"; fi
run "${TB[@]}"
if [ "$RC" = 0 ] && has "tool uses/call head 0.00 lanes n/a"; then
  ok "a fixture with no tool_use block reports 0.00 per call, and n/a where lanes are not scanned (control)"
else no "tool uses per call, none  [exit $RC] $OUT"; fi

# 34 — lane discovery by id from the spawn record: an in-session lane by agent id and a
#      headless lane by session id, under a fixture projects root. The lane glob deliberately
#      matches nothing, so both lanes can only have come from the record.
run "${SP[@]}" --lanes "$F/nothing/*.jsonl" --spawn-record "$F/record-clean.jsonl" --per-agent
if [ "$RC" = 0 ] && has "lanes: 2 in window" && has "2 resolved from the spawn record" \
   && has "metered 2 of 2 recorded" && ! has "MISMATCH" \
   && has "  L-INS · " && has "  L-HDL · "; then
  ok "--spawn-record finds an in-session lane by agent id and a headless lane by session id where the lane glob matches nothing"
else no "spawn-record discovery  [exit $RC] $OUT"; fi
run "${SP[@]}" --lanes "$F/nothing/*.jsonl"
if [ "$RC" = 2 ] && has "fable share: unmetered (no readable lane transcript found"; then
  ok "the same glob without the record reaches no lane at all (control: the two lanes above came from the record)"
else no "spawn-record discovery control  [exit $RC] $OUT"; fi

# 35 — a recorded lane with no transcript is flagged, not hidden, and the reason tally reads
#      the letters: (a) once, (b) and (d) from one two-letter reason, (c) never, none once.
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-gap.jsonl"
if [ "$RC" = 0 ] && has "metered 2 of 3 recorded [MISMATCH: 1 recorded lane(s) unmatched]" \
   && has "lanes 2 (reasons: (a)×1 (b)×1 (c)×0 (d)×1, none×1)"; then
  ok "metered n of m: an unmatched recorded lane is flagged on the line while the figures still print, exit 0; the reason tally counts every letter and a reason naming none"
else no "metered n of m mismatch  [exit $RC] $OUT"; fi
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty"
if [ "$RC" = 0 ] && has "metered 1 of n/a recorded" && has "(reasons: n/a)" && ! has "MISMATCH"; then
  ok "without a spawn record the tally and the recorded count read n/a and nothing is flagged (control)"
else no "no spawn record  [exit $RC] $OUT"; fi

# 36 — the delegation regime and its source: the Settings line (source owner, the state file
#      tried first and named), the flags, an absent line, and the pre-rename mode line.
run "${TB[@]}" --vault "$F/vaultA"
if [ "$RC" = 0 ] && has "· delegation multi (owner) ·" \
   && has "delegation from the delegation line of $F/vaultA/CUSTOMISATION.md (no session state file at $F/state-none/tiered.json)"; then
  ok "the Settings delegation line supplies the regime with source owner, after the state file was tried and found absent"
else no "delegation from the Settings line  [exit $RC] $OUT"; fi
run "${TB[@]}" --vault "$F/vaultA" --delegation single --delegation-src head --baseline "run-2026-01-01 same sources"
if [ "$RC" = 0 ] && has "· delegation single (head) · baseline run-2026-01-01 same sources ·" && has "delegation from --delegation"; then
  ok "--delegation with --delegation-src overrides the file, and --baseline is printed verbatim"
else no "delegation override  [exit $RC] $OUT"; fi
run "${TB[@]}" --vault "$F/vaultB"
if [ "$RC" = 0 ] && has "· delegation unstated ·" && has "no delegation line in $F/vaultB/CUSTOMISATION.md"; then
  ok "a CUSTOMISATION.md without a delegation line leaves the regime unstated and says why (control for the legs above)"
else no "delegation unstated  [exit $RC] $OUT"; fi
run "${TB[@]}" --vault "$F/vaultC"
if [ "$RC" = 0 ] && has "· delegation multi (owner) ·" && has "delegation from the pre-rename mode line of $F/vaultC/CUSTOMISATION.md"; then
  ok "the pre-rename mode line is still read, with source owner, and named as the pre-rename line"
else no "pre-rename mode line  [exit $RC] $OUT"; fi

# 36b — the session state file: the head's resolution under auto, read by session id; an owner
#       auto there is no regime; the flags override the file; a broken file falls through and says why.
run "${TB[@]}" --vault "$F/vaultA" --state-dir "$F/state"
if [ "$RC" = 0 ] && has "· delegation multi (head) ·" && has "delegation from the session state file $F/state/tiered.json"; then
  ok "the head's resolution in the session state file is read by session id and outranks the Settings line"
else no "delegation from the state file  [exit $RC] $OUT"; fi
run "${TB[@]}" --vault "$F/vaultA" --state-dir "$F/state-auto"
if [ "$RC" = 0 ] && has "· delegation multi (owner) ·" && has "carries no resolved regime (delegation 'auto', source 'owner')"; then
  ok "an owner-set auto in the state file is no regime: the Settings word is used and the fall-through is named"
else no "owner auto in the state file  [exit $RC] $OUT"; fi
run "${TB[@]}" --vault "$F/vaultA" --state-dir "$F/state" --delegation single --delegation-src owner
if [ "$RC" = 0 ] && has "· delegation single (owner) ·" && has "delegation from --delegation"; then
  ok "the flags override the state file (control: the same file supplied multi (head) above)"
else no "flags over the state file  [exit $RC] $OUT"; fi
run "${TB[@]}" --vault "$F/vaultB" --state-dir "$F/state-bad"
if [ "$RC" = 0 ] && has "· delegation unstated ·" && has "(session state file unreadable ("; then
  ok "a state file that is not JSON falls through to unstated and says why"
else no "unreadable state file  [exit $RC] $OUT"; fi
run "${TB[@]}" --format json --vault "$F/vaultA" --state-dir "$F/state"
if [ "$RC" = 0 ] && printf '%s' "$OUT" | "$PY" -c '
import json, sys
b = json.load(sys.stdin)["billed"]
assert b["delegation"] == "multi" and b["delegation_src"] == "head", b
assert b["delegation_from"].startswith("the session state file "), b["delegation_from"]
assert "delegation multi (head)" in b["line"], b["line"]
'; then ok "JSON carries delegation, delegation_src and delegation_from beside the billed line"
else no "JSON delegation keys  [exit $RC] $OUT"; fi
run "${TB[@]}" --delegation multi
if [ "$RC" = 2 ] && line "fable share: unmetered (--delegation and --delegation-src go together: --delegation single|multi --delegation-src head|owner)"; then
  ok "--delegation without --delegation-src is a broken premise, never a regime with no source"
else no "delegation without a source  [exit $RC] $OUT"; fi
run "${TB[@]}" --delegation-src head
if [ "$RC" = 2 ] && has "go together"; then
  ok "--delegation-src without --delegation is refused the same way"
else no "source without a regime  [exit $RC] $OUT"; fi

# 37 — unbilled: no price table. The share line still prints, then the unbilled line, exit 2.
run "${TB[@]}" --prices "$F/no-such-prices.json"
if [ "$RC" = 2 ] && has "fable share: head 70,100 out" \
   && has "billed: unbilled (price table unreadable: $F/no-such-prices.json" \
   && ! has "billed (list"; then
  ok "a missing price table prints the share line, then unbilled, and exits 2 — never a zero"
else no "unbilled, missing table  [exit $RC] $OUT"; fi
run "${TB[@]}" --prices "$F/prices-notjson.json"
if [ "$RC" = 2 ] && has "billed: unbilled (price table is not valid JSON:"; then
  ok "a price table that is not JSON is a broken billing premise"
else no "unbilled, not JSON  [exit $RC] $OUT"; fi
run "${TB[@]}" --format json --prices "$F/no-such-prices.json"
if [ "$RC" = 2 ] && has "billed: unbilled (price table unreadable:" && ! has '"billed"'; then
  ok "JSON mode prints the same two lines and no payload on a billing premise failure"
else no "unbilled in JSON  [exit $RC] $OUT"; fi

# 38 — unbilled: a model id no price family matches.
run --project-dir "$F/proj" --session unknown --start MARK --end END --lanes none \
    --prices "$PRICES" --vault "$F"
if [ "$RC" = 2 ] && has "fable share: head 100 out" \
   && has "billed: unbilled (model id matches no price family" && has "mystery-model-9"; then
  ok "an unknown model id is unbilled with the id named, exit 2, the metered line still printed"
else no "unbilled, unknown model  [exit $RC] $OUT"; fi

# 38b — priced with an unpriced list: one priced family plus one stray id is billed, the stray named.
run --project-dir "$F/proj" --session mixed --start MARK --end END --lanes none \
    --prices "$PRICES" --vault "$F"
if [ "$RC" = 0 ] && has "billed (list" && has "unpriced <synthetic> (1 call)" && ! has "billed: unbilled"; then
  ok "one stray model id beside a priced family prices the family and names the stray with its call count, exit 0"
else no "mixed unpriced  [exit $RC] $OUT"; fi
run --project-dir "$F/proj" --session mixed --start MARK --end END --lanes none \
    --prices "$PRICES" --vault "$F" --format json
if [ "$RC" = 0 ] && has '"unpriced": [' && has '"model": "<synthetic>"' && ! has '"unpriced": []'; then
  ok "and the JSON payload carries the unpriced list"
else no "mixed unpriced JSON  [exit $RC] $OUT"; fi

# 39 — the built-in price control, and what it does when its own premise moves.
run "${TB[@]}" --prices "$F/prices-corrupt.json"
if [ "$RC" = 2 ] && has "billed: unbilled (control fixture priced at \$" \
   && has "against the hand-computed \$17.10 for the table dated 2026-09-03"; then
  ok "the known-positive control catches a corrupted rate in a table still carrying the anchor date, exit 2"
else no "price control on a corrupted table  [exit $RC] $OUT"; fi
run "${TB[@]}" --prices "$F/prices-redated.json"
if [ "$RC" = 0 ] && has "anchor \$17.10 not applicable (table dated 2099-01-01" && has "invariants checked"; then
  ok "a re-priced, re-dated table is billed with the anchor stated as not applicable rather than failing a legitimate re-pricing"
else no "price control, re-dated table  [exit $RC] $OUT"; fi
run "${TB[@]}" --prices "$F/prices-zeroed.json"
if [ "$RC" = 2 ] && has "billed: unbilled (price table field output of family fable is not a positive number: 0)"; then
  ok "a rate of zero is refused by the table check, so no column of the bill can silently price at nothing"
else no "price table with a zero rate  [exit $RC] $OUT"; fi

# 40 — the spawn record's own premises.
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/no-such-record.jsonl"
if [ "$RC" = 2 ] && line "fable share: unmetered (spawn record not found: $F/no-such-record.jsonl)"; then
  ok "a missing spawn record is a broken premise, not a silent n/a"
else no "missing spawn record  [exit $RC] $OUT"; fi
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-empty.jsonl"
if [ "$RC" = 2 ] && line "fable share: unmetered (spawn record holds no lane-open event: $F/record-empty.jsonl)"; then
  ok "a spawn record with no lane-open event cannot support the tally it was passed for"
else no "spawn record with no lanes  [exit $RC] $OUT"; fi

# ======================= the record's partitions, per head session ==========================
# A run outlives one head session, so lane events are partitioned by the run-open/run-resume
# marker that precedes them and only the metered session's partition is expected. The record
# is `record-two.jsonl` (partition A = session `spawn`, partition B = session `spawn2`).

# 41 — metered as session A: its own two lanes, one matched, and no sight of partition B.
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-two.jsonl"
if [ "$RC" = 0 ] \
   && has "metered 1 of 2 recorded under run-open spawn [MISMATCH: 1 recorded lane(s) unmatched]" \
   && has "lanes 1 (reasons: (a)×1 (b)×0 (c)×1 (d)×0, none×0)" \
   && ! has "another session"; then
  ok "a partitioned record metered as session A expects A's two lanes only, tallies A's reasons, and never mentions B"
else no "partition A  [exit $RC] $OUT"; fi

# 42 — metered as session B: B's two lanes, the headless one matched by session id.
SP2=("--project-dir" "$F/proj" "--session" "spawn2" "--start" "MARK" "--end" "END"
     "--prices" "$PRICES" "--vault" "$F" "--projects-root" "$F/projects")
run "${SP2[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-two.jsonl" --per-agent
if [ "$RC" = 0 ] \
   && has "metered 1 of 2 recorded under run-resume spawn2 [MISMATCH: 1 recorded lane(s) unmatched]" \
   && has "lanes 1 (reasons: (a)×0 (b)×1 (c)×0 (d)×1, none×1)" \
   && has "  B-HDL · "; then
  ok "the same record metered as session B expects B's lanes, finds its headless lane by session id and labels it B-HDL"
else no "partition B  [exit $RC] $OUT"; fi

# 43 — a transcript recorded under the other partition is named as such, never as unrecorded.
run "${SP2[@]}" --lanes "$F/proj/spawn/subagents/agent-INS1.jsonl" --spawn-record "$F/record-two.jsonl"
if [ "$RC" = 0 ] && has "1 metered lane(s) from another session of this run" \
   && ! has "not in the record"; then
  ok "a lane recorded under another session of the same run is reported as such, not as a lane missing from the record"
else no "other-partition attribution  [exit $RC] $OUT"; fi

# 44 — the no-marker control: a record without run-open/run-resume keeps today's behaviour,
#      every event in one partition, matched against whatever session is metered.
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-gap.jsonl"
if [ "$RC" = 0 ] && has "metered 2 of 3 recorded [MISMATCH: 1 recorded lane(s) unmatched]" \
   && ! has "recorded under"; then
  ok "a record with no run marker is one partition and names none (control: the partition legs above are not renaming every run)"
else no "no-marker control  [exit $RC] $OUT"; fi

# 45 — a marker that names no session claims nothing: its lanes are not assigned to this
#      session, and the flag says the partition had no session field.
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-nosession.jsonl"
if [ "$RC" = 0 ] && has "metered 0 of 0 recorded under no partition for spawn" \
   && has "1 partition(s) with no session field"; then
  ok "a run marker without a session field is a broken premise for its partition, printed on the flag rather than guessed"
else no "marker with no session  [exit $RC] $OUT"; fi

# ==================== a lane resumed by a later head is split at the resume =================
# `record-resumed.jsonl`: R-SHARED opened under head `spawn` (run-open), cut at 00:02:10,
# resumed under head `spawn2` (run-resume) at 00:02:30 and closed at 00:03:40. Its transcript
# holds two calls before the resume ($1.22) and two from it on ($2.57); both heads' windows
# cover all four, so only the resume's timestamp can split them (the register case of
# 2026-09-05, where the resumer's line read lanes $0.00 under no partition). Under --lanes
# auto, head `spawn` also scans its durable in-session lane INS1 ($0.02, see the spawn
# fixture), which this record never opened: its lanes figure is the share plus $0.02, and the
# line flags that lane as not in the record. Head spawn's own calls price at $0.02.

# 45b — the opener bills the first run only, with the resume's records named as excluded.
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-resumed.jsonl"
if [ "$RC" = 0 ] && has "lanes \$1.24" && has "session \$1.26" \
   && has "metered 1 of 1 recorded under run-open spawn [MISMATCH: 1 metered lane(s) not in the record]" \
   && has "lane R-SHARED: models claude-test-opus-b:2 · 2 calls (2 records) · 20,000 out" \
   && has "split at the resume: 2 records of another head's span excluded"; then
  ok "a lane resumed by a later head: the opener bills the two calls before the resume (\$1.22, plus the \$0.02 in-session lane it scans) and names the two it excluded"
else no "resumed lane, opener  [exit $RC] $OUT"; fi

# 45c — the resumer bills the resume under its own partition, counts the lane as its own and
#       tallies its reason.
run "${SP2[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-resumed.jsonl"
if [ "$RC" = 0 ] && has "lanes \$2.57" && has "session \$2.59" \
   && has "metered 1 of 1 recorded under run-resume spawn2" && ! has "MISMATCH" \
   && has "lane R-SHARED: models claude-test-opus-b:2 · 2 calls (2 records) · 40,000 out" \
   && has "lanes 1 (reasons: (a)×1 (b)×0 (c)×0 (d)×0, none×0)"; then
  ok "the resumer bills the two calls from the resume on (\$2.57) under run-resume spawn2, metered 1 of 1, and the two shares sum to the whole lane"
else no "resumed lane, resumer  [exit $RC] $OUT"; fi

# 45d — the negative control: without the lane-resumed event the whole lane ($3.79 = 1.22 +
#       2.57, plus INS1's $0.02 = $3.81) is the opener's, nothing is split, and the resumer
#       reads no partition — the shape the register entry described.
run "${SP[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-unresumed.jsonl"
A_OK=0; A_OUT="$OUT"
if [ "$RC" = 0 ] && has "lanes \$3.81" && has "metered 1 of 1 recorded under run-open spawn" \
   && has "lane R-SHARED: models claude-test-opus-b:4 · 4 calls (4 records) · 60,000 out" \
   && ! has "split at the resume"; then A_OK=1; fi
run "${SP2[@]}" --lanes auto --tmp-root "$F/tmp-empty" --expect-lanes 0 --spawn-record "$F/record-unresumed.jsonl"
if [ "$A_OK" = 1 ] && [ "$RC" = 0 ] && has "lanes \$0.00" \
   && has "metered 0 of 0 recorded under no partition for spawn2"; then
  ok "control: the same record without the resume bills the whole lane (\$3.79) to the opener, splits nothing, and leaves the resumer with no partition — the split is the resume event's doing"
else no "unresumed control  [opener ok $A_OK] [exit $RC] $A_OUT $OUT"; fi

# 45e — a resume with no timestamp cannot split the lane: unmetered for the resumer and
#       flagged, never billed on a guessed boundary.
run "${SP2[@]}" --lanes auto --tmp-root "$F/tmp-empty" --spawn-record "$F/record-resumed-nots.jsonl"
if [ "$RC" = 0 ] && has "lanes \$0.00" \
   && has "metered 0 of 1 recorded under run-resume spawn2 [MISMATCH: 1 recorded lane(s) unmatched; 1 shared lane(s) unsplittable (no timestamp on a lane-open or lane-resumed), left unmetered]" \
   && has "1 shared lane(s) unsplittable, left unmetered"; then
  ok "a shared lane whose resume carries no timestamp is left unmetered and flagged as unsplittable, on the billed line and the scan control"
else no "unsplittable  [exit $RC] $OUT"; fi

# 46 — stdout-only proof: run every mode against read-only copies of the fixture AND of the
#      script home, comparing checksum manifests before and after, then grep the source for the
#      write patterns the shared spec bans.
RO="$F/ro"; ROHOME="$F/rohome"
mkdir -p "$RO" "$ROHOME"
cp -R "$F/proj" "$RO/proj"
cp -R "$F/projects" "$RO/projects"
cp "$F/record-gap.jsonl" "$RO/record-gap.jsonl"
cp -R "$F/state" "$RO/state"
cp "$S" "$ROHOME/fable-share.py"
cp "$HERE/prices.json" "$ROHOME/prices.json"   # the table the script resolves beside itself
manifest(){ find "$1" -type f -exec shasum {} \; | sort; }
# Positive control for the comparison itself: a read-only tree cannot record a rejected write,
# so prove on a writable scratch copy that the manifest actually notices a changed byte.
SCRATCH="$F/scratch"; mkdir -p "$SCRATCH"; printf 'a\n' > "$SCRATCH/probe"
M1="$(manifest "$SCRATCH")"; printf 'b\n' > "$SCRATCH/probe"; M2="$(manifest "$SCRATCH")"
if [ -n "$M1" ] && [ "$M1" != "$M2" ]; then ok "manifest comparison detects a changed byte (control for the leg below)"
else no "manifest comparison is insensitive — the stdout-only leg below would be vacuous"; fi
chmod -R a-w "$RO" "$ROHOME"
BEFORE="$(manifest "$RO"; manifest "$ROHOME")"
RM=("$PY" "$ROHOME/fable-share.py" --project-dir "$RO/proj" --state-dir "$RO/state")
"${RM[@]}" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
      --lanes auto --tmp-root "$F/tmp-empty" > /dev/null 2>&1
"${RM[@]}" --session sess --start "START-RUN-MARKER" --end "END-RUN-MARKER" \
      --lanes none --format json --baseline-output 10 > /dev/null 2>&1
"${RM[@]}" --session malformed --start MAL-START --end MAL-END --lanes none > /dev/null 2>&1
"${RM[@]}" --session torn --start MARK --end END --lanes none > /dev/null 2>&1
"${RM[@]}" --session lonely --start MARK --end END --lanes auto --tmp-root "$F/tmp2" > /dev/null 2>&1
"${RM[@]}" --session nope --lanes none > /dev/null 2>&1
"$PY" "$ROHOME/fable-share.py" --project-dir "$RO/proj-not-here" --session sess --lanes none > /dev/null 2>&1
# the billing paths: the billed line, the per-agent table, lane discovery by id (in-session
# and headless), JSON with the billed object, and a billing premise failure.
# Captured, not discarded: a run that failed early would make this leg vacuous, so the leg
# below asserts this one really priced something on the read-only tree.
RO_BILLED="$("${RM[@]}" --session tiered --start MARK --end END --lanes none --vault "$F" 2>&1)"
"${RM[@]}" --session spawn --start MARK --end END --lanes auto --tmp-root "$F/tmp-empty" \
      --spawn-record "$RO/record-gap.jsonl" --projects-root "$RO/projects" --per-agent \
      --vault "$F/vaultA" --baseline "read-only run" > /dev/null 2>&1
"${RM[@]}" --session spawn --start MARK --end END --lanes auto --tmp-root "$F/tmp-empty" \
      --spawn-record "$RO/record-gap.jsonl" --projects-root "$RO/projects" --format json > /dev/null 2>&1
"${RM[@]}" --session unknown --start MARK --end END --lanes none > /dev/null 2>&1
"${RM[@]}" --session tiered --start MARK --end END --lanes none --prices "$F/no-such.json" > /dev/null 2>&1
AFTER="$(manifest "$RO"; manifest "$ROHOME")"
WRITES=0
for pat in 'open\([^)]*['"'"'"][wax]' '\bwrite_text\b' '\bwritelines\b' '\.write\(' \
           '\bos\.(remove|unlink|rename|replace|mkdir|makedirs|rmdir)\b' '\bshutil\.' \
           '\b(subprocess|Popen)\b' '\bos\.system\b'; do
  if grep -nE -- "$pat" "$S" | grep -v '^[0-9]*: *#'; then WRITES=$((WRITES+1)); fi
done
CONTROL="$(grep -cE -- 'open\(' "$S")"
RO_PRICED=0; printf '%s\n' "$RO_BILLED" | grep -Fq "billed (list, prices" && RO_PRICED=1
RO_STATE=0; printf '%s\n' "$RO_BILLED" | grep -Fq "delegation multi (head)" && RO_STATE=1
if [ "$BEFORE" = "$AFTER" ] && [ "$WRITES" = 0 ] && [ "$CONTROL" -gt 0 ] && [ -n "$BEFORE" ] \
   && [ "$RO_PRICED" = 1 ] && [ "$RO_STATE" = 1 ]; then
  ok "stdout-only: read-only fixture, projects root, spawn record, session state and script home (with its price table) unchanged after twelve runs across every mode, billing included; no write pattern in the source (controls: $CONTROL read-mode open calls found by the same grep; the read-only state file was read, not just present)"
else no "stdout-only proof  [manifest changed: $([ "$BEFORE" = "$AFTER" ] && echo no || echo yes); write patterns: $WRITES; control opens: $CONTROL; priced on the read-only tree: $RO_PRICED; state read: $RO_STATE]"; fi
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

# 47 — the suite itself leaves the shipped home alone: the files are byte-identical and no
#      bytecode cache appeared (importing the script for leg 22 would write one by default).
mkdir -p "$F/fakehome/__pycache__"                     # control: the -d test must discriminate
HOME_AFTER="$(shasum "$S" "$HERE/prices.json" "${BASH_SOURCE[0]}")"
if [ -n "$HOME_BEFORE" ] && [ "$HOME_BEFORE" = "$HOME_AFTER" ] && [ ! -d "$HERE/__pycache__" ] \
   && [ -d "$F/fakehome/__pycache__" ]; then
  ok "the suite leaves its own home untouched: script, price table and suite unchanged, no bytecode cache (controls: the byte-change control above, and a planted __pycache__ the same test does see)"
else no "suite wrote into the script home  [changed: $([ "$HOME_BEFORE" = "$HOME_AFTER" ] && echo no || echo yes); pycache: $([ -d "$HERE/__pycache__" ] && echo yes || echo no)]"; fi

TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then echo "PASS $PASS/$TOTAL"; else echo "FAIL $FAIL/$TOTAL"; exit 1; fi
