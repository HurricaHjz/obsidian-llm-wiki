#!/bin/sh
# test_lane.sh — regression suite for lane.py and lane-fence.py (delegate skill, thin lanes).
#
# Two parts. The OFFLINE part puts a stub `claude` first on PATH that records its argv, stdin,
# cwd and lane environment, writes a fixture transcript into a fixture projects root and emits
# a canned result JSON, so every wrapper behaviour is asserted without spending a penny. The
# LIVE part (--live) spawns a handful of real sonnet lanes and asserts what only a real
# harness can show: the read fence, the shell fence, the effort actually applied, the cache
# write tier, a write lane's whitelist, and the core-injection measurement.
#
# Every clean claim carries a positive control on the same probe: a planted case the same test
# must catch. Fixtures live under one mktemp -d that the suite removes; nothing outside it is
# written, and the last legs prove that with a checksum manifest and a source grep whose own
# control must hit.
#
# Run:  sh test_lane.sh                 offline only   (last line PASS n/n or FAIL k/n)
#       sh test_lane.sh --live          offline + the live sonnet legs (prints the live spend)
#       sh test_lane.sh --live-handsoff offline + two haiku probes (the allow list, the vault root)
#       sh test_lane.sh --vault DIR     run a copy of the scripts from elsewhere against DIR
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LANE="$HERE/lane.py"
FENCE="$HERE/lane-fence.py"
PY="${PYTHON:-python3}"
LIVE=0; LIVEHO=0; VAULT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE=1 ;;
    --live-handsoff) LIVEHO=1 ;;
    --vault) shift; VAULT_ARG="${1:-}" ;;
    *) echo "usage: sh test_lane.sh [--live] [--live-handsoff] [--vault DIR]" >&2; exit 2 ;;
  esac
  shift
done
export PYTHONDONTWRITEBYTECODE=1

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "FAIL   — $1"; }
eq(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1  [want $3, got $2]"; fi; }

F=$(mktemp -d)
cleanup(){ chmod -R u+w "$F" >/dev/null 2>&1; rm -rf "$F"; }
trap cleanup EXIT INT TERM

# The vault: three levels up from the shipped location, or --vault DIR when the suite runs on a
# copy of the scripts elsewhere (a builder's /tmp draft); the fence is read from beside lane.py,
# else from the vault's shipped copy. CLAUDE_PROJECT_DIR points the wrapper at the same vault.
if [ -n "$VAULT_ARG" ]; then VAULT=$(cd "$VAULT_ARG" && pwd) || exit 2
else VAULT=$(cd "$HERE/../../.." && pwd); fi
export CLAUDE_PROJECT_DIR="$VAULT"
[ -f "$FENCE" ] || FENCE="$VAULT/.claude/skills/delegate/lane-fence.py"
# The shipped home's own three files, so the last leg can prove the suite left them alone.
HOME_BEFORE=$(shasum "$LANE" "$FENCE" "$0")

STORE="$F/store"
# mktemp -d hands back the unresolved /var form on this platform; the wrapper records real paths.
FR=$("$PY" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$F")
SR="$FR/store/spawn-records"
LHOME="$F/home"
PROJ="$F/projects"
BIN="$F/bin"
mkdir -p "$STORE" "$PROJ" "$BIN" "$F/granted" "$F/writable" "$F/elsewhere"
printf 'GRANTED\n' > "$F/granted/inside.txt"
printf 'ELSEWHERE\n' > "$F/elsewhere/outside.txt"

# ------------------------------------------------------------------ the stub `claude` -------
cat > "$BIN/claude" <<'STUB_SOURCE_TERMINATOR'
#!/usr/bin/env python3
"""Stub harness: records the call, writes a fixture transcript, prints a canned result."""
import json, os, re, sys, time

log = os.environ["STUB_LOG"]
os.makedirs(log, exist_ok=True)
argv = sys.argv[1:]
with open(os.path.join(log, "argv.txt"), "w") as h:
    h.write("\n".join(argv) + "\n")
with open(os.path.join(log, "cwd.txt"), "w") as h:
    h.write(os.getcwd() + "\n")
with open(os.path.join(log, "env.txt"), "w") as h:
    for key in ("LLM_WIKI_LANE", "LLM_WIKI_LANE_RUN", "LLM_WIKI_LANE_ID",
                "LLM_WIKI_LANE_GRANTS", "LLM_WIKI_LANE_WRITES", "LLM_WIKI_LANE_PROGRESS",
                "CLAUDE_CONFIG_DIR"):
        h.write("%s=%s\n" % (key, os.environ.get(key, "<unset>")))
with open(os.path.join(log, "stdin.txt"), "w") as h:
    h.write(sys.stdin.read())

sid = "no-session"
for flag in ("--session-id", "--resume"):
    if flag in argv:
        sid = argv[argv.index(flag) + 1]
delay = float(os.environ.get("STUB_SLEEP", "0"))
if delay:
    time.sleep(delay)

projects = os.environ.get("STUB_PROJECTS", "")
if projects:
    name = os.environ.get("STUB_PROJECT_DIR") or re.sub(r"[^A-Za-z0-9]", "-",
                                                        os.path.realpath(os.getcwd()))
    directory = os.path.join(projects, name)
    os.makedirs(directory, exist_ok=True)
    usage = {"input_tokens": 10, "cache_creation_input_tokens": 400,
             "cache_read_input_tokens": 5000, "output_tokens": 20,
             "cache_creation": {"ephemeral_1h_input_tokens": 400,
                                "ephemeral_5m_input_tokens": 0}}
    records = [{"type": "assistant", "effort": os.environ.get("STUB_EFFORT", "high"),
                "message": {"id": "m1", "model": "claude-sonnet-5", "role": "assistant",
                            "stop_reason": "end_turn", "usage": usage,
                            "content": [{"type": "text", "text": "stub transcript text"}]}}]
    if os.environ.get("STUB_FENCE"):
        records.append({"type": "user", "message": {"role": "user", "content": [
            {"type": "tool_result",
             "content": "lane-fence: `/nope/x` is outside the granted directories"}]}})
        records.append({"type": "attachment", "attachment": {
            "type": "hook_success", "hookName": "PreToolUse:Bash",
            "stdout": json.dumps({"hookSpecificOutput": {
                "permissionDecisionReason": "lane-fence: within grants"}})}})
    if os.environ.get("STUB_REFUSAL"):
        records.append({"type": "assistant", "effort": os.environ.get("STUB_EFFORT", "high"),
                        "message": {"id": "m2", "model": "claude-sonnet-5", "role": "assistant",
                                    "stop_reason": "refusal", "usage": usage,
                                    "content": [{"type": "text", "text": ""}]}})
    # The lane's own prose quoting the fence prefix back must NOT count as a denial.
    records.append({"type": "assistant", "effort": os.environ.get("STUB_EFFORT", "high"),
                    "message": {"id": "m3", "model": "claude-sonnet-5", "role": "assistant",
                                "stop_reason": "end_turn", "usage": usage,
                                "content": [{"type": "text",
                                             "text": "I saw lane-fence: outside the grants"}]}})
    if os.environ.get("STUB_SYNTHETIC"):
        # The limit-stop shape: a last assistant record with a synthetic model and zero usage.
        records.append({"type": "assistant", "message": {
            "id": "m9", "model": "<synthetic>", "role": "assistant", "stop_reason": None,
            "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0,
                      "cache_read_input_tokens": 0, "output_tokens": 0},
            "content": [{"type": "text", "text": "You've hit your session limit"}]}})
    with open(os.path.join(directory, sid + ".jsonl"), "w") as h:
        for record in records:
            h.write(json.dumps(record) + "\n")

# A lane that stays silent AFTER its transcript exists (STUB_SLEEP_AFTER seconds), optionally
# appending to its progress file every half second (STUB_PROGRESS) as a healthy long call does.
after = float(os.environ.get("STUB_SLEEP_AFTER", "0"))
progress = os.environ.get("LLM_WIKI_LANE_PROGRESS")
waited = 0.0
while waited < after:
    time.sleep(0.5)
    waited += 0.5
    if os.environ.get("STUB_PROGRESS") and progress:
        with open(progress, "a") as h:
            h.write("tick\n")

denials = []
if os.environ.get("STUB_DENIALS"):
    denials = [{"tool_name": "Read", "tool_input": {"file_path": "/nope/x"}}]
result = {"type": "result", "subtype": os.environ.get("STUB_SUBTYPE", "success"),
          "is_error": bool(os.environ.get("STUB_ISERROR")),
          "result": os.environ.get("STUB_REPORT", "stub report body"),
          "num_turns": 3, "total_cost_usd": 0.12, "permission_denials": denials,
          "modelUsage": {"claude-sonnet-5": {"inputTokens": 10, "outputTokens": 20}},
          "session_id": sid}
sys.stdout.write(json.dumps(result) + "\n")
sys.exit(int(os.environ.get("STUB_EXIT", "0")))
STUB_SOURCE_TERMINATOR
chmod +x "$BIN/claude"

# ----------------------------------------------------------------- the fixture routing ------
"$PY" - "$F" <<'ROUTING_FIXTURE_TERMINATOR'
import json, sys
root = sys.argv[1]

def row(models, mdef, efforts, edef, grants, extras, writes, tools, skills=None, sextras=None):
    return {"model": {"options": models, "default": mdef},
            "effort": {"options": efforts, "default": edef},
            "grants": {"default": grants, "extras": extras},
            "writes": writes, "tools": tools,
            "skills": {"default": skills or [], "extras": sextras or []},
            "mcp": {"default": [], "grantable": []},
            "cache": "1h", "gate": "fixture row, not the shipped table", "dated": "2026-09-04"}

table = {"schema": 2,
         "order": {"model": ["haiku", "sonnet", "opus", "fable"],
                   "effort": ["low", "medium", "high", "xhigh", "max"]},
         "classes": {
    "verifier": row(["sonnet", "opus", "fable"], "sonnet", ["high", "xhigh", "max"], "high",
                    ["<claim files>"], ["wiki", "raw"], [],
                    ["Read", "Grep", "Glob", "Bash"], ["lane-core"], ["markitdown"]),
    "memory-hunter": row(["sonnet", "opus"], "sonnet", ["high", "xhigh", "max"], "high",
                         ["wiki"], ["raw"], ["<memory dir>"], ["Read", "Grep", "Glob"]),
    "wiki-compile": row(["sonnet", "opus", "fable"], "opus",
                        ["medium", "high", "xhigh", "max"], "xhigh",
                        ["wiki", "<assigned raw files>"], ["raw", "assets"], [],
                        ["Read", "Grep", "Glob", "Bash", "Write", "Edit"],
                        ["lane-core", "compile-core"], ["markitdown"]),
    "builder": row(["sonnet", "opus", "fable"], "opus", ["high", "xhigh", "max"], "high",
                   ["<target dirs>"], ["wiki"], ["<target dirs>"],
                   ["Read", "Grep", "Glob", "Bash", "Write", "Edit"]),
    "critic": row(["opus", "fable"], "opus", ["xhigh", "max"], "max",
                  ["<artefact files>", "<contract files>"], ["wiki", "raw"], [],
                  ["Read", "Grep", "Glob", "Bash"]),
    "planner": row(["opus", "fable"], "opus", ["high", "xhigh", "max"], "max",
                   ["wiki", "<batch listing>"], [], [], ["Read", "Grep", "Glob"]),
    "reflector": row(["opus", "fable"], "opus", ["high", "xhigh", "max"], "max",
                     ["<transcript>"], ["wiki"], [], ["Read", "Grep", "Glob"],
                     ["lane-core", "reflect-slice"]),
    "gate-judge": row(["opus"], "opus", ["max"], "max", ["<fixture>"], [], [],
                      ["Read", "Grep", "Glob"])}}

with open(root + "/routing-v2.json", "w") as handle:
    json.dump(table, handle, indent=1)
# Two broken tables for the premise legs.
with open(root + "/routing-v1.json", "w") as handle:
    json.dump({"order": table["order"], "roles": {}}, handle)
broken = json.loads(json.dumps(table))
del broken["classes"]["verifier"]["tools"]
with open(root + "/routing-noTools.json", "w") as handle:
    json.dump(broken, handle)
badslice = json.loads(json.dumps(table))
badslice["classes"]["reflector"]["skills"]["default"] = ["lane-core", "no-such-slice"]
with open(root + "/routing-badslice.json", "w") as handle:
    json.dump(badslice, handle)
ROUTING_FIXTURE_TERMINATOR

R="$F/routing-v2.json"
printf 'Do the thing and report.\n' > "$F/brief.md"

# A fixture vault for every offline spawn: the live .claude tree, CLAUDE.md, wiki, raw and assets
# reached through symlinks, plus its own CUSTOMISATION.md, so no leg depends on the live Settings
# line (a live `delegation: auto` would, by design, fail every flagless spawn). The wrapper
# resolves each symlinked grant to its real path, so the vault-reference legs still see the live
# vault path where a row literal names it.
mkvault(){ # $1 = vault dir, $2 = the delegation line (empty for none)
  mkdir -p "$1"
  for entry in .claude CLAUDE.md wiki raw assets; do
    [ -e "$VAULT/$entry" ] && ln -s "$VAULT/$entry" "$1/$entry"
  done
  { printf '## Settings\n- **throttle**: default\n- **breadth**: standard\n'
    [ -n "$2" ] && printf '%s\n' "$2"; } > "$1/CUSTOMISATION.md"
}
FXV="$F/vault"
mkvault "$FXV" '- **delegation**: single — the fixture regime'

# One environment for every offline wrapper call.
mkdir -p "$F/progress"
LANEV="env -u CLAUDE_CONFIG_DIR PATH=$BIN:$PATH LLM_WIKI_STORE=$STORE STUB_LOG=$F/stub STUB_PROJECTS=$PROJ CLAUDE_PROJECT_DIR=$FXV LLM_WIKI_PROGRESS_DIR=$F/progress"
spawn(){ $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
         --projects-root "$PROJ" "$@"; }

echo "== offline =="

# 1–5 · init ---------------------------------------------------------------------------------
INIT1=$("$PY" "$LANE" init --home "$LHOME" 2>&1); IRC=$?
MISS=0
for f in lane-settings.json lane-fence.py contract/schema-s4.md contract/confidence-rubric.md; do
  [ -f "$LHOME/$f" ] || MISS=$((MISS + 1))
done
if [ "$IRC" = 0 ] && [ "$MISS" = 0 ]; then ok "init builds the lane home's four artefacts"
else no "init did not build the lane home  [exit $IRC, $MISS missing]"; fi

if grep -q 'lane-fence.py' "$LHOME/lane-settings.json" \
   && grep -q '"PreToolUse"' "$LHOME/lane-settings.json" \
   && ! grep -q 'mcpServers' "$LHOME/lane-settings.json"; then
  ok "lane settings carry the Bash fence hook and no MCP servers"
else no "lane settings are wrong  [$(cat "$LHOME/lane-settings.json")]"; fi

BEFORE_SLICE=$(shasum "$LHOME/contract/schema-s4.md" | cut -d' ' -f1)
INIT2=$("$PY" "$LANE" init --home "$LHOME" 2>&1)
AFTER_SLICE=$(shasum "$LHOME/contract/schema-s4.md" | cut -d' ' -f1)
KEPT=$(printf '%s' "$INIT2" | grep -c 'kept')
if [ "$BEFORE_SLICE" = "$AFTER_SLICE" ] && [ "$KEPT" -ge 4 ]; then
  ok "init is idempotent: $KEPT artefacts kept, the slice byte-identical"
else no "init is not idempotent  [kept $KEPT, slice changed: $([ "$BEFORE_SLICE" = "$AFTER_SLICE" ] && echo no || echo yes)]"; fi

# Positive control for the leg above: a drifted slice must be regenerated, not kept.
printf 'DRIFT\n' > "$LHOME/contract/schema-s4.md"
INIT3=$("$PY" "$LANE" init --home "$LHOME" 2>&1)
RESTORED=$(shasum "$LHOME/contract/schema-s4.md" | cut -d' ' -f1)
if printf '%s' "$INIT3" | grep -q 'regenerated .*schema-s4' && [ "$RESTORED" = "$BEFORE_SLICE" ]; then
  ok "init regenerates a drifted slice (control: the 'kept' leg above is not vacuous)"
else no "init kept a drifted slice  [$(printf '%s' "$INIT3" | grep schema-s4)]"; fi

# The same probe against a vault that carries neither the core nor the slice source: init
# must name both and still succeed, since a fresh machine has them only after a pull.
mkdir -p "$F/fakevault/wiki/developments"
cp "$VAULT/CLAUDE.md" "$F/fakevault/CLAUDE.md"
cp "$VAULT/wiki/developments/wiki-confidence-levels.md" "$F/fakevault/wiki/developments/"
INITB=$(env CLAUDE_PROJECT_DIR="$F/fakevault" "$PY" "$LANE" init --home "$F/home-bare" 2>&1)
RC=$?
if [ "$RC" = 0 ] && printf '%s' "$INITB" | grep -q 'lane-home-src' \
   && printf '%s' "$INITB" | grep -q 'lane-core.md' \
   && printf '%s' "$INIT1" | grep -q 'created .*lane-core.md'; then
  ok "init names a missing core and slice source and still succeeds (control: the real vault's init created both)"
else no "init on a vault without the core or the slices  [exit $RC: $INITB]"; fi


# 6 · the record exists even when the process fails ------------------------------------------
env STUB_EXIT=9 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-a --lane L1 --class verifier \
  --grant "$F/granted" --record "$F/rec-a.jsonl" --reason 'leg 6' >/dev/null 2>&1
RC=$?
OPENS=$(grep -c '"event": "lane-open"' "$F/rec-a.jsonl" 2>/dev/null || echo 0)
if [ "$OPENS" = 1 ] && [ "$RC" = 3 ]; then
  ok "the lane-open record is written before the process starts (stub exit 9 -> wrapper exit 3)"
else no "record-before-spawn  [opens $OPENS, exit $RC]"; fi

# 7–11 · the composed call --------------------------------------------------------------------
spawn --run run-test-b --lane L2 --class verifier --grant "$F/granted" \
      --record "$F/rec-b.jsonl" --reason 'leg 7' >/dev/null 2>&1
A="$F/stub/argv.txt"
MISSING=""
for flag in -p --agents --agent --model --effort --restricted --tools --settings \
            --strict-mcp-config --session-id --max-budget-usd --permission-prompts \
            --output-format --add-dir; do
  grep -qx -- "$flag" "$A" || MISSING="$MISSING $flag"
done
if [ -z "$MISSING" ]; then ok "every required flag is on the command line"
else no "flags missing: $MISSING"; fi

if grep -qx -- '--mcp-config' "$A"; then no "--mcp-config appears without a grant"
else ok "--mcp-config is absent unless granted"; fi
if grep -qx -- '--permission-mode' "$A"; then no "acceptEdits on a read-only lane"
else ok "no --permission-mode on a read-only lane"; fi

E="$F/stub/env.txt"
if grep -q "^LLM_WIKI_LANE=1$" "$E" && grep -q "^LLM_WIKI_LANE_RUN=run-test-b$" "$E" \
   && grep -q "LLM_WIKI_LANE_GRANTS=.*$F/granted" "$E" && grep -q "LLM_WIKI_LANE_GRANTS=.*:/tmp" "$E" \
   && grep -q "^LLM_WIKI_LANE_WRITES=$" "$E"; then
  ok "the spawn environment carries the grants, the home, /tmp and an empty write set"
else no "spawn environment wrong  [$(cat "$E")]"; fi

DEF=$("$PY" - "$A" <<'DEFJSON_TERMINATOR'
import json, sys
argv = open(sys.argv[1]).read().split("\n")
blob = json.loads(argv[argv.index("--agents") + 1])
agent = blob["verifier"]
print(json.dumps({"keys": sorted(agent), "tools": agent["tools"],
                  "skills": agent.get("skills"), "body": agent["prompt"][:40]}))
DEFJSON_TERMINATOR
)
if printf '%s' "$DEF" | grep -q '"effort"'; then no "the thin definition still carries effort"
else ok "the thin definition carries no effort field (it is a spawn flag, not a definition field)"; fi
if printf '%s' "$DEF" | grep -q '"skills": null' && printf '%s' "$DEF" | grep -q 'Read'; then
  ok "the thin definition carries the row's tools and never a skills key (measured not to load)"
else no "thin definition wrong  [$DEF]"; fi

# The same probe must see a skills list when the class has one: the control for the leg above.
spawn --run run-test-c --lane L3 --class wiki-compile --grant "$F/granted" \
      --write "$F/writable" --record "$F/rec-c.jsonl" --reason 'leg 11 control' >/dev/null 2>&1
DEF2=$("$PY" - "$A" <<'DEFJSON2_TERMINATOR'
import json, sys
argv = open(sys.argv[1]).read().split("\n")
blob = json.loads(argv[argv.index("--agents") + 1])
print(json.dumps(blob["wiki-compile"].get("skills")))
DEFJSON2_TERMINATOR
)
eq "a class WITH default slices still gets no skills key in its definition" "$DEF2" "null"
if grep -qx -- '--permission-mode' "$A" && grep -qx -- 'acceptEdits' "$A"; then
  ok "acceptEdits is set for a write lane (control for the read-only leg above)"
else no "a write lane did not get acceptEdits"; fi
if grep -q "LLM_WIKI_LANE_WRITES=.*$F/writable" "$E"; then
  ok "the write set reaches the lane environment"
else no "write set missing from the environment  [$(grep WRITES "$E")]"; fi

# the appended system-prompt file: the single carrier of the core and the row's slices --------
CORESRC="$VAULT/.claude/skills/delegate/templates/lane-core.md"
appended(){ cat "$STORE/spawn-records/$1-appended-$2.md" 2>/dev/null; }
headings(){ appended "$1" "$2" | grep -c '^## Lane slice: '; }

spawn --run run-test-ap1 --lane A1 --class verifier --grant "$F/granted" \
      --record "$F/rec-ap1.jsonl" --reason 'appended: core only' >/dev/null 2>&1
if [ "$(headings run-test-ap1 A1)" = 1 ] \
   && appended run-test-ap1 A1 | grep -q '^## Lane slice: lane-core — source: '; then
  ok "a class with no slice beyond the core appends the core alone, under its named heading"
else no "verifier appended file  [$(appended run-test-ap1 A1 | grep '^## Lane slice')]"; fi

spawn --run run-test-ap2 --lane A2 --class wiki-compile --grant "$F/granted" \
      --record "$F/rec-ap2.jsonl" --reason 'appended: core + compile-core' >/dev/null 2>&1
CORE_MARK=$(head -1 "$CORESRC")
if appended run-test-ap2 A2 | grep -q '^## Lane slice: compile-core — source: .*lane-home-src/compile-core/SKILL.md' \
   && appended run-test-ap2 A2 | grep -qF "$CORE_MARK" \
   && [ "$(headings run-test-ap2 A2)" = 2 ]; then
  ok "a compile spawn appends the core's own text plus compile-core, each under its source heading"
else no "compile appended file  [$(appended run-test-ap2 A2 | grep '^## Lane slice')]"; fi

APREC=$("$PY" - "$F/rec-ap2.jsonl" "$STORE/spawn-records/run-test-ap2-appended-A2.md" <<'APPENDED_TERMINATOR'
import json, os, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-open":
        print(json.dumps({"appended": record["appended"],
                          "matches": record["appended_bytes"] == os.path.getsize(sys.argv[2])}))
APPENDED_TERMINATOR
)
eq "the lane-open record names what was appended and its byte size" \
   "$APREC" '{"appended": ["lane-core", "compile-core"], "matches": true}'

spawn --run run-test-ap3 --lane A3 --class reflector --grant "$F/granted" \
      --record "$F/rec-ap3.jsonl" --reason 'appended: core + reflect-slice' >/dev/null 2>&1
if appended run-test-ap3 A3 | grep -q '^## Lane slice: reflect-slice — source: ' \
   && [ "$(headings run-test-ap3 A3)" = 2 ]; then
  ok "a reflector spawn appends reflect-slice beside the core"
else no "reflector appended file  [$(appended run-test-ap3 A3 | grep '^## Lane slice')]"; fi

if grep -qx -- '--append-system-prompt-file' "$A" \
   && grep -qx -- "$SR/run-test-ap3-appended-A3.md" "$A"; then
  ok "the appended file is the one passed with --append-system-prompt-file"
else no "the appended file was not passed to the harness"; fi

spawn --run run-test-ap4 --lane A4 --class wiki-compile --grant "$F/granted" --no-core \
      --record "$F/rec-ap4.jsonl" --reason 'appended: --no-core' >/dev/null 2>&1
if [ "$(headings run-test-ap4 A4)" = 1 ] \
   && appended run-test-ap4 A4 | grep -q '^## Lane slice: compile-core' \
   && ! appended run-test-ap4 A4 | grep -q '^## Lane slice: lane-core'; then
  ok "--no-core drops the core and keeps the slices (control: the two-heading leg above)"
else no "--no-core  [$(appended run-test-ap4 A4 | grep '^## Lane slice')]"; fi

# 12–16 · outputs and the close line ----------------------------------------------------------
if [ -s "$STORE/spawn-records/run-test-b-definition-L2.md" ] \
   && grep -q 'verifier' "$STORE/spawn-records/run-test-b-definition-L2.md"; then
  ok "the thin definition copy is saved beside the record"
else no "no definition copy saved"; fi

if [ "$(cat "$STORE/spawn-records/run-test-b-report-L2.md")" = "stub report body" ]; then
  ok "the report is persisted from the result JSON"
else no "report not persisted  [$(cat "$STORE/spawn-records/run-test-b-report-L2.md" 2>&1)]"; fi

BRIEFED=$(cat "$F/stub/stdin.txt")
eq "the brief is delivered on stdin" "$BRIEFED" "$(cat "$F/brief.md")"

env STUB_FENCE=1 STUB_DENIALS=1 STUB_EFFORT=xhigh $LANEV "$PY" "$LANE" spawn --home "$LHOME" \
  --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-d --lane L4 \
  --class verifier --grant "$F/granted" --effort xhigh --record "$F/rec-d.jsonl" \
  --reason 'leg 15' >/dev/null 2>&1
RC=$?
CLOSE=$("$PY" - "$F/rec-d.jsonl" <<'CLOSE_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-closed":
        print(json.dumps({"effort": record["effort_applied"], "tier": record["cache_write_tier"],
                          "fence": record["denials"]["fence"],
                          "allows": record["denials"]["fence_allows"],
                          "tool": record["denials"]["tool"], "exit": record["exit_class"],
                          "peak": record["usage"]["peak_context"]}))
CLOSE_TERMINATOR
)
eq "the close line reads effort, tier, fence and tool denials from the fixture transcript" \
   "$CLOSE" '{"effort": ["xhigh"], "tier": ["1h"], "fence": 1, "allows": 1, "tool": 1, "exit": "completed", "peak": 5410}'
eq "permission denials are reported, not treated as an error" "$RC" "0"

env STUB_REFUSAL=1 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-e --lane L5 --class verifier \
  --grant "$F/granted" --record "$F/rec-e.jsonl" --reason 'leg 17' >/dev/null 2>&1
eq "a refusal in the transcript closes the lane at exit 3" "$?" "3"
grep -q '"exit_class": "refusal"' "$F/rec-e.jsonl" \
  && ok "the close line names the refusal" || no "close line does not name the refusal"

env STUB_SUBTYPE=error_max_budget_usd $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-f --lane L6 --class verifier \
  --grant "$F/granted" --record "$F/rec-f.jsonl" --reason 'leg 19' >/dev/null 2>&1
RC=$?
if [ "$RC" = 3 ] && grep -q '"exit_class": "budget"' "$F/rec-f.jsonl"; then
  ok "a budget stop closes the lane at exit 3 and says so"
else no "budget stop mishandled  [exit $RC]"; fi

# 20 · the deadline path ----------------------------------------------------------------------
START=$(date +%s)
env STUB_SLEEP=30 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-g --lane L7 --class verifier \
  --grant "$F/granted" --deadline-s 2 --record "$F/rec-g.jsonl" --reason 'leg 20' >/dev/null 2>&1
RC=$?; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 3 ] && grep -q '"exit_class": "deadline"' "$F/rec-g.jsonl" && [ "$ELAPSED" -lt 25 ]; then
  ok "the deadline kills the process group and records it (${ELAPSED}s against a 30s stub)"
