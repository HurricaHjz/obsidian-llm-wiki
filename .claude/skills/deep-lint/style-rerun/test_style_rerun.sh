#!/bin/sh
# test_style_rerun.sh — the style re-run kit's suite: run.sh (argument handling, the plan, the premise
# failures, a full run through a stub `claude` that plants transcripts), extract.py (the main reply
# chosen by the record rule, never by size; the status-line report; the premise failures; the
# transcript-directory derivation), render-rubric.py (the live Test embedded; the premise failures),
# and the kit's guarantees: no word counting in any script, no owner path in any shipped file, and
# the read-only scripts wrote nothing outside the run directory (a checksum manifest before and after).
#
# Run:  sh test_style_rerun.sh   (last line: PASS n/n or FAIL k/n)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PY="${PYTHON:-python3}"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   — $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL   — $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }
for f in run.sh extract.py render-rubric.py rubric.md judge-brief.md README.md questions.txt; do
	[ -f "$HERE/$f" ] || { echo "PROBE FAILED: no $f beside this suite"; echo "FAIL 1/1"; exit 2; }
done

export PYTHONDONTWRITEBYTECODE=1   # the suite imports the kit modules; never leave bytecode in the shipped folder
W=$(mktemp -d)
cleanup() { chmod -R u+w "$W" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT
VAULT="$W/vault"; mkdir -p "$VAULT"
printf '`CUSTOMISATION-LOADED-v1` — load marker.\n\n## Settings\n- **style**: balanced — the default style\n\n## Output styles\n\n### balanced\nThe natural answer. Test: every low-level passage earns its place.\n' >"$VAULT/CUSTOMISATION.md"
printf '## Output styles\n\n### shortest\nThe shortest style, described here.\nTest: each asked part in at most one or two sentences; a why in at most one clause;\nno term left unexplained.\n\n### brief\nShort. Test: visibly shorter than balanced would be.\n\n## Roles\n\n### tutor\n- teach\n' >"$VAULT/CUSTOMISATION-definitions.md"
printf 'tutor: What is the first thing?\n\n# a comment line\nengineer: Is the second thing sound, and can it be reused?\ngeneralist: Why is the third thing set as it is?\n' >"$W/questions.txt"

# ---------------------------------------------------------------- 1 · syntax and compile
bash -n "$HERE/run.sh"
eq "K01a run.sh parses (bash -n)" "$?" "0"
"$PY" - "$HERE/extract.py" "$HERE/render-rubric.py" <<'COMPILE_END'
import sys
for f in sys.argv[1:]:   # an in-memory syntax check: py_compile would write bytecode beside the shipped sources
    compile(open(f, encoding="utf-8").read(), f, "exec")
COMPILE_END
eq "K01b extract.py and render-rubric.py compile" "$?" "0"

# ---------------------------------------------------------------- 2 · the dry run and the plan
DRY=$(bash "$HERE/run.sh" --dry-run --questions "$W/questions.txt" --vault "$VAULT" --out "$W/never" --style shortest 2>&1)
RC=$?
eq "K02a a dry run exits 0" "$RC" "0"
eq "K02b it plans one session per usable line (blank and # lines skipped)" "$(printf '%s\n' "$DRY" | grep -c '^plan ')" "3"
eq "K02c the prompt is the hand-off opener: role, style, then the question" \
	"$(printf '%s\n' "$DRY" | grep -c '^plan 1: tag=tutor-shortest prompt="tutor, shortest. What is the first thing?"$')" "1"
eq "K02d the header names the count, the style, the model and the vault" \
	"$(printf '%s\n' "$DRY" | grep -c "^dry run: 3 session(s) on the shortest style, model claude-fable-5-1, from $VAULT$")" "1"
eq "K02e and writes nothing: the out directory is not created" "$(if [ -e "$W/never" ]; then echo yes; else echo no; fi)" "no"
printf 'tutor: one\ntutor: two\n' >"$W/q-dup.txt"
DUP=$(bash "$HERE/run.sh" --dry-run --questions "$W/q-dup.txt" --vault "$VAULT" --style brief 2>&1)
eq "K02f a second question for the same role gets its own tag (role-style-n), and --style flows into the tag" \
	"$(printf '%s\n' "$DUP" | grep -c '^plan 1: tag=tutor-brief ')/$(printf '%s\n' "$DUP" | grep -c '^plan 2: tag=tutor-brief-2 ')" "1/1"

# ---------------------------------------------------------------- 3 · premise failures
probe() { # probe <leg> <expected substring> run.sh args...
	NAME="$1"; WANT="$2"; shift 2
	GOT=$(bash "$HERE/run.sh" "$@" 2>&1); RC=$?
	eq "$NAME (exit 2, PROBE FAILED naming it)" "$RC/$(printf '%s\n' "$GOT" | grep -c "^PROBE FAILED: .*$WANT")" "2/1"
}
probe "K03a a missing questions file" "no questions file" --dry-run --questions "$W/none.txt" --vault "$VAULT"
printf '\n# only a comment\n' >"$W/q-empty.txt"
probe "K03b a questions file with no usable line" "no usable" --dry-run --questions "$W/q-empty.txt" --vault "$VAULT"
printf 'tutor: fine\njust words without a role prefix\n' >"$W/q-bad.txt"
probe "K03c a malformed line is named by number" "line 2 of" --dry-run --questions "$W/q-bad.txt" --vault "$VAULT"
printf 'tutor:   \n' >"$W/q-noq.txt"
probe "K03d a line with a role and no question" "has no question" --dry-run --questions "$W/q-noq.txt" --vault "$VAULT"
probe "K03e a directory that is not a vault root" "not a vault root" --dry-run --questions "$W/questions.txt" --vault "$W"
probe "K03f a style with no definition (the rubric cannot render, so no session is paid for)" "could not render the turbo style" --dry-run --questions "$W/questions.txt" --vault "$VAULT" --style turbo
probe "K03g an unknown argument" "unknown argument" --dry-run --bogus
# a PATH holding only the tools run.sh itself needs (symlinked), so `claude` is genuinely absent
TOOLBIN="$W/toolbin"; mkdir -p "$TOOLBIN"
for t in bash dirname sed python3 date mkdir cp basename rm; do ln -s "$(command -v "$t")" "$TOOLBIN/$t"; done
GOT=$(env PATH="$TOOLBIN" "$TOOLBIN/bash" "$HERE/run.sh" --questions "$W/questions.txt" --vault "$VAULT" --out "$W/never2" 2>&1); RC=$?
eq "K03h a real run without claude on PATH is PROBE FAILED, exit 2, and creates no run directory" \
	"$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: claude is not on PATH$')/$(if [ -e "$W/never2" ]; then echo yes; else echo no; fi)" "2/1/no"

# ---------------------------------------------------------------- 4 · a full run through a stub claude
# The stub takes the CLI's arguments, prints a JSON result, and plants this session's transcript in
# $STUB_TRANSCRIPTS with one of three shapes: (1) a progress line, a tool call, then the main reply
# opening with the status line; (2) the main reply, then the Stop hook's feedback record and a
# correction LONGER than the main reply (so a size rule would pick the correction and the record
# rule must not); (3) a main reply without a status line.
BIN="$W/bin"; mkdir -p "$BIN"; STUB_TRANSCRIPTS="$W/transcripts"; mkdir -p "$STUB_TRANSCRIPTS"; STUB_COUNT="$W/stub.count"; STUB_STDIN="$W/stub.stdin"
cat >"$BIN/claude" <<'STUB_END'
#!/bin/sh
sid=""; prompt=""
while [ $# -gt 0 ]; do
	case "$1" in --session-id) sid="$2"; shift 2;; -p) prompt="$2"; shift 2;; *) shift;; esac