else no "deadline path  [exit $RC, ${ELAPSED}s]"; fi

# 21 · the glob fallback for a transcript in an unexpected directory ---------------------------
env STUB_PROJECT_DIR=some-other-name $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
  --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-h --lane L8 --class verifier \
  --grant "$F/granted" --record "$F/rec-h.jsonl" --reason 'leg 21' >/dev/null 2>&1
if grep -q '"effort_applied": \[' "$F/rec-h.jsonl"; then
  ok "a transcript in an unexpected project directory is still found by the session-id glob"
else no "the glob fallback did not find the transcript"; fi

# 22–26 · the throttle mapping and out-of-range choices ----------------------------------------
tier(){ $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
        --run run-test-t --lane T --class wiki-compile --grant "$F/granted" --dry-run \
        --throttle "$1" 2>/dev/null \
        | grep '^  claude' | tr ' ' '\n' | grep -A1 -x -e --model -e --effort | grep -v '^--' \
        | tr '\n' ' '; }
eq "throttle default -> the row's default"      "$(tier default)"    "opus xhigh "
eq "throttle top -> the strongest options"      "$(tier top)"        "fable max "
eq "throttle cheap -> the weakest options"      "$(tier cheap)"      "sonnet medium "
eq "throttle fast -> default model, weakest effort" "$(tier fast)"   "opus medium "
eq "throttle cheap-fast -> weakest of both"     "$(tier cheap-fast)" "sonnet medium "

OUT=$(spawn --run run-test-i --lane L9 --class verifier --grant "$F/granted" --model haiku \
      --record "$F/rec-i.jsonl" --dry-run 2>&1)
if printf '%s' "$OUT" | grep -q 'outside_options'; then
  ok "a model outside the class options is recorded as such"
else no "an out-of-range model was not recorded"; fi

# per-call slots in a routing row -------------------------------------------------------------
spawn --run run-test-ph1 --lane B1 --class builder --write "$F/writable" \
      --record "$F/rec-ph1.jsonl" --reason 'slot filled by --write' >/dev/null 2>&1
PH1=$("$PY" - "$F/rec-ph1.jsonl" <<'SLOT_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-open":
        tokens = [p for p in record["grants"] + record["writes"] if "<" in p]
        print(json.dumps({"writes": record["writes"], "granted": record["writes"][0] in record["grants"],
                          "tokens": tokens}))
SLOT_TERMINATOR
)
if printf '%s' "$PH1" | grep -q '"granted": true' && printf '%s' "$PH1" | grep -q '"tokens": \[\]' \
   && printf '%s' "$PH1" | grep -q "$F/writable"; then
  ok "a write slot is filled by --write, and the record carries the resolved path, never the token"
else no "builder write slot  [$PH1]"; fi

MEMREL=".claude/agent-memory-local/memory-hunter"
if [ -d "$LHOME/$MEMREL" ]; then
  spawn --run run-test-ph2 --lane B2 --class memory-hunter \
        --record "$F/rec-ph2.jsonl" --reason 'slot filled by the home memory dir' >/dev/null 2>&1
  if grep -q "$MEMREL" "$F/rec-ph2.jsonl"; then
    ok "a memory class's write slot resolves to its own directory in the home, with no flag"
  else no "memory slot did not auto-resolve  [$(grep -o '"writes": \[[^]]*\]' "$F/rec-ph2.jsonl")]"; fi
else no "init did not materialise the memory directory the leg needs"; fi

spawn --run run-test-ph3 --lane B3 --class verifier --grant "$F/granted" \
      --record "$F/rec-ph3.jsonl" --reason 'read slot filled by --grant' >/dev/null 2>&1
if grep -q "$F/granted" "$F/rec-ph3.jsonl" && ! grep -q 'claim files' "$F/rec-ph3.jsonl"; then
  ok "a read slot is filled by --grant, and the token never reaches the record"
else no "verifier read slot  [$(grep -o '"grants": \[[^]]*\]' "$F/rec-ph3.jsonl")]"; fi

# --grants-only: a fixture-bound lane sees nothing of the live vault ---------------------------
mkdir -p "$F/fx"
# mktemp -d hands back the unresolved /var form on this platform while every path the wrapper
# records is symlink-resolved (/private/var/...), so the exact-match assertions use the
# resolved form; a substring test on the unresolved one would pass vacuously.
FXR=$("$PY" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$F/fx")
vaultrefs(){ # how many times the vault root appears in the record and in the --add-dir args
  R=$(grep -c -- "$VAULT" "$1"); [ -n "$R" ] || R=0
  G=$("$PY" - "$A" "$VAULT" <<'ADDDIR_TERMINATOR'
import sys
argv = open(sys.argv[1]).read().split("\n")
print(sum(1 for i, a in enumerate(argv)
          if a == "--add-dir" and i + 1 < len(argv) and argv[i + 1].startswith(sys.argv[2])))
ADDDIR_TERMINATOR
)
  echo "$R/$G"
}
spawn --run run-test-go1 --lane G1 --class wiki-compile --grants-only --grant "$F/fx" \
      --write "$F/fx" --record "$F/rec-go1.jsonl" --reason 'fixture-bound' >/dev/null 2>&1
GO1=$(vaultrefs "$F/rec-go1.jsonl")
GOENV=$(cat "$E")            # the environment of THIS spawn, before the control overwrites it
spawn --run run-test-go2 --lane G2 --class wiki-compile --grant "$F/fx" --write "$F/fx" \
      --record "$F/rec-go2.jsonl" --reason 'control: row literals kept' >/dev/null 2>&1
GO2=$(vaultrefs "$F/rec-go2.jsonl")
if [ "$GO1" = "0/0" ] && [ "$GO2" != "0/0" ]; then
  ok "--grants-only keeps every vault path out of the record and out of --add-dir (control: $GO2 vault references without the flag)"
else no "--grants-only scope  [with flag $GO1, without $GO2 — want 0/0 and non-zero]"; fi
if grep -q '"row_literals_dropped": \["wiki"\]' "$F/rec-go1.jsonl"; then
  ok "the dropped row literals are named in the record, not discarded quietly"
else no "row_literals_dropped  [$(grep -o '\"row_literals_dropped\": \[[^]]*\]' "$F/rec-go1.jsonl")]"; fi
if grep -q "\"$FXR\"" "$F/rec-go1.jsonl"; then
  ok "the row's per-call slot is still filled from the call under --grants-only"
else no "the slot was not filled under --grants-only"; fi
if printf '%s\n' "$GOENV" | grep -q "LLM_WIKI_LANE_GRANTS=$FXR:" \
   && printf '%s\n' "$GOENV" | grep -q "LLM_WIKI_LANE_WRITES=$FXR$" \
   && ! printf '%s\n' "$GOENV" | grep -q -- "$VAULT"; then
  ok "the fence environment carries exactly the call's scope, with no vault path in it"
else no "fence environment under --grants-only  [$(printf '%s\n' "$GOENV" | grep GRANTS)]"; fi

# 27–33 · premise failures: exit 2, no record --------------------------------------------------
premise(){ # name, expected-fragment, args...
  NAME="$1"; FRAG="$2"; shift 2
  rm -f "$F/rec-p.jsonl"
  ERR=$($LANEV "$PY" "$LANE" spawn --projects-root "$PROJ" --record "$F/rec-p.jsonl" "$@" 2>&1)
  RC=$?
  if [ "$RC" = 2 ] && [ ! -f "$F/rec-p.jsonl" ] && printf '%s' "$ERR" | grep -q "$FRAG"; then
    ok "premise: $NAME (exit 2, no record)"
  else no "premise: $NAME  [exit $RC, record $([ -f "$F/rec-p.jsonl" ] && echo written || echo absent), said: $ERR]"; fi
}
premise "no lane home"        "run \`lane.py init\`" --home "$F/nohome" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier
premise "unknown class"       "unknown class"        --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class no-such-class
premise "routing schema 1"    "schema"               --home "$LHOME" --routing "$F/routing-v1.json" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier
premise "routing field missing" "has no \`tools\`"   --home "$LHOME" --routing "$F/routing-noTools.json" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/granted"
premise "brief missing"       "brief file not found" --home "$LHOME" --routing "$R" \
        --brief "$F/no-brief.md" --run run-test-p --lane P --class verifier
premise "default slice missing" "resolves nowhere" --home "$LHOME" \
        --routing "$F/routing-badslice.json" --brief "$F/brief.md" --run run-test-p --lane P \
        --class reflector --grant "$F/granted"
premise "grant that does not exist" "does not exist" --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/no-such-dir"
premise "a write slot the call left empty" "needs --write for <target dirs>" --home "$LHOME" \
        --routing "$R" --brief "$F/brief.md" --run run-test-p --lane P --class builder \
        --grant "$F/granted"
premise "a read slot the call left empty" "needs --grant for <fixture>" --home "$LHOME" \
        --routing "$R" --brief "$F/brief.md" --run run-test-p --lane P --class gate-judge
premise "--grants-only with no --grant" "needs at least one --grant" --home "$LHOME" \
        --routing "$R" --brief "$F/brief.md" --run run-test-p --lane P --class wiki-compile \
        --grants-only --write "$F/fx"

mkdir -p "$F/rolock"; : > "$F/rolock/rec.jsonl"; chmod a-w "$F/rolock/rec.jsonl" "$F/rolock"
ERR=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
      --projects-root "$PROJ" --run run-test-p --lane P --class verifier --grant "$F/granted" \
      --record "$F/rolock/rec.jsonl" 2>&1)
RC=$?; chmod u+w "$F/rolock" "$F/rolock/rec.jsonl"
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'not writable'; then
  ok "premise: an unwritable spawn record (exit 2)"
else no "an unwritable record did not stop the spawn  [exit $RC: $ERR]"; fi

# 35 · --dry-run writes nothing ---------------------------------------------------------------
DRYMAN1=$(find "$STORE" "$LHOME" -type f -exec shasum {} \; | sort)
DRYOUT=$(spawn --run run-test-dry --lane D1 --class wiki-compile --grant "$F/granted" \
         --write "$F/writable" --record "$F/rec-dry.jsonl" --dry-run 2>&1)
DRYMAN2=$(find "$STORE" "$LHOME" -type f -exec shasum {} \; | sort)
if [ "$DRYMAN1" = "$DRYMAN2" ] && [ ! -f "$F/rec-dry.jsonl" ] \
   && printf '%s' "$DRYOUT" | grep -q 'claude -p --agents' \
   && printf '%s' "$DRYOUT" | grep -q 'LLM_WIKI_LANE_GRANTS='; then
  ok "--dry-run prints the full command, the environment and the record line, and writes nothing"
else no "--dry-run wrote something or printed too little"; fi