done
n=$(cat "$STUB_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$STUB_COUNT"
# what reached this call's stdin: run.sh must feed /dev/null, since the real claude -p reads a non-terminal
# stdin as part of its prompt (the first live run, 2026-09-05, sent every session the loop's remaining rows)
stdin_bytes=$(cat | wc -c | tr -d ' '); echo "$sid $stdin_bytes" >>"$STUB_STDIN"
python3 - "$STUB_TRANSCRIPTS/$sid.jsonl" "$n" "$prompt" "$PWD" <<'PY'
import json, sys
path, n, prompt, cwd = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
def user(text, meta=False):
    r = {"type": "user", "message": {"role": "user", "content": text}, "cwd": cwd}
    if meta:
        r["isMeta"] = True
    return r
def bot(text=None, tool=None, api=False):
    content = [{"type": "text", "text": text}] if text is not None else [{"type": "tool_use", "name": tool}]
    r = {"type": "assistant", "message": {"role": "assistant", "content": content}}
    if api:
        r["isApiErrorMessage"] = True
    return r
recs = [user(prompt)]
if n == 1:
    recs += [bot("I'll read the page first."), bot(tool="Read"),
             {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "x"}]}},
             bot("testbot · tutor · shortest · single\n\nThe first thing is the marker. It sits on line one.")]
elif n == 2:
    recs += [bot("`testbot · engineer · shortest · single`\n\nSound, and reusable for every future credential."),
             user("Stop hook feedback:\nrole/style: this reply did not open with the status line.", meta=True),
             bot("testbot · engineer · shortest · single\n\nCorrection: here is the whole reply again, restated at length so that it is by far the longest assistant text in this session, which a size rule would pick and the record rule must leave out."),
             bot("API Error: the response stopped arriving.", api=True)]
else:
    recs += [bot("No status line here.\n\nBecause the third thing was set by judgement.")]
with open(path, "w", encoding="utf-8") as fh:
    for r in recs:
        fh.write(json.dumps(r) + "\n")
PY
printf '{"type":"result","session_id":"%s","result":"ok"}\n' "$sid"
STUB_END
chmod +x "$BIN/claude"
OUT="$W/out"; REC="$W/record.jsonl"
STAMP_BEFORE=$(cat "$HOME/.llm-wiki/style-rerun/last-run.txt" 2>/dev/null | wc -l | tr -d ' ')
mkdir -p "$W/home"   # HOME redirected: run.sh writes its run stamp under $HOME/.llm-wiki/style-rerun/, never the real one
RUNOUT=$(env HOME="$W/home" PATH="$BIN:$PATH" STUB_TRANSCRIPTS="$STUB_TRANSCRIPTS" STUB_COUNT="$STUB_COUNT" STUB_STDIN="$STUB_STDIN" \
	bash "$HERE/run.sh" --questions "$W/questions.txt" --vault "$VAULT" --out "$OUT" --style shortest --record "$REC" --run-id run-test 2>&1)
RC=$?
eq "K04a a full run exits 0 and reports the count, the style and the out directory" \
	"$RC/$(printf '%s\n' "$RUNOUT" | grep -c "^style-rerun: 3 session(s) on the shortest style; out=$OUT; manifest=$OUT/manifest.txt; non-zero exits=0$")" "0/1"
eq "K04b the manifest has one tag-and-sid row per question, in order" \
	"$(awk '{print $1}' "$OUT/manifest.txt" | tr '\n' ' ')/$(awk 'NF==2' "$OUT/manifest.txt" | wc -l | tr -d ' ')" "tutor-shortest engineer-shortest generalist-shortest /3"
eq "K04c the stub was called with each session's id (the transcripts carry the manifest's sids)" \
	"$(awk '{print $2}' "$OUT/manifest.txt" | while read -r s; do [ -f "$STUB_TRANSCRIPTS/$s.jsonl" ] && echo y; done | wc -l | tr -d ' ')" "3"
eq "K16b the run stamp went to the fixture HOME, and the real stamp file is unchanged (control: the fixture's has one line)" \
	"$(cat "$HOME/.llm-wiki/style-rerun/last-run.txt" 2>/dev/null | wc -l | tr -d ' ')/$(cat "$W/home/.llm-wiki/style-rerun/last-run.txt" 2>/dev/null | wc -l | tr -d ' ')" "$STAMP_BEFORE/1"
eq "K16a every session's stdin was empty (run.sh feeds /dev/null; a leaked plan file would show as bytes here; the real claude re-reads a leaked file from byte 0, the stub drains it, and either way the property that matters is zero bytes)" \
	"$(wc -l <"$STUB_STDIN" | tr -d ' ')/$(awk '$2 != 0' "$STUB_STDIN" | wc -l | tr -d ' ')" "3/0"