# ------------------------------------------------------ the delegation regime in the record ---
# Resolved from the flags or the Settings line; `auto`, an absent line or any other value is a
# premise failure, so the record never carries a regime nobody chose.
echo "== delegation =="
modeof(){ "$PY" - "$1" <<'MODEOF_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("event") == "lane-open":
        print("%s/%s/%s" % (record.get("mode"), record.get("mode_src"), record.get("mode_from")))
MODEOF_TERMINATOR
}
# $1 = vault dir (the CLAUDE_PROJECT_DIR override goes AFTER $LANEV's own, so it wins), then args
dspawn(){ V="$1"; shift; $LANEV CLAUDE_PROJECT_DIR="$V" "$PY" "$LANE" spawn --home "$LHOME" \
          --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" --class verifier \
          --grant "$F/granted" "$@"; }
eq "a Settings single passes through to the record with source owner (the leg-7 spawn)" \
   "$(modeof "$F/rec-b.jsonl")" 'single/owner/the Settings `delegation` line'

mkvault "$F/vault-auto"   '- **delegation**: auto — the head resolves per run'
mkvault "$F/vault-legacy" '- **mode**: multi — the pre-rename line'
mkvault "$F/vault-legauto" '- **mode**: auto — the pre-rename line, unresolved'
mkvault "$F/vault-noline" ''
dpremise(){ # name, expected-fragment, vault, args...
  NAME="$1"; FRAG="$2"; V="$3"; shift 3
  rm -f "$F/rec-dp.jsonl"
  ERR=$(dspawn "$V" --run run-test-dp --lane DP --record "$F/rec-dp.jsonl" "$@" 2>&1); RC=$?
  if [ "$RC" = 2 ] && [ ! -f "$F/rec-dp.jsonl" ] && printf '%s' "$ERR" | grep -qF -- "$FRAG"; then
    ok "premise: $NAME (exit 2, no record)"
  else no "premise: $NAME  [exit $RC, record $([ -f "$F/rec-dp.jsonl" ] && echo written || echo absent), said: $ERR]"; fi
}
dpremise "Settings auto without --delegation" 'the Settings line is `auto`' "$F/vault-auto"
dpremise "a Settings line that is absent" 'the Settings line is absent' "$F/vault-noline"
dpremise "a pre-rename mode line reading auto" 'the Settings line is `auto`' "$F/vault-legauto"
dpremise "--delegation without --delegation-src" 'go together' "$F/vault-auto" --delegation multi
dpremise "--delegation-src without --delegation" 'go together' "$F/vault-auto" --delegation-src head
ERR=$(dspawn "$F/vault-auto" --run run-test-dp --lane DP --record "$F/rec-dp.jsonl" --delegation turbo \
      --delegation-src head 2>&1); RC=$?
if [ "$RC" = 2 ] && [ ! -f "$F/rec-dp.jsonl" ] && printf '%s' "$ERR" | grep -q 'invalid choice'; then
  ok "premise: a regime no run runs under is refused by the flag itself (exit 2, no record)"
else no "an invalid --delegation value got through  [exit $RC: $ERR]"; fi

dspawn "$F/vault-auto" --run run-test-dl --lane DL1 --record "$F/rec-dl1.jsonl" \
       --delegation multi --delegation-src head --reason 'resolved under auto' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && [ "$(modeof "$F/rec-dl1.jsonl")" = 'multi/head/--delegation' ] \
   && grep -q '^LLM_WIKI_LANE_RUN=run-test-dl$' "$E"; then
  ok "under Settings auto the flags carry the regime and its source into the record, and the lane spawns (control: the stub saw the run)"
else no "flags under auto  [exit $RC, record $(modeof "$F/rec-dl1.jsonl" 2>&1)]"; fi

dspawn "$F/vault-legacy" --run run-test-dl --lane DL2 --record "$F/rec-dl2.jsonl" \
       --reason 'legacy line' >/dev/null 2>&1
eq "a pre-rename mode line reading multi passes through with source owner and says which line" \
   "$(modeof "$F/rec-dl2.jsonl")" 'multi/owner/the Settings `mode (the pre-rename line)` line'

dspawn "$FXV" --run run-test-dl --lane DL3 --record "$F/rec-dl3.jsonl" \
       --delegation multi --delegation-src owner --reason 'the owner said do this multi' >/dev/null 2>&1
eq "the flags beat a Settings single (the owner's one-run word)" \
   "$(modeof "$F/rec-dl3.jsonl")" 'multi/owner/--delegation'

DRY=$(dspawn "$F/vault-auto" --run run-test-dl --lane DL4 --record "$F/rec-dl4.jsonl" \
      --delegation single --delegation-src head --dry-run 2>&1)
if printf '%s' "$DRY" | grep -q '"mode": "single", "mode_src": "head", "mode_from": "--delegation"' \
   && [ ! -f "$F/rec-dl4.jsonl" ]; then
  ok "--dry-run shows the resolved regime and source on the record line it would write"
else no "--dry-run record line  [$(printf '%s' "$DRY" | grep -o '"mode[^,]*,[^,]*,[^,]*')]"; fi

# ------------------------------------------------------------- the hands-off additions -------
# File-level grants, both spellings, the per-lane input directory, --grant-vault-root, the
# CONTROL+ refusal, the per-spawn settings, --config-dir, the report cut, the silence watch,
# watch, resume, the limit class and --detach (design page hands-off-mode-design: D8, D17–D20,
# D25; C2 N5, N6, N12). Every planted case has its clean control on the same probe.
echo "== hands-off =="
recfield(){ # record, event, key -> the key's value as sorted JSON, from the LAST such event
  "$PY" - "$1" "$2" "$3" <<'RECFIELD_TERMINATOR'
import json, sys
value = None
for line in open(sys.argv[1]):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("event") == sys.argv[2] and sys.argv[3] in record:
        value = record[sys.argv[3]]
print(json.dumps(value, sort_keys=True))
RECFIELD_TERMINATOR
}
events(){ N=$(grep -c "\"event\": \"$2\"" "$1"); [ -n "$N" ] || N=0; echo "$N"; }
adddirs(){ "$PY" - "$A" <<'ADDDIRS_TERMINATOR'
import sys
argv = open(sys.argv[1]).read().split("\n")
for i, a in enumerate(argv):
    if a == "--add-dir" and i + 1 < len(argv):
        print(argv[i + 1])
ADDDIRS_TERMINATOR
}
argafter(){ grep -A1 -x -- "$1" "$A" | tail -1; }
dirs_of(){ printf '%s\n' "$1" | grep '^add-dirs:' | sed 's/^add-dirs: //' | tr ' ' '\n'; }

# file-level grants, the per-spawn settings and the input directory ---------------------------
printf 'NOTE\n' > "$F/writable/note.md"
spawn --run run-test-fg --lane FG --class builder --grant "$F/granted/inside.txt" \
      --write "$F/writable/note.md" --record "$F/rec-fg.jsonl" --reason 'file-level grants' >/dev/null 2>&1
RC=$?
GF=$(recfield "$F/rec-fg.jsonl" lane-open grants_files); WF=$(recfield "$F/rec-fg.jsonl" lane-open writes_files)
if [ "$RC" = 0 ] && [ "$GF" = "[\"$FR/granted/inside.txt\", \"$FR/writable/note.md\"]" ] \
   && [ "$WF" = "[\"$FR/writable/note.md\"]" ]; then
  ok "a file passed to --grant or --write is accepted and recorded in grants_files / writes_files (real paths)"
else no "file-level grants  [exit $RC, grants_files $GF, writes_files $WF]"; fi
if grep -q "^LLM_WIKI_LANE_WRITES=$FR/writable/note.md$" "$E" \
   && grep -q "^LLM_WIKI_LANE_GRANTS=$FR/granted/inside.txt:$FR/writable/note.md:" "$E"; then
  ok "the fence environment carries the file paths themselves (a write file is also a read grant)"
else no "file grants in the fence environment  [$(grep LLM_WIKI_LANE_ "$E" | tr '\n' ' ')]"; fi
if adddirs | grep -qx "$FR/granted" && adddirs | grep -qx "$FR/writable" \
   && ! adddirs | grep -q 'inside.txt' && ! adddirs | grep -q 'note.md'; then
  ok "the file tools get each file's parent directory through --add-dir, never the file itself"
else no "--add-dir for file grants  [$(adddirs | tr '\n' ' ')]"; fi
SET="$STORE/spawn-records/run-test-fg-settings-FG.json"
if [ -f "$SET" ] && grep -qx -- "$SR/run-test-fg-settings-FG.json" "$A" \
   && grep -q "\"Edit(/$FR/writable/note.md)\"" "$SET" && grep -q "\"Write(/$FR/writable/note.md)\"" "$SET" \
   && grep -q 'lane-fence.py' "$SET" && grep -q '"PreToolUse"' "$SET"; then
  ok "the per-spawn settings file carries the home's hooks plus Edit/Write allow rules for the file write, and is what --settings names"
else no "per-spawn settings  [$(cat "$SET" 2>&1 | tr '\n' ' ')]"; fi
SETC="$STORE/spawn-records/run-test-c-settings-L3.json"; SETB="$STORE/spawn-records/run-test-b-settings-L2.json"
if grep -q "\"Edit(/$FR/writable/\*\*)\"" "$SETC" && grep -q "\"Write(/$FR/writable/\*\*)\"" "$SETC" \
   && ! grep -q 'permissions' "$SETB" && grep -q '"PreToolUse"' "$SETB"; then
  ok "a directory write allows its whole tree (dir/**); a read-only lane's settings carry the hooks and no allow list (control)"
else no "settings allow shapes  [$(grep -o 'Edit([^)]*)' "$SETC" | tr '\n' ' ') / permissions lines in the read-only file: $(grep -c permissions "$SETB")]"; fi
IN="$STORE/spawn-records/run-test-fg-in-FG"
if [ -f "$IN/run-test-fg-brief-FG.md" ] && cmp -s "$IN/run-test-fg-brief-FG.md" "$F/brief.md" \
   && [ "$(recfield "$F/rec-fg.jsonl" lane-open input_dir)" = "\"$SR/run-test-fg-in-FG\"" ] \
   && adddirs | grep -qx "$SR/run-test-fg-in-FG" && grep -q "^LLM_WIKI_LANE_GRANTS=.*:$SR/run-test-fg-in-FG:" "$E" \
   && ! adddirs | grep -qx "$SR"; then
  ok "each spawn gets its own input directory with the brief copied in, granted read in the fence and --add-dir; the store itself is not granted"
else no "the per-lane input directory  [$(ls "$IN" 2>&1 | tr '\n' ' '); add-dirs $(adddirs | tr '\n' ' ')]"; fi
spawn --run run-test-fg2 --lane FG2 --class verifier --grant "$STORE/spawn-records" \
      --record "$F/rec-fg2.jsonl" --reason 'control: the store named explicitly' >/dev/null 2>&1
if adddirs | grep -qx "$SR"; then ok "the store reaches --add-dir when a call names it (control for the leg above)"
else no "an explicit store grant did not reach --add-dir  [$(adddirs | tr '\n' ' ')]"; fi

# both spellings of a symlinked grant -----------------------------------------------------------
ln -s "$F/granted" "$F/link-granted"
spawn --run run-test-sl --lane SL --class verifier --grant "$F/link-granted" \
      --record "$F/rec-sl.jsonl" --reason 'a symlinked grant' >/dev/null 2>&1
if adddirs | grep -qx "$FR/granted" && adddirs | grep -qx "$F/link-granted" \
   && [ "$(recfield "$F/rec-sl.jsonl" lane-open grants)" = "[\"$FR/granted\"]" ]; then
  ok "a symlinked grant reaches --add-dir in both spellings and the record in its real path"
else no "symlink spellings  [$(adddirs | tr '\n' ' ')]"; fi
spawn --run run-test-sl2 --lane SL2 --class verifier --grant "$FR/granted" \
      --record "$F/rec-sl2.jsonl" --reason 'control: a real path' >/dev/null 2>&1
eq "a grant given as its real path is passed once (control for the two-spelling leg)" \
   "$(adddirs | grep -c '/granted$')" "1"

# --grant-vault-root -----------------------------------------------------------------------------
GV=$(spawn --run run-test-gv --lane GV --class verifier --grant "$F/granted" --record "$F/rec-gv.jsonl" \
     --grant-vault-root --dry-run 2>&1)
GV0=$(spawn --run run-test-gv --lane GV0 --class verifier --grant "$F/granted" --record "$F/rec-gv.jsonl" \
      --dry-run 2>&1)
if dirs_of "$GV" | grep -qx "$FR/vault" && printf '%s\n' "$GV" | grep -q '"grant_vault_root": true' \
   && printf '%s\n' "$GV" | grep '^  LLM_WIKI_LANE_GRANTS=' | sed 's/^  LLM_WIKI_LANE_GRANTS=//' | tr ':' '\n' | grep -qx "$FR/vault" \
   && ! dirs_of "$GV0" | grep -qx "$FR/vault" && printf '%s\n' "$GV0" | grep -q '"grant_vault_root": false' \
   && [ ! -f "$F/rec-gv.jsonl" ]; then
  ok "--grant-vault-root passes the real vault root through --add-dir and the fence grants and records the flag (control: absent without it)"
else no "--grant-vault-root  [$(dirs_of "$GV" | tr '\n' ' ')]"; fi

# CONTROL+ lines --------------------------------------------------------------------------------
printf 'Do the thing.\nCONTROL+: GRANTED in %s\n- CONTROL+: "Settings" in CUSTOMISATION.md\n' "$F/granted/inside.txt" > "$F/brief-ctl.md"
spawn --run run-test-ct --lane CT --class verifier --grant "$F/granted" --record "$F/rec-ct.jsonl" \
      --brief "$F/brief-ctl.md" --reason 'controls checked' >/dev/null 2>&1
RC=$?
WANT="[{\"file\": \"$FR/granted/inside.txt\", \"matches\": 1, \"phrase\": \"GRANTED\"}, {\"file\": \"$FR/vault/CUSTOMISATION.md\", \"matches\": 1, \"phrase\": \"Settings\"}]"
GOT=$(recfield "$F/rec-ct.jsonl" lane-open controls_checked)
if [ "$RC" = 0 ] && [ "$GOT" = "$WANT" ]; then
  ok "CONTROL+ lines are grepped before the spawn (a bulleted, quoted phrase and a vault-relative file included) and recorded as controls_checked"
else no "controls_checked  [exit $RC: $GOT]"; fi
printf 'x\nCONTROL+: NOPE-PHRASE-7731 in %s\n' "$F/granted/inside.txt" > "$F/brief-ctl-miss.md"
printf 'x\nCONTROL+: GRANTED in %s\n' "$F/granted/absent.txt" > "$F/brief-ctl-nofile.md"
printf 'x\nCONTROL+: GRANTED\n' > "$F/brief-ctl-bad.md"
premise "a CONTROL+ phrase that matches nothing refuses the spawn" "matches nothing" --home "$LHOME" \
        --routing "$R" --brief "$F/brief-ctl-miss.md" --run run-test-p --lane P --class verifier --grant "$F/granted"
premise "a CONTROL+ file that does not exist" "control file not found" --home "$LHOME" \
        --routing "$R" --brief "$F/brief-ctl-nofile.md" --run run-test-p --lane P --class verifier --grant "$F/granted"
premise "a malformed CONTROL+ line" "malformed control line" --home "$LHOME" \
        --routing "$R" --brief "$F/brief-ctl-bad.md" --run run-test-p --lane P --class verifier --grant "$F/granted"

# --config-dir ----------------------------------------------------------------------------------
mkdir -p "$F/cfg2"
spawn --run run-test-cfg --lane CF --class verifier --grant "$F/granted" --config-dir "$F/cfg2" \
      --record "$F/rec-cfg.jsonl" --reason 'a second login directory' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && grep -q "^CLAUDE_CONFIG_DIR=$F/cfg2$" "$E" \
   && [ "$(recfield "$F/rec-cfg.jsonl" lane-open config_dir)" = "\"$F/cfg2\"" ]; then
  ok "--config-dir sets CLAUDE_CONFIG_DIR for the lane process and is recorded on lane-open"
else no "--config-dir  [exit $RC, env $(grep CLAUDE_CONFIG_DIR "$E"), record $(recfield "$F/rec-cfg.jsonl" lane-open config_dir)]"; fi
spawn --run run-test-cfg0 --lane CF0 --class verifier --grant "$F/granted" \
      --record "$F/rec-cfg0.jsonl" --reason 'control: no config dir' >/dev/null 2>&1
if grep -q '^CLAUDE_CONFIG_DIR=<unset>$' "$E" && [ "$(recfield "$F/rec-cfg0.jsonl" lane-open config_dir)" = "null" ]; then
  ok "without the flag the lane inherits no CLAUDE_CONFIG_DIR and the record says null (control)"
else no "config dir control  [$(grep CLAUDE_CONFIG_DIR "$E")]"; fi
premise "--config-dir that is not a directory" "not a directory" --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/granted" --config-dir "$F/no-cfg"

# the report cut --------------------------------------------------------------------------------
LONG=$("$PY" -c 'print(" ".join("w%d" % i for i in range(1, 1001)))')
CUT=$(env STUB_REPORT="$LONG" $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
      --projects-root "$PROJ" --run run-test-cut --lane CU --class verifier --grant "$F/granted" \
      --record "$F/rec-cut.jsonl" --reason 'report cut' 2>&1)
RC=$?
REPF="$STORE/spawn-records/run-test-cut-report-CU.md"
if [ "$RC" = 0 ] && printf '%s\n' "$CUT" | grep -qF "(800 of 1000 words shown; full text: $SR/run-test-cut-report-CU.md)" \
   && printf '%s\n' "$CUT" | grep -qw 'w800' && ! printf '%s\n' "$CUT" | grep -qw 'w801' \
   && [ "$(wc -w < "$REPF" | tr -d ' ')" = 1000 ] \
   && [ "$(recfield "$F/rec-cut.jsonl" lane-closed report_words)" = 1000 ] \
   && [ "$(recfield "$F/rec-cut.jsonl" lane-closed report_cut)" = true ] \
   && printf '%s\n' "$CUT" | grep -q 'report 800/1000 words (cut)'; then
  ok "a 1000-word report is cut to 800 words on stdout with the pointer line, persisted whole, and recorded as report_words 1000 / report_cut true"
else no "the report cut  [exit $RC; $(printf '%s\n' "$CUT" | grep -c .) lines; $(printf '%s\n' "$CUT" | grep 'words shown')]"; fi
SHORT=$(spawn --run run-test-cut2 --lane CU2 --class verifier --grant "$F/granted" --record "$F/rec-cut2.jsonl" \
        --reason 'control: a short report' 2>&1)
FIVE=$(env STUB_REPORT="$LONG" $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
       --projects-root "$PROJ" --run run-test-cut3 --lane CU3 --class verifier --grant "$F/granted" \
       --record "$F/rec-cut3.jsonl" --report-words 5 2>&1)
if printf '%s\n' "$SHORT" | grep -q '(3 of 3 words shown; full text: ' \
   && [ "$(recfield "$F/rec-cut2.jsonl" lane-closed report_cut)" = false ] \
   && printf '%s\n' "$FIVE" | grep -q '(5 of 1000 words shown; full text: ' \
   && printf '%s\n' "$FIVE" | grep -qw 'w5' && ! printf '%s\n' "$FIVE" | grep -qw 'w6'; then
  ok "a short report is shown whole (report_cut false) and --report-words sets the cut (controls)"
else no "report cut controls  [$(printf '%s\n' "$SHORT" | grep 'words shown') / $(printf '%s\n' "$FIVE" | grep 'words shown')]"; fi

# the silence watch -----------------------------------------------------------------------------
START=$(date +%s)
env STUB_SLEEP_AFTER=20 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st1 --lane S1 --class verifier --grant "$F/granted" \
  --silence-s 2 --poll-s 1 --record "$F/rec-st1.jsonl" --reason 'a silent lane' >/dev/null 2>&1
RC=$?; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 5 ] && grep -q '"event": "stall"' "$F/rec-st1.jsonl" && grep -q '"reason": "silent"' "$F/rec-st1.jsonl" \
   && grep -q '"exit_class": "stall"' "$F/rec-st1.jsonl" && grep -q '"by": "spawn"' "$F/rec-st1.jsonl" \
   && [ "$ELAPSED" -lt 15 ]; then
  ok "a lane silent past --silence-s is killed: stall event, exit_class stall, exit 5 (${ELAPSED}s against a 20 s sleep)"
else no "the silence watch  [exit $RC, ${ELAPSED}s, $(grep -o '"event": "[a-z-]*"' "$F/rec-st1.jsonl" | tr '\n' ' ')]"; fi
env STUB_SLEEP_AFTER=5 STUB_PROGRESS=1 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st2 --lane S2 --class verifier --grant "$F/granted" \
  --silence-s 2 --poll-s 1 --record "$F/rec-st2.jsonl" --reason 'control: a progress file' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && ! grep -q '"event": "stall"' "$F/rec-st2.jsonl" && [ -s "$F/progress/run-test-st2-S2.progress" ] \
   && grep -q "^LLM_WIKI_LANE_PROGRESS=$F/progress/run-test-st2-S2.progress$" "$E"; then
  ok "a lane that appends to its progress file through a 5 s silence is not stalled at a 2 s threshold (control; the path reaches the lane as LLM_WIKI_LANE_PROGRESS)"
else no "the progress-file liveness  [exit $RC, progress file: $(wc -l < "$F/progress/run-test-st2-S2.progress" 2>&1) lines]"; fi
START=$(date +%s)
env STUB_SLEEP=20 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st3 --lane S3 --class verifier --grant "$F/granted" \
  --silence-s 30 --poll-s 1 --no-transcript-s 2 --record "$F/rec-st3.jsonl" --reason 'no transcript' >/dev/null 2>&1
RC=$?; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 5 ] && grep -q '"reason": "no transcript"' "$F/rec-st3.jsonl" && [ "$ELAPSED" -lt 15 ]; then
  ok "no transcript within --no-transcript-s is a stall of reason 'no transcript' (${ELAPSED}s)"
else no "the no-transcript stall  [exit $RC, ${ELAPSED}s]"; fi
env STUB_SLEEP_AFTER=4 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-st4 --lane S4 --class verifier --grant "$F/granted" \
  --silence-s 0 --poll-s 1 --no-transcript-s 1 --record "$F/rec-st4.jsonl" --reason '--silence-s 0' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && ! grep -q '"event": "stall"' "$F/rec-st4.jsonl" \
   && [ "$(recfield "$F/rec-st4.jsonl" lane-open silence_s)" = 0 ]; then
  ok "--silence-s 0 disables the watch: a 4 s silence at a 1 s no-transcript bound completes (control)"
else no "--silence-s 0  [exit $RC]"; fi
printf '{"event": "lane-closed", "lane": "X", "run": "run-test-bl", "duration_s": 10}\n' > "$F/rec-bl.jsonl"
BL=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" \
     --silence-s 5 --baseline-lane X --dry-run 2>&1)
BL2=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" \
      --silence-s 100 --baseline-lane X --dry-run 2>&1)
BL3=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" --dry-run 2>&1)
if printf '%s\n' "$BL" | grep -qF 'silence: 15.0 s (1.5 x baseline X (10.0 s))' \
   && printf '%s\n' "$BL2" | grep -qF 'silence: 100.0 s (--silence-s)' \
   && printf '%s\n' "$BL3" | grep -qF 'silence: 900 s (default)'; then
  ok "--baseline-lane raises the threshold to 1.5 x the predecessor's duration only when larger; the default is 900 s"