eq "K04d the sessions ran from the vault root (the stub recorded its cwd)" \
	"$(grep -l "\"cwd\": \"$VAULT\"" "$STUB_TRANSCRIPTS"/*.jsonl | wc -l | tr -d ' ')" "3"
eq "K04e progress.log has a start and a done line per session and ALL DONE" \
	"$(grep -c '^\[..:..:..\] start ' "$OUT/progress.log")/$(grep -c '^\[..:..:..\] done .* rc=0$' "$OUT/progress.log")/$(grep -c '^ALL DONE ' "$OUT/progress.log")" "3/3/1"
eq "K04f each session's JSON result and err file exist" "$(ls "$OUT"/*-shortest.json | wc -l | tr -d ' ')/$(ls "$OUT"/*-shortest.err | wc -l | tr -d ' ')" "3/3"
eq "K04g the questions were copied and the rubric rendered into the run directory with the live Test" \
	"$(cmp -s "$W/questions.txt" "$OUT/questions.txt" && echo same)/$(grep -c '^Test: each asked part in at most one or two sentences; a why in at most one clause; no term left unexplained\.$' "$OUT/rubric.md")" "same/1"
eq "K04h the record holds a probe-open and a probe-closed line per session, with the run id, the style and the exit" \
	"$(grep -c '"event":"probe-open"' "$REC")/$(grep -c '"event":"probe-closed"' "$REC")/$(grep -c '"run":"run-test"' "$REC")/$(grep -c '"style":"shortest"' "$REC")/$(grep -c '"exit":0}' "$REC")" "3/3/6/3/3"
eq "K04i the record's session ids are the manifest's" \
	"$(awk '{print $2}' "$OUT/manifest.txt" | while read -r s; do grep -c "\"session\":\"$s\"" "$REC"; done | tr '\n' '/')" "2/2/2/"
eq "K04j the plan scratch file is gone" "$(ls -a "$OUT" | grep -c '^\.plan')" "0"

# ---------------------------------------------------------------- 5 · extract.py on the planted transcripts
SNAP_T=$(cd "$STUB_TRANSCRIPTS" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256)
SNAP_V=$(cd "$VAULT" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256)
EXT=$("$PY" "$HERE/extract.py" --out "$OUT" --transcripts "$STUB_TRANSCRIPTS" 2>&1)
RC=$?
eq "K05a extract exits 0 and prints one line per manifest row" "$RC/$(printf '%s\n' "$EXT" | grep -c '^[a-z-]* *sid=')" "0/3"
eq "K05b session 1: the main reply is the status-line reply, not the progress line; opens_status=yes" \
	"$(printf '%s\n' "$EXT" | grep -c "^tutor-shortest .*opens_status=yes texts=2 corrections=0 opening='testbot · tutor · shortest · single'$")/$(head -1 "$OUT/tutor-shortest.full.txt")" "1/testbot · tutor · shortest · single"
eq "K05c session 2: the longer post-feedback correction is left out by the record rule; the main reply is the shorter one; the backticked line still opens" \
	"$(printf '%s\n' "$EXT" | grep -c "^engineer-shortest .*opens_status=yes texts=2 corrections=1 ")/$(grep -c '^Sound, and reusable' "$OUT/engineer-shortest.full.txt")/$(grep -c 'Correction:' "$OUT/engineer-shortest.full.txt")" "1/1/0"
eq "K05d session 3: a reply without the line reports opens_status=no" \
	"$(printf '%s\n' "$EXT" | grep -c "^generalist-shortest .*opens_status=no texts=1 corrections=0 opening='No status line here\.'$")" "1"
eq "K05e the harness-written API record was never a candidate (session 2 saw two model texts)" "$(printf '%s\n' "$EXT" | grep -c 'texts=2 corrections=1')" "1"
eq "K05f extract read the transcripts and the vault without changing a byte (checksums before and after)" \
	"$(if [ "$(cd "$STUB_TRANSCRIPTS" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256)" = "$SNAP_T" ] && [ "$(cd "$VAULT" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256)" = "$SNAP_V" ]; then echo same; else echo changed; fi)/$(printf '%s\n' "$SNAP_T" | grep -c .)" "same/3"
GOT=$("$PY" "$HERE/extract.py" --out "$W/nomanifest" --transcripts "$STUB_TRANSCRIPTS" 2>&1); RC=$?
eq "K05g a missing manifest is PROBE FAILED, exit 2" "$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: no manifest at ')" "2/1"
mkdir -p "$W/empty"; : >"$W/empty/manifest.txt"
GOT=$("$PY" "$HERE/extract.py" --out "$W/empty" --transcripts "$STUB_TRANSCRIPTS" 2>&1); RC=$?
eq "K05h an empty manifest is PROBE FAILED, exit 2, never a clean zero" "$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: no `tag sid` row')" "2/1"
GOT=$("$PY" "$HERE/extract.py" --out "$OUT" --transcripts "$W/no-such-dir" 2>&1); RC=$?
eq "K05i a missing transcript directory is PROBE FAILED, exit 2" "$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: no transcript directory at ')" "2/1"
mkdir -p "$W/partial"; { head -1 "$OUT/manifest.txt"; echo "ghost-shortest 00000000-0000-0000-0000-000000000000"; } >"$W/partial/manifest.txt"
GOT=$("$PY" "$HERE/extract.py" --out "$W/partial" --transcripts "$STUB_TRANSCRIPTS" 2>&1); RC=$?
eq "K05j a row without a transcript is PROBE FAILED naming it, exit 2, and the other row is still reported" \
	"$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: ghost-shortest has no transcript at ')/$(printf '%s\n' "$GOT" | grep -c '^tutor-shortest ')" "2/1/1"
mkdir -p "$W/denials"; cp "$OUT/manifest.txt" "$W/denials/manifest.txt"
printf '{"type":"result","session_id":"x","permission_denials":[{"tool_name":"Bash"}],"num_turns":4}\n' >"$W/denials/tutor-shortest.json"
printf 'not json\n' >"$W/denials/engineer-shortest.json"
GOT=$("$PY" "$HERE/extract.py" --out "$W/denials" --transcripts "$STUB_TRANSCRIPTS" 2>&1); RC=$?
eq "K05l a session's refusal and turn counts are read from its result file and printed (register 2026-09-05)" \
	"$RC/$(printf '%s\n' "$GOT" | grep -c '^tutor-shortest .*denials=1 turns=4 opens_status=')" "0/1"
eq "K05m a missing result file prints absent, never 0 (an unknown is not a measured zero)" \
	"$(printf '%s\n' "$GOT" | grep -c '^generalist-shortest .*denials=absent turns=absent opens_status=')" "1"
eq "K05n an unreadable result file prints absent and the run still exits 0" \
	"$RC/$(printf '%s\n' "$GOT" | grep -c '^engineer-shortest .*denials=absent turns=absent ')" "0/1"
DER=$("$PY" - "$HERE/extract.py" <<'DERIVE_END'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("extract_under_test", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.transcript_dir("/Some/Where-x/@owner/@lab/vault") == os.path.expanduser("~/.claude/projects/-Some-Where-x--owner--lab-vault"))
DERIVE_END
)
eq "K05k the transcript directory is derived as Claude Code derives it (every non-alphanumeric character becomes '-')" "$DER" "True"

# ---------------------------------------------------------------- 6 · render-rubric.py
REN=$("$PY" "$HERE/render-rubric.py" --style shortest --vault "$VAULT" 2>&1); RC=$?
eq "K06a the rubric renders to stdout with the style name and the live Test, whitespace collapsed, from the definitions file" \
	"$RC/$(printf '%s\n' "$REN" | grep -c '^# Rubric for a style re-run on the `shortest` style$')/$(printf '%s\n' "$REN" | grep -c '^Test: each asked part in at most one or two sentences; a why in at most one clause; no term left unexplained\.$')/$(printf '%s\n' "$REN" | grep -c 'from CUSTOMISATION-definitions.md')" "0/1/1/1"
eq "K06b no placeholder is left (control: the template carries them)" "$(printf '%s\n' "$REN" | grep -c '{{')/$(grep -c '{{' "$HERE/rubric.md" | awk '{print ($1 >= 3) ? "yes" : "no"}')" "0/yes"
REN2=$("$PY" "$HERE/render-rubric.py" --style balanced --vault "$VAULT" 2>&1); RC=$?
eq "K06c a style defined in the core file is found there" "$RC/$(printf '%s\n' "$REN2" | grep -c '^Test: every low-level passage earns its place\.$')/$(printf '%s\n' "$REN2" | grep -c 'from CUSTOMISATION.md')" "0/1/1"
GOT=$("$PY" "$HERE/render-rubric.py" --style turbo --vault "$VAULT" 2>&1); RC=$?
eq "K06d an undefined style is PROBE FAILED, exit 2" "$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: no `### turbo` block')" "2/1"
printf '\n### notest\nA style with no Test clause.\n' >>"$VAULT/CUSTOMISATION-definitions.md"
GOT=$("$PY" "$HERE/render-rubric.py" --style notest --vault "$VAULT" 2>&1); RC=$?
eq "K06e a block without a Test is PROBE FAILED, exit 2" "$RC/$(printf '%s\n' "$GOT" | grep -c 'has no `Test:` clause')" "2/1"
GOT=$("$PY" "$HERE/render-rubric.py" --style shortest --vault "$VAULT" --template "$W/no-template.md" 2>&1); RC=$?
eq "K06f a missing template is PROBE FAILED, exit 2" "$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: no rubric template at ')" "2/1"
printf '# {{STYLE}} {{STYLE_TEST}} {{RENDERED}} {{UNKNOWN}}\n' >"$W/bad-template.md"
GOT=$("$PY" "$HERE/render-rubric.py" --style shortest --vault "$VAULT" --template "$W/bad-template.md" 2>&1); RC=$?
eq "K06g a placeholder the renderer does not know is PROBE FAILED, exit 2" "$RC/$(printf '%s\n' "$GOT" | grep -c '^PROBE FAILED: placeholder(s) left unrendered: {{UNKNOWN}}$')" "2/1"
WR=$("$PY" "$HERE/render-rubric.py" --style shortest --vault "$VAULT" --out "$W/rout" 2>&1); RC=$?
eq "K06h with --out it writes <dir>/rubric.md and prints the embedded Test" \
	"$RC/$(grep -c '^Test: each asked part' "$W/rout/rubric.md")/$(printf '%s\n' "$WR" | grep -c '^rubric: .*rout/rubric.md rendered for the shortest style (CUSTOMISATION-definitions.md); embedded: Test: each asked part')" "0/1/1"

# ---------------------------------------------------------------- 7 · the kit's guarantees in the source
eq "K07a no script counts words (no split-and-count, no wc; control: the pattern hits a planted line)" \
	"$(cat "$HERE/run.sh" "$HERE/extract.py" "$HERE/render-rubric.py" | grep -c -E 'len\([A-Za-z_.]+\.split\(|\bwc -w\b|word_count')/$(printf 'n = len(t.split())\n' | grep -c -E 'len\([A-Za-z_.]+\.split\(')" "0/1"
echo "  info — occurrences of 'word' in extract.py (expected in comments only):"; grep -n -i 'word' "$HERE/extract.py" | sed 's/^/         /'
eq "K07b no owner path or name in the shipped files (control: the pattern hits a planted line)" \
	"$(cat "$HERE/run.sh" "$HERE/extract.py" "$HERE/render-rubric.py" "$HERE/rubric.md" "$HERE/judge-brief.md" "$HERE/README.md" "$HERE/test_style_rerun.sh" | grep -c -E '/Us[e]rs/|/home/[a-z]|One[D]rive')/$(printf '/Us%srs/x\n' e | grep -c -E '/Us[e]rs/')" "0/1"
eq "K07c no wikilink in the scripts or templates (control: the pattern hits a planted line)" \
	"$(cat "$HERE/run.sh" "$HERE/extract.py" "$HERE/render-rubric.py" "$HERE/rubric.md" "$HERE/judge-brief.md" "$HERE/README.md" | grep -c '\[\[[^:]')/$(printf '[[x]]\n' | grep -c '\[\[[^:]')" "0/1"
eq "K07d the run loop calls claude in print mode with the read-only tool set (control for the stub run)" \
	"$(grep -c 'claude -p "\$role, \$STYLE\. \$question" --model "\$MODEL" --session-id "\$sid" --allowedTools "Read,Grep,Glob" --output-format json' "$HERE/run.sh")" "1"
eq "K07e the read-only scripts open no file for writing outside their run directory (extract: one write, the .full.txt; render: one write, rubric.md)" \
	"$(grep -c 'open(.*"w"' "$HERE/extract.py")/$(grep -c 'open(.*"w"' "$HERE/render-rubric.py")/$(grep -c -E 'os\.(remove|unlink|rename|replace|rmdir)|rmtree|shutil' "$HERE/extract.py" "$HERE/render-rubric.py" | awk -F: '{s+=$2} END {print s}')" "1/1/0"

TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
	echo "PASS $PASS/$TOTAL"
	exit 0
fi
echo "FAIL $FAIL/$TOTAL"
exit 1