else no "the silence threshold  [$(printf '%s\n' "$BL" | grep '^silence') / $(printf '%s\n' "$BL2" | grep '^silence') / $(printf '%s\n' "$BL3" | grep '^silence')]"; fi
ERR=$(spawn --run run-test-bl --lane BL --class verifier --grant "$F/granted" --record "$F/rec-bl.jsonl" \
      --baseline-lane Y --dry-run 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'has no lane-closed'; then
  ok "premise: --baseline-lane naming a lane with no recorded close (exit 2)"
else no "an unknown baseline lane got through  [exit $RC: $ERR]"; fi

# watch -----------------------------------------------------------------------------------------
ERR=$($LANEV "$PY" "$LANE" watch --run run-test-b --lane NOPE --record "$F/rec-b.jsonl" --poll-s 1 --appear-s 0 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'unknown'; then ok "watch: an unknown lane is refused (exit 2)"
else no "watch on an unknown lane  [exit $RC: $ERR]"; fi
OUT=$($LANEV "$PY" "$LANE" watch --run run-test-b --lane L2 --record "$F/rec-b.jsonl" --poll-s 1 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'already closed' && printf '%s' "$OUT" | grep -q '^lane run-test-b/L2: '; then
  ok "watch: an already-closed lane is refused (exit 2) after its summary line"
else no "watch on a closed lane  [exit $RC: $OUT]"; fi
env STUB_SLEEP_AFTER=6 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-w1 --lane W1 --class verifier --grant "$F/granted" \
  --silence-s 0 --record "$F/rec-w1.jsonl" --reason 'watched to its close' >/dev/null 2>&1 &
SP=$!
sleep 2
WOUT=$($LANEV "$PY" "$LANE" watch --run run-test-w1 --lane W1 --record "$F/rec-w1.jsonl" --poll-s 1 \
       --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
wait "$SP"
if [ "$RC" = 0 ] && printf '%s\n' "$WOUT" | grep -q '^lane run-test-w1/W1: .* completed ' \
   && [ "$(events "$F/rec-w1.jsonl" lane-closed)" = 1 ]; then
  ok "watch: a running lane that closes on its own returns 0 with the summary line, and no second close is written"
else no "watch to a natural close  [exit $RC: $(printf '%s' "$WOUT" | head -2 | tr '\n' ' ')]"; fi
env STUB_SLEEP_AFTER=8 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-w2 --lane W2 --class verifier --grant "$F/granted" \
  --silence-s 0 --record "$F/rec-w2.jsonl" --reason 'still running' >/dev/null 2>&1 &
SP=$!
sleep 2
WOUT=$($LANEV "$PY" "$LANE" watch --run run-test-w2 --lane W2 --record "$F/rec-w2.jsonl" --poll-s 1 --max-wait-s 2 \
       --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
wait "$SP"
if [ "$RC" = 8 ] && printf '%s' "$WOUT" | grep -q 'still-running'; then
  ok "watch: --max-wait-s returns still-running (exit 8) so the head can re-issue a bounded blocking call"
else no "watch --max-wait-s  [exit $RC: $WOUT]"; fi
env STUB_SLEEP_AFTER=30 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-ws --lane WS --class verifier --grant "$F/granted" \
  --silence-s 0 --record "$F/rec-ws.jsonl" --reason 'stalled by watch' >/dev/null 2>&1 &
SP=$!
sleep 2; START=$(date +%s)
WOUT=$($LANEV "$PY" "$LANE" watch --run run-test-ws --lane WS --record "$F/rec-ws.jsonl" --poll-s 1 --silence-s 1 \
       --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
wait "$SP"; ELAPSED=$(( $(date +%s) - START ))
if [ "$RC" = 5 ] && grep -q '"by": "watch"' "$F/rec-ws.jsonl" && grep -q '"event": "stall"' "$F/rec-ws.jsonl" \
   && [ "$(events "$F/rec-ws.jsonl" lane-closed)" = 1 ] && [ "$ELAPSED" -lt 20 ]; then
  ok "watch --silence-s kills a silent lane (stall event by watch, exit 5) and the live wrapper writes the one close (${ELAPSED}s against a 30 s sleep)"
else no "watch stalling a lane  [exit $RC, ${ELAPSED}s: $(printf '%s' "$WOUT" | head -2 | tr '\n' ' ')]"; fi
# a lane whose wrapper is gone: closed from its transcript (C2 N6)
sh -c 'exit 0' & DEADPID=$!; wait "$DEADPID"
TS=$(date +%Y-%m-%dT%H:%M:%S%z)
printf '{"ts": "%s", "run": "run-test-wg", "lane": "WG", "event": "lane-open", "class": "verifier", "model": "sonnet", "effort": "high", "session_id": "fixture-gone", "deadline_s": 3600, "cwd": "%s", "projects_root": "%s"}\n' "$TS" "$LHOME" "$PROJ" > "$F/rec-wg.jsonl"
printf '{"ts": "%s", "run": "run-test-wg", "lane": "WG", "event": "lane-spawned", "session_id": "fixture-gone", "pid": %s, "wrapper_pid": %s}\n' "$TS" "$DEADPID" "$DEADPID" >> "$F/rec-wg.jsonl"
DASHED=$("$PY" -c 'import os, re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(sys.argv[1])))' "$LHOME")
mkdir -p "$PROJ/$DASHED"
sleep 1
"$PY" - "$PROJ/$DASHED/fixture-gone.jsonl" <<'GONE_TRANSCRIPT_TERMINATOR'
import json, sys
usage = {"input_tokens": 5, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 2000,
         "output_tokens": 30}
with open(sys.argv[1], "w") as h:
    h.write(json.dumps({"type": "assistant", "effort": "high", "message": {
        "id": "g1", "model": "claude-sonnet-5", "role": "assistant", "usage": usage,
        "content": [{"type": "text", "text": "orphan report text ORPHAN-9911"}]}}) + "\n")
GONE_TRANSCRIPT_TERMINATOR
WG=$($LANEV "$PY" "$LANE" watch --run run-test-wg --lane WG --record "$F/rec-wg.jsonl" --poll-s 1 2>&1); RC=$?
if [ "$RC" = 0 ] && grep -q '"exit_class": "watch-closed"' "$F/rec-wg.jsonl" \
   && grep -q '"cost_src": "transcript-estimate"' "$F/rec-wg.jsonl" && grep -q '"denials": "unknown"' "$F/rec-wg.jsonl" \
   && grep -q '"note": "closed by watch (wrapper gone)"' "$F/rec-wg.jsonl" \
   && [ "$(recfield "$F/rec-wg.jsonl" lane-closed duration_s)" != null ] \
   && grep -q 'ORPHAN-9911' "$STORE/spawn-records/run-test-wg-report-WG.md" \
   && printf '%s\n' "$WG" | grep -q '^lane run-test-wg/WG: .* watch-closed '; then
  ok "watch: a lane whose wrapper is gone is closed from its transcript (watch-closed, transcript-estimate, denials unknown), its report persisted, home and projects root taken from the record"
else no "watch closing an orphan  [exit $RC: $(printf '%s' "$WG" | head -2 | tr '\n' ' '); $(grep -o '"exit_class": "[a-z-]*"' "$F/rec-wg.jsonl")]"; fi
sleep 30 & LIVEPID=$!
printf '{"ts": "%s", "run": "run-test-wl", "lane": "WL", "event": "lane-open", "class": "verifier", "model": "sonnet", "effort": "high", "session_id": "fixture-live", "deadline_s": 3600, "cwd": "%s", "projects_root": "%s"}\n' "$TS" "$LHOME" "$PROJ" > "$F/rec-wl.jsonl"
printf '{"ts": "%s", "run": "run-test-wl", "lane": "WL", "event": "lane-spawned", "session_id": "fixture-live", "pid": %s, "wrapper_pid": %s}\n' "$TS" "$LIVEPID" "$LIVEPID" >> "$F/rec-wl.jsonl"
WL=$($LANEV "$PY" "$LANE" watch --run run-test-wl --lane WL --record "$F/rec-wl.jsonl" --poll-s 1 --max-wait-s 2 2>&1); RC=$?
if [ "$RC" = 8 ] && printf '%s' "$WL" | grep -q 'still-running' && [ "$(events "$F/rec-wl.jsonl" lane-closed)" = 0 ]; then
  ok "watch never closes a lane whose wrapper is alive: still-running (exit 8), no close written (control for the orphan leg)"
else no "watch on a live wrapper  [exit $RC: $WL]"; fi
WL=$($LANEV "$PY" "$LANE" watch --run run-test-wl --lane WL --record "$F/rec-wl.jsonl" --poll-s 1 --max-wait-s 3 \
     --silence-s 5 --no-transcript-s 1 2>&1); RC=$?
if [ "$RC" = 8 ] && [ "$(events "$F/rec-wl.jsonl" unwatched)" = 1 ] && [ "$(events "$F/rec-wl.jsonl" lane-closed)" = 0 ] \
   && kill -0 "$LIVEPID" 2>/dev/null; then
  ok "watch with a threshold but no transcript to read writes one unwatched event and kills nothing"
else no "the unwatched path  [exit $RC, unwatched $(events "$F/rec-wl.jsonl" unwatched): $WL]"; fi

# resume ----------------------------------------------------------------------------------------
printf 'Follow-up: say more.\n' > "$F/brief-follow.md"
RS=$($LANEV "$PY" "$LANE" resume --run run-test-b --lane L2 --brief "$F/brief-follow.md" --record "$F/rec-b.jsonl" \
     --home "$LHOME" 2>&1); RC=$?
SIDB=$(recfield "$F/rec-b.jsonl" lane-open session_id | tr -d '"')
if [ "$RC" = 0 ] && [ "$(argafter --resume)" = "$SIDB" ] && ! grep -qx -- '--session-id' "$A" \
   && [ "$(cat "$F/stub/stdin.txt")" = 'Follow-up: say more.' ] \
   && [ "$(argafter --model)" = sonnet ] && [ "$(argafter --effort)" = high ] \
   && [ "$(events "$F/rec-b.jsonl" lane-resumed)" = 1 ] && [ "$(events "$F/rec-b.jsonl" lane-closed)" = 2 ] \
   && [ "$(recfield "$F/rec-b.jsonl" lane-closed resumed)" = true ] \
   && [ -f "$STORE/spawn-records/run-test-b-in-L2/run-test-b-brief-L2-resume-1.md" ]; then
  ok "resume re-enters the session (--resume <id>, the follow-up on stdin, the open's model and effort) and records lane-resumed plus a new lane-closed"
else no "resume  [exit $RC: $(printf '%s' "$RS" | head -3 | tr '\n' ' ')]"; fi
printf '{"run": "run-test-old", "lane": "O", "event": "lane-open", "class": "verifier"}\n{"run": "run-test-old", "lane": "O", "event": "lane-spawned", "session_id": "old-sid"}\n{"run": "run-test-old", "lane": "O", "event": "lane-closed", "ts": "2026-01-01T00:00:00+0000", "session_id": "old-sid"}\n' > "$F/rec-old.jsonl"
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-old --lane O --brief "$F/brief-follow.md" --record "$F/rec-old.jsonl" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'resume window'; then
  ok "premise: resume refuses a lane whose last call is older than 55 min (exit 2)"
else no "resume of a lapsed lane  [exit $RC: $ERR]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-wl --lane WL --brief "$F/brief-follow.md" --record "$F/rec-wl.jsonl" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'no lane-closed yet'; then
  ok "premise: resume refuses a lane that has not closed (exit 2)"
else no "resume of an open lane  [exit $RC: $ERR]"; fi
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-b --lane NOPE --brief "$F/brief-follow.md" --record "$F/rec-b.jsonl" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'unknown'; then
  ok "premise: resume refuses an unknown lane (exit 2)"
else no "resume of an unknown lane  [exit $RC: $ERR]"; fi

# D29: after a `limit` close the cache window is waived; every other class keeps it, and a lane
# whose transcript cannot be found is re-spawned rather than resumed.
agedclose(){ # source record, destination, exit_class, [session id override] -> a close 2 h old
  "$PY" - "$1" "$2" "$3" "${4-}" <<'AGED_CLOSE_TERMINATOR'
import json, sys, time
src, dst, cls, sid = sys.argv[1:5]
ts = time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() - 2 * 3600))
records = []
for line in open(src):
    if not line.strip():
        continue
    record = json.loads(line)
    if sid and record.get("session_id"):
        record["session_id"] = sid
    if record.get("event") == "lane-closed":
        record["ts"] = ts
        record["exit_class"] = cls
    records.append(record)
with open(dst, "w") as handle:
    for record in records:
        handle.write(json.dumps(record) + "\n")
AGED_CLOSE_TERMINATOR
}
agedclose "$F/rec-b.jsonl" "$F/rec-limit.jsonl" limit
RS=$($LANEV "$PY" "$LANE" resume --run run-test-lim --lane L2 --brief "$F/brief-follow.md" \
     --record "$F/rec-limit.jsonl" --home "$LHOME" 2>&1); RC=$?
RAGE=$(recfield "$F/rec-limit.jsonl" lane-resumed age_s | cut -d. -f1)
if [ "$RC" = 0 ] && printf '%s' "$RS" | grep -q 'cache window is waived' \
   && [ "$(recfield "$F/rec-limit.jsonl" lane-resumed after_limit)" = true ] \
   && [ -n "$RAGE" ] && [ "$RAGE" -gt 3600 ]; then
  ok "D29: a lane closed on a limit 2 h ago resumes, prints the waiver, and records after_limit with age_s ($RAGE s)"
else no "D29 limit resume  [exit $RC, age $RAGE: $(printf '%s' "$RS" | head -3 | tr '\n' ' ')]"; fi
agedclose "$F/rec-b.jsonl" "$F/rec-comp.jsonl" completed
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-comp --lane L2 --brief "$F/brief-follow.md" \
      --record "$F/rec-comp.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'resume window'; then
  ok "D29: a completed close of the same age still refuses (the waiver is the limit class's alone — control for the leg above)"
else no "D29 non-limit close  [exit $RC: $ERR]"; fi
agedclose "$F/rec-b.jsonl" "$F/rec-nots.jsonl" limit fixture-no-transcript
ERR=$($LANEV "$PY" "$LANE" resume --run run-test-nots --lane L2 --brief "$F/brief-follow.md" \
      --record "$F/rec-nots.jsonl" --home "$LHOME" 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 're-spawn the lane'; then
  ok "D29: a limit close whose transcript is gone refuses with re-spawn (exit 2)"
else no "D29 missing transcript  [exit $RC: $ERR]"; fi
kill "$LIVEPID" 2>/dev/null; wait "$LIVEPID" 2>/dev/null

# the limit class -------------------------------------------------------------------------------
env STUB_REPORT="You've hit your session limit · resets 8:50am (Europe/London)" STUB_ISERROR=1 $LANEV "$PY" "$LANE" spawn \
  --home "$LHOME" --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" --run run-test-lm1 --lane LM1 \
  --class verifier --grant "$F/granted" --record "$F/rec-lm1.jsonl" --reason 'a limit stop' >/dev/null 2>&1
RC=$?
if [ "$RC" = 6 ] && grep -q '"exit_class": "limit"' "$F/rec-lm1.jsonl" \
   && grep -q '"limit_signal": "result text names a limit"' "$F/rec-lm1.jsonl"; then
  ok "a result naming a session limit closes as limit, exit 6"
else no "the limit class from the result text  [exit $RC]"; fi
env STUB_SYNTHETIC=1 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-lm2 --lane LM2 --class verifier --grant "$F/granted" \
  --record "$F/rec-lm2.jsonl" --reason 'a synthetic stop' >/dev/null 2>&1
RC=$?
if [ "$RC" = 6 ] && grep -q '"exit_class": "limit"' "$F/rec-lm2.jsonl" && grep -q '"limit_signal": "transcript: ' "$F/rec-lm2.jsonl"; then
  ok "a transcript whose last assistant record is a synthetic model with zero usage closes as limit, exit 6 (C2 N12)"
else no "the limit class from the transcript  [exit $RC: $(grep -o '"limit_signal": "[^"]*"' "$F/rec-lm2.jsonl")]"; fi
LONGLIMIT=$("$PY" -c 'print("the rate limit in the usage table is documented here; " * 12)')
env STUB_REPORT="$LONGLIMIT" $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
  --projects-root "$PROJ" --run run-test-lm3 --lane LM3 --class verifier --grant "$F/granted" \
  --record "$F/rec-lm3.jsonl" --reason 'control: a report that mentions limits' >/dev/null 2>&1
RC=$?
if [ "$RC" = 0 ] && grep -q '"exit_class": "completed"' "$F/rec-lm3.jsonl"; then
  ok "a successful 108-word report that merely mentions a limit and usage is not a limit stop (control; a budget stop stays budget, leg 19)"
else no "the limit text guard  [exit $RC]"; fi

# --detach --------------------------------------------------------------------------------------
DT=$(env STUB_SLEEP_AFTER=4 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
     --projects-root "$PROJ" --run run-test-dt1 --lane D1 --class verifier --grant "$F/granted" \
     --silence-s 0 --record "$F/rec-dt1.jsonl" --detach --no-wait 2>&1); RC=$?
DPID=$(printf '%s\n' "$DT" | sed -n 's/^detached pid \([0-9][0-9]*\) session .*$/\1/p')
if [ "$RC" = 0 ] && [ -n "$DPID" ] && [ "$(printf '%s\n' "$DT" | grep -c .)" = 1 ]; then
  ok "--detach --no-wait prints one line (detached pid N session S) and returns 0 at once"
else no "--detach --no-wait  [exit $RC: $DT]"; fi
WD=$($LANEV "$PY" "$LANE" watch --run run-test-dt1 --lane D1 --record "$F/rec-dt1.jsonl" --poll-s 1 \
     --home "$LHOME" --projects-root "$PROJ" 2>&1); RC=$?
if [ "$RC" = 0 ] && printf '%s\n' "$WD" | grep -q '^lane run-test-dt1/D1: .* completed ' \
   && [ "$(recfield "$F/rec-dt1.jsonl" lane-spawned wrapper_pid)" = "$DPID" ] \
   && [ "$(recfield "$F/rec-dt1.jsonl" lane-spawned detached)" = true ] \
   && [ "$(recfield "$F/rec-dt1.jsonl" lane-closed wrapper_pid)" = "$DPID" ]; then
  ok "watch on a detached lane waits for the worker's close; lane-spawned and lane-closed carry the worker's pid as wrapper_pid"
else no "watch on a detached lane  [exit $RC: $(printf '%s' "$WD" | head -2 | tr '\n' ' '); wrapper_pid $(recfield "$F/rec-dt1.jsonl" lane-spawned wrapper_pid) vs $DPID]"; fi
DT2=$(env STUB_EXIT=9 $LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" \
      --projects-root "$PROJ" --run run-test-dt2 --lane D2 --class verifier --grant "$F/granted" \
      --silence-s 0 --poll-s 1 --record "$F/rec-dt2.jsonl" --detach 2>&1); RC=$?
if [ "$RC" = 3 ] && printf '%s\n' "$DT2" | grep -q '^lane run-test-dt2/D2: .* error ' \
   && [ "$(recfield "$F/rec-dt2.jsonl" lane-spawned detached)" = true ]; then
  ok "--detach (waiting) stays as the watch over its worker and exits with the worker's code (3 for a stub exiting 9), printing the same summary line"
else no "--detach waiting on a failing worker  [exit $RC: $(printf '%s' "$DT2" | head -2 | tr '\n' ' ')]"; fi
DT3=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" \
      --run run-test-dt3 --lane D3 --class verifier --grant "$F/granted" --silence-s 0 --poll-s 1 \
      --record "$F/rec-dt3.jsonl" --detach 2>&1); RC=$?
if [ "$RC" = 0 ] && printf '%s\n' "$DT3" | grep -q '^lane run-test-dt3/D3: .* completed '; then
  ok "--detach with a clean worker exits 0 with the summary (control)"
else no "--detach on a clean worker  [exit $RC: $(printf '%s' "$DT3" | head -2 | tr '\n' ' ')]"; fi
DT4=$($LANEV "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" --brief "$F/brief.md" --projects-root "$PROJ" \
      --run run-test-dt4 --lane D4 --class no-such-class --grant "$F/granted" --poll-s 1 \
      --record "$F/rec-dt4.jsonl" --detach 2>&1); RC=$?
if [ "$RC" = 2 ] && printf '%s' "$DT4" | grep -q 'unknown class' && [ ! -f "$F/rec-dt4.jsonl" ]; then
  ok "a detached worker's premise failure surfaces in the foreground (exit 2, its reason quoted, no record)"
else no "a detached premise failure  [exit $RC: $(printf '%s' "$DT4" | tail -2 | tr '\n' ' ')]"; fi
premise "--no-wait without --detach" "goes with --detach" --home "$LHOME" --routing "$R" \
        --brief "$F/brief.md" --run run-test-p --lane P --class verifier --grant "$F/granted" --no-wait

# ------------------------------------------------------------------- the fence, offline ------
echo "== fence =="
fence(){ # name, expect(allow|deny|silent), command, [grants], [writes]
  NAME="$1"; WANT="$2"; CMD="$3"; G="${4-$F/granted}"; W="${5-}"
  OUT=$(printf '%s' "$($PY - "$CMD" <<'FENCE_INPUT_TERMINATOR'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
FENCE_INPUT_TERMINATOR
)" | env LLM_WIKI_LANE_GRANTS="$G" LLM_WIKI_LANE_WRITES="$W" "$PY" "$FENCE")
  RC=$?
  if [ "$RC" != 0 ]; then no "fence exited $RC on: $NAME"; return; fi
  GOT=silent
  printf '%s' "$OUT" | grep -q '"permissionDecision": "deny"'  && GOT=deny
  printf '%s' "$OUT" | grep -q '"permissionDecision": "allow"' && GOT=allow
  if [ "$GOT" = "$WANT" ]; then ok "fence $WANT: $NAME"
  else no "fence $NAME  [want $WANT, got $GOT: $OUT]"; fi
}
fence "a read inside the grants"            allow "cat $F/granted/inside.txt"
fence "a read outside the grants"           deny  "cat $F/elsewhere/outside.txt"
fence "a relative escape"                   deny  "cat ../../etc/hosts"
fence "a write with no write grant"         deny  "echo x > $F/writable/f.txt"
fence "a write into /tmp"                   allow "echo x > /tmp/lane-scratch.txt"
fence "an invocation of claude"             deny  "claude -p 'hello'"
fence "an invocation of claude by path"     deny  "/usr/local/bin/claude -p 'hello'"
fence "a quoted redirect character in a read" allow "grep -n '>' $F/granted/inside.txt"
fence "a system binary reading a granted file" allow "/usr/bin/grep -c x $F/granted/inside.txt"
fence "a write inside the whitelist"        allow "echo x > $F/writable/f.txt" "$F/granted" "$F/writable"
fence "a write outside the whitelist"       deny  "echo x > $F/elsewhere/f.txt" "$F/granted" "$F/writable"
fence "rm outside the whitelist"            deny  "rm -f $F/elsewhere/outside.txt" "$F/granted" "$F/writable"
fence "sed -i with no write grant"          deny  "sed -i '' s/a/b/ $F/granted/inside.txt"
fence "tee with no write grant"             deny  "cat $F/granted/inside.txt | tee /etc/x"

# --- D33: heredoc bodies are data, quoted payload is not a path -------------------------------
# `hd` turns \n in its argument into real newlines, so a multi-line command reaches the fence
# without this suite writing one: printf, never a heredoc, since a heredoc here would be the very
# thing under test. Every path is derived from $F, so no leg carries a literal home path.
hd(){ printf '%b' "$1"; }
fence "a heredoc body carrying >, tee, claude, ~, rm -rf and an outside path, written into the write grant" \
  allow "$(hd "cat > $F/writable/f.md <<'EOF'\na > b and tee -a x and claude -p hi\n$F/elsewhere/secret and ~/private\nrm -rf /\nthe word EOF inside the body\nEOF\necho done")" \
  "$F/granted" "$F/writable"
fence "the same redirect on the command line proper still denies" \
  deny "$(hd "cat > $F/elsewhere/f.md <<'EOF'\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "the same claude on the command line proper still denies" \
  deny "$(hd "claude -p hi <<'EOF'\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "the same tee on the command line proper still denies" \
  deny "$(hd "cat <<'EOF' | tee /etc/hosts\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "the same outside path on the command line proper still denies" \
  deny "$(hd "cat $F/elsewhere/secret <<'EOF'\nharmless\nEOF")" "$F/granted" "$F/writable"
fence "two heredocs opened on one line, consumed in marker order" \
  allow "$(hd "diff <(cat <<'A'\n> $F/elsewhere/x claude\nA\n) <(cat <<'B'\ntee /etc/passwd\nB\n)")" \
  "$F/granted" "$F/writable"
fence "<<- with a tab-indented terminator ends the body there" \
  allow "$(hd "cat > $F/writable/g.md <<-END\n\tclaude > $F/elsewhere/x\n\tEND\necho ok")" \
  "$F/granted" "$F/writable"
fence "an unterminated heredoc is body to the end of the text" \
  allow "$(hd "cat > $F/writable/h.md <<'ZZ'\nclaude -p x > $F/elsewhere/y\ntee /etc/hosts")" \
  "$F/granted" "$F/writable"
fence "a heredoc marker with no body at all still leaves its command line checked" \
  deny "cat $F/elsewhere/secret <<EOF" "$F/granted" "$F/writable"
fence "a > inside a body whose own command line redirects outside the grants still denies" \
  deny "$(hd "cat > $F/elsewhere/out.md <<'EOF'\na > b\nEOF")" "$F/granted" "$F/writable"
fence "a quoted single path outside the grants is a path token" \
  deny "cat \"$F/elsewhere/secret\"" "$F/granted" "$F/writable"
fence "a mutator with a quoted spaced target outside the write roots" \
  deny "cp /tmp/a \"$F/elsewhere/a b\"" "$F/granted" "$F/writable"
fence "a quoted multi-word literal naming a path in a read command is payload" \
  allow "grep \"see $F/elsewhere/x for\" /tmp/a" "$F/granted" "$F/writable"
fence "a python one-liner in quotes carrying claude still denies (check 1 keeps content)" \
  deny "python3 -c \"import os; os.system('claude -p hi')\"" "$F/granted" "$F/writable"
fence "chmod +x a file inside the write grant (a +-led mode is not a path)" \
  allow "chmod +x $F/writable/f.md" "$F/granted" "$F/writable"
fence "chmod +x a variable target stays denied, fail-closed" \
  deny "chmod +x \"\$f\"" "$F/granted" "$F/writable"
fence "a quoted pattern carrying ^ is payload" \
  allow "grep '/^x/' /tmp/a" "$F/granted" "$F/writable"
fence "a quoted glob outside the grants is still a path token, cut to its directory" \
  deny "cat \"$F/elsewhere/*.md\"" "$F/granted" "$F/writable"

# --- D33 as amended by critic C2: N1 (one spaced path, not two words) and N3 (no variable target)
fence "N1: a spaced quoted path outside the grants is ONE path and denies" \
  deny "cat \"$F/elsewhere/Application Support/x\"" "$F/granted" "$F/writable"
fence "N1: a spaced quoted path inside the temp roots is allowed" \
  allow "cat \"/tmp/a b\"" "$F/granted" "$F/writable"
fence "N1: a quoted glob inside the write grant is cut to its directory and allowed (control for the deny above)" \
  allow "cat \"$F/writable/*.md\"" "$F/granted" "$F/writable"
fence "N3: a mutator target carrying a variable is denied outright" \
  deny "cp /tmp/a \"\$HOME/.zshrc\"" "$F/granted" "$F/writable"
fence "N3: a redirection target carrying a variable is denied outright" \
  deny "echo x > \"\$HOME/.zshrc\"" "$F/granted" "$F/writable"
fence "N3: a tee target carrying a variable is denied outright" \
  deny "cat /tmp/a | tee \"\$HOME/x\"" "$F/granted" "$F/writable"
fence "N3: two literal paths inside the write roots still pass (control for the three denies above)" \
  allow "cp /tmp/a /tmp/b" "$F/granted" "$F/writable"
fence "N1 residue: a letters-only quoted pattern is still read as a path and false-denies" \
  deny "sed -n '/foo/p' /tmp/a" "$F/granted" "$F/writable"

# --- N9: the false-deny classes on quoted arguments, each with its negative control ------------
# Five denials measured live (register, 2026-09-05 and 2026-09-06), each of which stopped a whole
# command line for a call that wrote nothing: a quoted `>` scanned as a redirection, a sanctioned
# quoted target whose blanking unbalanced the rest of the line, and a slash-led quoted pattern read
# as a path. Every control below is the deny the fix must keep, run on the same suite.
fence "N9: a quoted status prose holding an angle-bracket placeholder and a backticked word is no redirect" \
  allow "python3 $F/granted/vault-writes.py register add --status \"wrote <topic>/<page> \`date -u\`\"" \
  "$F/granted" "$F/writable"
fence "N9 control: a real redirect whose quoted target carries a substitution still denies (N3)" \
  deny "echo x > \"\`echo /etc/x\`\"" "$F/granted" "$F/writable"
fence "N9: an awk program whose slash-led quoted regex carries an action block is a pattern" \
  allow "awk '/## Open/{print \$2}' $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N9 control: a slash-led quoted real path outside the grants is still a path (N1)" \
  deny "awk '{print}' \"/etc/passwd\"" "$F/granted" "$F/writable"
fence "N9: a compound whose quoted redirect target sits in the write grant, then a quoted placeholder" \
  allow "echo x > \"$F/writable/out.txt\" && echo \"compiled <topic> page\"" "$F/granted" "$F/writable"
fence "N9 control: the same compound with the quoted target outside the write grant still denies" \
  deny "echo x > \"$F/elsewhere/out.txt\" && echo \"compiled <topic> page\"" "$F/granted" "$F/writable"
fence "N9: a sed address range is a pattern, not a path" \
  allow "sed -n '/Open/,/Closed/p' $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N9 control: an address range does not blind check 4 on the same line" \
  deny "sed -n '/Open/,/Closed/p' \"/etc/passwd\"" "$F/granted" "$F/writable"
fence "N9c: a read path built from a quoted shell variable joined to a literal subdirectory" \
  allow "grep -rn \"needle\" \"\$V\"/wiki" "$F/granted" "$F/writable"
fence "N9c control: a quoted literal directory glued to a name outside the grants still denies" \
  deny "cat \"$F/elsewhere\"/secret" "$F/granted" "$F/writable"

# N9 attack pass: each premise failure with the verdict it must get -----------------------------
fence "N9 attack: empty quotes in a redirect target position deny, fail-closed" \
  deny "echo x > \"\"" "$F/granted" "$F/writable"
fence "N9 attack: an unterminated quote hiding a redirect outside the writes still denies" \
  deny "echo \"a > $F/elsewhere/x.txt" "$F/granted" "$F/writable"
fence "N9 attack: a double-quoted string inside a single-quoted awk program is payload" \
  allow "awk 'BEGIN{print \"a > b\"}' $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N9 attack: a pattern-shaped redirect target denies, fail-closed" \
  deny "echo x > \"/foo/,/bar/\"" "$F/granted" "$F/writable"
fence "N9 attack: a multi-segment path that looks pattern-ish is still a path" \
  deny "cat \"/etc/pam.d/sudo\"" "$F/granted" "$F/writable"
fence "N9 attack: a quoted path behind a glued flag is still a path token" \
  deny "grep -f\"/etc/patterns\" $F/granted/inside.txt" "$F/granted" "$F/writable"

# --- the mutator check is scoped to the mutator's own segment and its target arguments ---------
# The head hit the whole-command form live on 2026-09-05: `cd <vault> && … && mkdir -p /tmp/a`
# denied with "`mkdir` targets `cd`", every later token read as a target.
fence "a compound line whose only write is inside the write grant" \
  allow "cd $F/granted && echo x && mkdir -p /tmp/lane-compound && python3 -B run.py" "$F/granted" /tmp
fence "cp reads a granted source and writes a granted target (the source is a read, not a target)" \
  allow "cp $F/granted/inside.txt /tmp/lane-copy" "$F/granted" /tmp
fence "cp whose TARGET is outside the write roots still denies" \
  deny "cp /tmp/a $F/elsewhere/b" "$F/granted" /tmp
fence "a second segment's mutator is checked on its own target" \
  deny "mkdir -p /tmp/a && cp /tmp/a/x $F/elsewhere/z" "$F/granted" /tmp
fence "a mutator after a sanctioned redirect is still checked" \
  deny "echo x > /tmp/a; rm -rf $F/elsewhere" "$F/granted" /tmp
fence "a leading VAR=value assignment does not hide the mutator" \
  allow "VAR=1 rm -rf /tmp/lane-scratch" "$F/granted" /tmp
fence "a prefix word does not hide the mutator either" \
  deny "sudo rm -rf $F/elsewhere" "$F/granted" /tmp

# --- N10: the mutator scan reads TOKENS, and an operand that names no file is not a target ------
# Three denials measured live on 2026-09-06, each on a command line that ran nothing: quoted prose
# whose `;` started a segment and whose next word was `cp`; a heredoc body inside a QUOTED command
# substitution (a `<<` inside quotes opens no heredoc, so the body stayed text), whose `install`
# line was read as a command; and `chmod 644 <file in W>`, whose MODE was read as a relative path
# and denied as a target outside W. Every allow below is paired with the deny it must keep, and
# the controls grant READ on the outside directory so the deny can only come from the write rule.
fence "N10: a mutator word inside another command's quoted prose is prose, not a command" \
  allow "python3 $F/granted/vault-writes.py register add --status \"compiled the page; cp of the fixture into $F/elsewhere/notes.md\"" \
  "$F/granted" "$F/writable"
fence "N10 control: the same cp as a command still denies on its target" \
  deny "python3 $F/granted/vault-writes.py register add --status compiled; cp $F/granted/inside.txt $F/elsewhere/notes.md" \
  "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a heredoc body inside a quoted command substitution is payload, not commands" \
  allow "$(hd "python3 $F/granted/note.py --text \"\$(cat <<'EOF'\ninstall -m 644 lane-fence.py $F/elsewhere/delegate/\nthe head runs that line; this lane does not\nEOF\n)\"")" \
  "$F/granted" "$F/writable"
fence "N10 control: the same install line as a command still denies on its target" \
  deny "$(hd "python3 $F/granted/note.py --text ok\ninstall -m 644 $F/granted/inside.txt $F/elsewhere/delegate/x")" \
  "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: chmod writes its FILE — an octal mode is a mode, not a relative path" \
  allow "chmod 644 $F/writable/f.md" "$F/granted" "$F/writable"
fence "N10 control: the same mode with the file outside the writes still denies" \
  deny "chmod 644 $F/elsewhere/f.md" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a mode that is also a plausible file name — the SECOND operand is what chmod writes" \
  allow "chmod 755 $F/writable/755" "$F/granted" "$F/writable"
fence "N10 control: the same shape with the second operand outside the writes denies" \
  deny "chmod 755 $F/elsewhere/755" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a symbolic mode with commas is a mode" \
  allow "chmod u+x,g-w $F/writable/f.md" "$F/granted" "$F/writable"
fence "N10 control: a symbolic mode with commas over a file outside the writes denies" \
  deny "chmod u+x,g-w $F/elsewhere/f.md" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: chown -R takes its owner spec after the flag, and the spec is no path" \
  allow "chown -R alice:staff $F/writable/d" "$F/granted" "$F/writable"
fence "N10 control: the same owner spec with the target outside the writes denies" \
  deny "chown -R alice:staff $F/elsewhere/d" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a chgrp group spec is a group, not a relative path" \
  allow "chgrp staff $F/writable/f.md" "$F/granted" "$F/writable"
fence "N10 control: chgrp with the target outside the writes denies" \
  deny "chgrp staff $F/elsewhere/f.md" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: install -m consumes its mode, and the last operand is the file it creates" \
  allow "install -m 644 $F/granted/inside.txt $F/writable/b" "$F/granted" "$F/writable"
fence "N10 control: install -m with the created file outside the writes denies" \
  deny "install -m 644 $F/granted/inside.txt $F/elsewhere/b" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: install -d creates EVERY operand, all of them inside the writes" \
  allow "install -d $F/writable/a $F/writable/b $F/writable/c" "$F/granted" "$F/writable"
fence "N10 control: install -d denies when one operand is outside the writes" \
  deny "install -d $F/writable/a $F/elsewhere/b" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a quoted single-path target inside the writes stays a target and passes" \
  allow "cp $F/granted/inside.txt \"$F/writable/b\"" "$F/granted" "$F/writable"
fence "N10 control: the same quoted single-path target outside the writes still denies" \
  deny "cp $F/granted/inside.txt \"$F/elsewhere/b\"" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: a real write hides in a glued target-directory flag, and denies on that directory" \
  deny "cp -t\"$F/granted/sub\" $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N10 control: the same glued flag naming a directory inside the writes passes" \
  allow "cp -t\"$F/writable\" $F/granted/inside.txt" "$F/granted" "$F/writable"
fence "N10: a glued path behind a flag that takes no value is no write (the command reads the whole word as options and errors)" \
  allow "rm -rf\"$F/granted/sub\"" "$F/granted" "$F/writable"
fence "N10: dd writes its of= operand and reads its if= one" \
  allow "dd if=$F/granted/inside.txt of=$F/writable/copy.img bs=4k count=1" "$F/granted" "$F/writable"
fence "N10 control: dd with of= outside the writes denies" \
  deny "dd if=$F/granted/inside.txt of=$F/elsewhere/copy.img" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10: touch -r takes a reference FILE as its value, never as its target" \
  allow "touch -r $F/granted/inside.txt $F/writable/f" "$F/granted" "$F/writable"
fence "N10 control: touch with its target outside the writes denies" \
  deny "touch -r $F/granted/inside.txt $F/elsewhere/f" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10 attack: an empty quoted target writes nothing and keeps its verdict" \
  allow "cp $F/granted/inside.txt \"\"" "$F/granted" "$F/writable"
fence "N10 attack: an unterminated quote round a target outside the writes still denies" \
  deny "cp $F/granted/inside.txt \"$F/elsewhere/x" "$F/granted:$F/elsewhere" "$F/writable"
fence "N10 attack: nested quotes round prose naming a mutator and two paths read nothing" \
  allow "python3 $F/granted/x.py --status \"it's cp $F/elsewhere/a $F/elsewhere/b, not run\"" \
  "$F/granted" "$F/writable"
fence "N10 attack: a mutator's own diagnostics redirect is not one of its operands" \
  allow "rm -f $F/writable/x 2>/dev/null" "$F/granted" "$F/writable"

# --- D33 attack pass: planted smuggles, each with the verdict it must get ----------------------
fence "attack: a # <<EOF comment opens no heredoc, so the lines beneath it are commands" \
  deny "$(hd "# <<EOF\nrm -rf $F/elsewhere/important\nEOF")" "$F/granted" "$F/writable"
fence "attack: a << inside quotes opens no heredoc either" \
  deny "$(hd "echo \"a << EOF here\"\ncat $F/elsewhere/secret")" "$F/granted" "$F/writable"
fence "attack: a terminator with a trailing space does not end the body (the shell agrees: the line beneath never runs)" \
  allow "$(hd "cat > $F/writable/a.md <<'EOF'\nbody\nEOF \ncat $F/elsewhere/secret")" "$F/granted" "$F/writable"
fence "attack: a backslash-continued line hiding a redirect outside the grants" \
  deny "$(hd "cat /tmp/a \\\\\n  > $F/elsewhere/out.txt")" "$F/granted" "$F/writable"
fence "attack: a heredoc opened on a continued line, a mutator after the terminator" \
  deny "$(hd "cat > $F/writable/b.md \\\\\n<<'EOF'\nbody > $F/elsewhere/x\nEOF\nrm -f $F/elsewhere/important")" "$F/granted" "$F/writable"
fence "attack: a command substitution naming an outside path" \
  deny "cat \$(echo $F/elsewhere/secret)" "$F/granted" "$F/writable"
fence "attack: an interpreter payload (sh -c) keeps its content for the read checks" \
  deny "sh -c \"cat $F/elsewhere/secret\"" "$F/granted" "$F/writable"
fence "attack: a /-led quoted target carrying a variable is one path token and is checked" \
  deny "cat \"$F/elsewhere/\$f\"" "$F/granted" "$F/writable"
fence "attack: a \$-led quoted target is the named read-side false-allow (the fence cannot expand it)" \
  allow "cat \"\$HOME/Library/Application Support/x\"" "$F/granted" "$F/writable"
fence "attack: a here-STRING is not a heredoc and its word is still a path token" \
  deny "cat <<< $F/elsewhere/secret" "$F/granted" "$F/writable"
fence "attack: a bare terminator ends the body, so the tee beneath it is checked" \
  deny "$(hd "cat > $F/writable/c.md <<EOF\ntee /etc/hosts\nEOF\ncat /tmp/a | tee /etc/hosts")" "$F/granted" "$F/writable"
fence "attack: nested quotes round a spaced literal naming a path read nothing" \
  allow "grep \"it's $F/elsewhere/secret\" /tmp/a" "$F/granted" "$F/writable"
fence "attack: a mutator whose target is a variable stays denied, fail-closed" \
  deny "cp /tmp/a \"\$DEST/b\"" "$F/granted" "$F/writable"

# --- D34: the head role (--head) --------------------------------------------------------------
hfence(){ # name, expect(silent|deny|allow), command, [grants], [writes] — the same checker, --head
  HNAME="$1"; HWANT="$2"; HCMD="$3"; HG="${4-$F/granted}"; HW="${5-}"
  OUT=$(printf '%s' "$($PY - "$HCMD" <<'HEAD_FENCE_INPUT_TERMINATOR'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
HEAD_FENCE_INPUT_TERMINATOR
)" | env LLM_WIKI_LANE_GRANTS="$HG" LLM_WIKI_LANE_WRITES="$HW" "$PY" "$FENCE" --head)
  RC=$?
  if [ "$RC" != 0 ]; then no "head fence exited $RC on: $HNAME"; return; fi
  GOT=silent
  printf '%s' "$OUT" | grep -q '"permissionDecision": "deny"'  && GOT=deny
  printf '%s' "$OUT" | grep -q '"permissionDecision": "allow"' && GOT=allow
  if [ "$GOT" = "$HWANT" ]; then ok "head fence $HWANT: $HNAME"
  else no "head fence $HNAME  [want $HWANT, got $GOT: $OUT]"; fi
}
hfence "a cleared command is silent, never an explicit allow" \
  silent "cat $F/granted/inside.txt" "$F/granted" "$F/writable"
hfence "a head may invoke claude (check 1 is off)" \
  silent "claude -p 'spawn a lane'" "$F/granted" "$F/writable"
hfence "git is the head's X grant" silent "git status --short" "$F/granted" "$F/writable"
hfence "a read outside the grants is the same deny as a lane's" \
  deny "cat $F/elsewhere/secret" "$F/granted" "$F/writable"
hfence "a write outside the write grant is the same deny as a lane's" \
  deny "echo x > $F/elsewhere/f.txt" "$F/granted" "$F/writable"
hfence "N9: the head's own compound — a quoted target in the writes, then a quoted placeholder" \
  silent "echo x > \"$F/writable/o.txt\" && echo \"compiled <topic> page\"" "$F/granted" "$F/writable"
fence "the lane role still answers a cleared command with an explicit allow (control for the silence above)" \
  allow "cat $F/granted/inside.txt" "$F/granted" "$F/writable"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p hi"}}' \
      | env LLM_WIKI_LANE_GRANTS="$F/granted" LLM_WIKI_FENCE_ROLE=head "$PY" "$FENCE"); RC=$?
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then ok "LLM_WIKI_FENCE_ROLE=head selects the head role without the flag"
else no "the head role from the environment  [exit $RC: $OUT]"; fi

# fail-closed and the premise cases
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' \
      | env -u LLM_WIKI_LANE_GRANTS -u LLM_WIKI_LANE_WRITES "$PY" "$FENCE")
if printf '%s' "$OUT" | grep -q 'lane-fence: no grants in environment'; then
  ok "fence fails closed with no grants in the environment"
else no "fence did not fail closed  [$OUT]"; fi
OUT=$(printf 'not json at all' | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE")
printf '%s' "$OUT" | grep -q 'hook input unreadable' \
  && ok "fence denies unreadable hook input" || no "fence allowed unreadable input  [$OUT]"
OUT=$(printf '{"tool_name":"Bash","tool_input":{}}' | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE")
printf '%s' "$OUT" | grep -q 'no command in hook input' \
  && ok "fence denies a Bash event carrying no command" || no "fence allowed a command-less event  [$OUT]"
OUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}' \
      | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE"); RC=$?
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then ok "fence stays silent on a non-Bash tool"
else no "fence spoke on a non-Bash tool  [exit $RC: $OUT]"; fi
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"   "}}' \
      | env LLM_WIKI_LANE_GRANTS="$F/granted" "$PY" "$FENCE"); RC=$?
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then ok "fence stays silent on an empty command"
else no "fence spoke on an empty command  [exit $RC: $OUT]"; fi

# ----------------------------------------------------------- wrote nothing outside its own ---
echo "== containment =="
SCRATCH="$F/scratch"; mkdir -p "$SCRATCH"; printf 'a\n' > "$SCRATCH/probe"
manifest(){ find "$1" -type f -exec shasum {} \; | sort; }
M1=$(manifest "$SCRATCH"); printf 'b\n' > "$SCRATCH/probe"; M2=$(manifest "$SCRATCH")
if [ -n "$M1" ] && [ "$M1" != "$M2" ]; then
  ok "the manifest comparison notices a changed byte (control for the legs below)"
else no "the manifest comparison is insensitive — the containment legs would be vacuous"; fi

# Only the files these two scripts read or could plausibly damage are hashed: the rest of the
# skill directory may legitimately change under a concurrent editor, and hashing it would turn
# a sibling's edit into a false failure here.
WATCHED="$LANE $FENCE $0 $VAULT/CLAUDE.md $VAULT/wiki/developments/wiki-confidence-levels.md"
VAULT_BEFORE=$(shasum $WATCHED)
spawn --run run-test-z --lane Z1 --class verifier --grant "$F/granted" \
      --record "$F/rec-z.jsonl" --reason 'containment' >/dev/null 2>&1
"$PY" "$LANE" init --home "$LHOME" >/dev/null 2>&1
VAULT_AFTER=$(shasum $WATCHED)
if [ "$VAULT_BEFORE" = "$VAULT_AFTER" ] && [ -n "$VAULT_BEFORE" ]; then
  ok "a spawn and an init leave both scripts and the two vault files init reads byte-identical"
else no "the wrapper wrote into the vault"; fi

if [ -z "$(find "$HOME/.llm-wiki/spawn-records" -name 'run-test-*' -newer "$LANE" 2>/dev/null)" ]; then
  ok "no run-test artefact reached the real run store (LLM_WIKI_STORE redirected every write)"
else no "the suite wrote into the real run store"; fi

scan_writes(){ # count how many of the five write-pattern families hit in a file
  N=0
  for pat in 'open\([^)]*['"'"'"][wax]' '\bos\.(remove|unlink|rename|replace|mkdir|makedirs|rmdir)\b' \
             '\bshutil\.' '\b(subprocess|Popen)\b' '\bos\.symlink\b'; do
    grep -qE -- "$pat" "$1" && N=$((N + 1))
  done
  echo "$N"
}
PLANT="$F/planted-fence.py"
{ cat "$FENCE"; printf '\nopen("x", "w")\nos.remove("x")\nshutil.copy("x","y")\nsubprocess.run([])\nos.symlink("a","b")\n'; } > "$PLANT"
WRITES=$(scan_writes "$FENCE"); PWRITES=$(scan_writes "$PLANT"); LWRITES=$(scan_writes "$LANE")
if [ "$WRITES" = 0 ] && [ "$PWRITES" = 5 ] && [ "$LWRITES" -ge 3 ]; then
  ok "the fence is stdout-only: none of the five write-pattern families appears in its source (controls: all 5 caught in a planted copy, and the same scan finds $LWRITES families in lane.py, which does write)"
else no "fence write-pattern scan  [fence $WRITES, planted $PWRITES of 5, lane.py $LWRITES]"; fi

STRAY=$(grep -nE "open\([^)]*['\"][wax]" "$LANE" | grep -v 'write_atomic\|append_record' | wc -l | tr -d ' ')
if [ "$STRAY" = 2 ]; then
  ok "every write in lane.py runs through write_atomic or append_record (2 call sites, both inside those helpers)"
else no "lane.py has $STRAY write call sites outside its two helpers"; fi

HOME_AFTER=$(shasum "$LANE" "$FENCE" "$0")
mkdir -p "$F/fakehome/__pycache__"
if [ "$HOME_BEFORE" = "$HOME_AFTER" ] && [ ! -d "$HERE/__pycache__" ] \
   && [ -d "$F/fakehome/__pycache__" ]; then
  ok "the suite leaves its own home untouched (control: a planted __pycache__ the same test sees)"
else no "the suite wrote into the script home"; fi

# ------------------------------------------------------------------------- live --------------
if [ "$LIVE" = 1 ]; then
  echo "== live =="
  LSTORE="$F/live-store"; LREC="$LSTORE/spawn-records/run-test-live.jsonl"
  mkdir -p "$F/live/granted" "$F/live/whitelist" "$F/live/offlimits"
  printf 'LIVE-GRANTED-TOKEN-5150\n' > "$F/live/granted/inside.txt"
  printf 'LIVE-OFFLIMITS-TOKEN-6260\n' > "$F/live/offlimits/outside.txt"
  live(){ env LLM_WIKI_STORE="$LSTORE" "$PY" "$LANE" spawn --home "$LHOME" --routing "$R" \
          --run run-test-live --model sonnet --budget-usd 1 --max-turns 6 --deadline-s 420 \
          --record "$LREC" "$@"; }

  cat > "$F/live/brief-fence.md" <<LIVE_FENCE_BRIEF_TERMINATOR
Do exactly these four steps, in order, then stop. One line per step.
1. Read tool on $F/live/granted/inside.txt — quote the token.
2. Read tool on $F/live/offlimits/outside.txt — if refused, say REFUSED.
3. Bash: cat $VAULT/CLAUDE.md — if refused, say DENIED and quote the first four words of the reason.
4. Bash: cat $F/live/granted/inside.txt — say ALLOWED and the token, or DENIED and the reason.
Finish with the line: STEPS DONE.
LIVE_FENCE_BRIEF_TERMINATOR
  live --lane V1 --class verifier --brief "$F/live/brief-fence.md" --effort high \
       --grant "$F/live/granted" --reason 'live: the two fences' >/dev/null 2>&1
  REP="$LSTORE/spawn-records/run-test-live-report-V1.md"
  V1=$("$PY" - "$LREC" V1 <<'LIVE_CLOSE_TERMINATOR'
import json, sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed" and r.get("lane") == sys.argv[2]:
        print(json.dumps({"tool": r["denials"]["tool"], "fence": r["denials"]["fence"],
                          "allows": r["denials"]["fence_allows"],
                          "effort": r["effort_applied"], "tier": r["cache_write_tier"],
                          "exit": r["exit_class"],
                          "denied": [d.get("tool_name") for d in r["permission_denials"]]}))
LIVE_CLOSE_TERMINATOR
)
  printf '%s' "$V1" | grep -q '"denied": \["Read", "Bash"\]' \
    && ok "live: the harness refused the ungranted Read and the fence refused the Bash read" \
    || no "live: fences  [$V1]"
  grep -q 'LIVE-GRANTED-TOKEN-5150' "$REP" \
    && ok "live: the granted read and the granted cat both succeeded (control: the denials above)" \
    || no "live: a granted read failed  [$(cat "$REP" 2>&1 | head -4)]"
  grep -qi 'lane-fence' "$REP" \
    && ok "live: the Bash denial carried a lane-fence reason the lane could quote" \
    || no "live: no lane-fence reason reached the lane"
  printf '%s' "$V1" | grep -q '"effort": \["high"\]' \
    && ok "live: the transcript's effort equals the --effort flag" || no "live: effort  [$V1]"
  printf '%s' "$V1" | grep -q '"tier": \["1h"\]' \
    && ok "live: the cache write tier is reported (1h, the headless default)" || no "live: tier  [$V1]"

  cat > "$F/live/brief-write.md" <<LIVE_WRITE_BRIEF_TERMINATOR
Do exactly these two steps, then stop. One line per step.
1. Use the Write tool to create $F/live/whitelist/made.txt containing exactly: WROTE-INSIDE
2. Use the Write tool to create $F/live/offlimits/made.txt containing exactly: WROTE-OUTSIDE
Say for each: WROTE or REFUSED. Finish with the line: STEPS DONE.
LIVE_WRITE_BRIEF_TERMINATOR
  live --lane W1 --class builder --brief "$F/live/brief-write.md" --effort high \
       --grant "$F/live/granted" --write "$F/live/whitelist" \
       --reason 'live: the write whitelist' >/dev/null 2>&1
  if [ -f "$F/live/whitelist/made.txt" ]; then
    ok "live: a write lane wrote inside its whitelist"
  else no "live: the write lane could not write inside its whitelist"; fi
  if [ ! -f "$F/live/offlimits/made.txt" ]; then
    ok "live: the same lane was refused outside its whitelist (control: the write above)"
  else no "live: a write landed outside the whitelist"; fi

  # The injection control pair: one spawn with the core appended, one without.
  cat > "$F/live/core.md" <<'LIVE_CORE_TERMINATOR'
# Lane core (measurement fixture)

LANE-CORE-MARKER: KESTREL-4417

Conduct, controls and shell discipline would follow here. This fixture stands in for the
shipped core so the leg does not depend on the shipped text.
LIVE_CORE_TERMINATOR
  printf 'Reply with exactly two words: ok, then the value of the LANE-CORE-MARKER line in your instructions, or NONE if there is no such line.\n' \
    > "$F/live/brief-core.md"
  live --lane A --class verifier --brief "$F/live/brief-core.md" --effort high \
       --grant "$F/live/granted" --max-turns 3 --reason 'live: no core' --no-core >/dev/null 2>&1
  live --lane C --class verifier --brief "$F/live/brief-core.md" --effort high \
       --grant "$F/live/granted" --max-turns 3 --reason 'live: core appended' \
       --append-core "$F/live/core.md" >/dev/null 2>&1
  MEAS=$("$PY" - "$LREC" "$LSTORE/spawn-records" <<'LIVE_MEASURE_TERMINATOR'
import json, os, sys
first = {}
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed" and r.get("lane") in ("A", "C"):
        first[r["lane"]] = r["usage"].get("first_call_context")
marks = {}
for lane in ("A", "C"):
    path = os.path.join(sys.argv[2], "run-test-live-report-%s.md" % lane)
    marks[lane] = "KESTREL-4417" in open(path).read() if os.path.exists(path) else None
print(json.dumps({"first": first, "marks": marks}))
LIVE_MEASURE_TERMINATOR
)
  echo "  measurement: $MEAS"
  printf '%s' "$MEAS" | grep -q '"C": true' \
    && ok "live: the core reaches the lane as an appended system prompt (marker quoted back)" \
    || no "live: the appended core did not reach the lane  [$MEAS]"
  printf '%s' "$MEAS" | grep -q '"A": false' \
    && ok "live: a lane spawned --no-core sees none (negative control for the leg above)" \
    || no "live: a core-less lane saw the marker  [$MEAS]"

  # The compile class carries its slice the same way: the lane quotes the slice's own heading.
  printf 'Your instructions contain lines beginning "## Lane slice: ". Reply with those lines and nothing else. If there are none, reply NONE.\n' \
    > "$F/live/brief-slice.md"
  live --lane S --class wiki-compile --brief "$F/live/brief-slice.md" --effort high \
       --grant "$F/live/granted" --max-turns 4 --reason 'live: the compile slice' >/dev/null 2>&1
  SREP="$LSTORE/spawn-records/run-test-live-report-S.md"
  if grep -q 'Lane slice: compile-core' "$SREP" && grep -q 'Lane slice: lane-core' "$SREP"; then
    ok "live: a wiki-compile lane's first call carries the compile-core heading beside the core's"
  else no "live: the compile slice did not reach the lane  [$(head -3 "$SREP" 2>&1)]"; fi

  TRUST=$("$PY" - "$LHOME" <<'LIVE_TRUST_TERMINATOR'
import json, os, sys
path = os.path.expanduser("~/.claude.json")
data = json.load(open(path)) if os.path.exists(path) else {}
entry = (data.get("projects") or {}).get(os.path.realpath(sys.argv[1]))
print("absent" if not isinstance(entry, dict) or "hasTrustDialogAccepted" not in entry
      else str(entry["hasTrustDialogAccepted"]))
LIVE_TRUST_TERMINATOR
)
  if [ "$TRUST" = absent ] && grep -q 'LIVE-GRANTED-TOKEN-5150' "$REP"; then
    ok "live: probe (a) — a lane home with no trust entry ($TRUST) still reads its home and grants"
  else no "live: probe (a) is inconclusive  [trust $TRUST]"; fi

  SPEND=$("$PY" - "$LREC" <<'LIVE_SPEND_TERMINATOR'
import json, sys
total = 0.0
n = 0
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed":
        total += float(r.get("total_cost_usd") or 0)
        n += 1
print("%d spawns, $%.4f list" % (n, total))
LIVE_SPEND_TERMINATOR
)
  echo "  live spend: $SPEND"
fi

# ------------------------------------------------------------- live hands-off probes ---------
# Two questions only a real harness can answer, each a haiku lane capped at $0.10: whether the
# per-spawn settings allow list beats the harness's sensitive-path guard under a `.claude/`
# directory (design D18: recorded, either answer is a finding), and whether --grant-vault-root
# lets a lane `cat` a vault-root file through the fence (with a no-flag control).
if [ "$LIVEHO" = 1 ]; then
  echo "== live hands-off (haiku, capped at \$0.10 per lane) =="
  HSTORE="$F/ho-store"; HREC="$HSTORE/spawn-records/run-test-ho.jsonl"
  mkdir -p "$F/ho/.claude/skills/thing" "$F/ho/plain"
  printf '# thing\n' > "$F/ho/.claude/skills/thing/SKILL.md"
  printf 'PLAIN-TOKEN-8181\n' > "$F/ho/plain/file.txt"
  holive(){ env -u CLAUDE_CONFIG_DIR LLM_WIKI_STORE="$HSTORE" CLAUDE_PROJECT_DIR="$FXV" "$PY" "$LANE" spawn \
            --home "$LHOME" --routing "$R" --run run-test-ho --model haiku --effort high --budget-usd 0.1 \
            --max-turns 4 --deadline-s 300 --record "$HREC" "$@"; }
  cat > "$F/ho/brief-edit.md" <<HO_EDIT_BRIEF_TERMINATOR
Use the Edit tool (never Bash) on the file $F/ho/.claude/skills/thing/SKILL.md: old_string is the line "# thing", new_string is "# thing" followed by a newline and the line PROBE-EDIT-OK. Then reply with exactly one line: EDITED, or DENIED followed by the tool's refusal text verbatim. Do nothing else.
HO_EDIT_BRIEF_TERMINATOR
  holive --lane HE --class builder --brief "$F/ho/brief-edit.md" --grant "$F/ho" \
         --write "$F/ho/.claude/skills/thing/SKILL.md" --reason 'live: the allow list against the sensitive-path guard' >/dev/null 2>&1
  HERC=$?
  HEREP="$HSTORE/spawn-records/run-test-ho-report-HE.md"
  if grep -q 'PROBE-EDIT-OK' "$F/ho/.claude/skills/thing/SKILL.md"; then
    ANSWER="the allow list BEATS the guard: the Edit landed"
  else
    ANSWER="the guard WINS: no edit landed (lane said: $(head -c 300 "$HEREP" 2>&1 | tr '\n' ' '))"
  fi
  echo "  probe (settings allow list under .claude/): $ANSWER"
  if [ "$HERC" = 0 ] || [ "$HERC" = 3 ]; then
    ok "live: the settings allow-list probe ran to a close (answer above; exit $HERC)"
  else no "live: the allow-list probe did not close cleanly  [exit $HERC]"; fi

  printf 'Run exactly one Bash command: cat %s/CUSTOMISATION.md — then reply with exactly one line: ALLOWED followed by the line of that file containing "throttle", or DENIED followed by the refusal text verbatim. Do nothing else.\n' "$FR/vault" > "$F/ho/brief-root.md"
  holive --lane HR --class verifier --brief "$F/ho/brief-root.md" --grant "$F/ho/plain" --grant-vault-root \
         --reason 'live: --grant-vault-root' >/dev/null 2>&1
  holive --lane HR0 --class verifier --brief "$F/ho/brief-root.md" --grant "$F/ho/plain" \
         --reason 'live: control, no vault root' >/dev/null 2>&1
  HRREP="$HSTORE/spawn-records/run-test-ho-report-HR.md"; HR0REP="$HSTORE/spawn-records/run-test-ho-report-HR0.md"
  if grep -q 'throttle' "$HRREP" && ! grep -q 'DENIED' "$HRREP"; then
    ok "live: --grant-vault-root lets a lane cat a vault-root file through the fence"
  else no "live: --grant-vault-root  [$(head -c 300 "$HRREP" 2>&1 | tr '\n' ' ')]"; fi
  if grep -q 'DENIED' "$HR0REP" && grep -q 'outside the granted directories' "$HR0REP"; then
    ok "live: without the flag the same cat is fenced, the reason quoted back (control)"
  else no "live: the vault-root control  [$(head -c 300 "$HR0REP" 2>&1 | tr '\n' ' ')]"; fi
  HOSPEND=$("$PY" - "$HREC" <<'HO_SPEND_TERMINATOR'
import json, sys
total, n, classes = 0.0, 0, []
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("event") == "lane-closed":
        total += float(r.get("total_cost_usd") or 0)
        n += 1
        classes.append("%s:%s" % (r.get("lane"), r.get("exit_class")))
print("%d lanes (%s), $%.4f list" % (n, " ".join(classes), total))
HO_SPEND_TERMINATOR
)
  echo "  live hands-off spend: $HOSPEND"
fi

TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then echo "PASS $PASS/$TOTAL"; else echo "FAIL $FAIL/$TOTAL"; exit 1; fi
