#!/bin/bash
# style-rerun/run.sh — fresh headless head sessions, one per question, on one output style.
#
# Each line of the questions file reads `role: question`. For each, one `claude -p` session starts
# from the vault root with the hand-off opener "<role>, <style>. <question>", so the live hooks (the
# role/style anchor, the Stop verifier) act on it exactly as on an owner session, and the reply is
# what a fresh head prints under the shipped texts. The session id is chosen here so extract.py can
# find the transcript afterwards. Written into --out: <tag>.json (the CLI's JSON result), <tag>.err,
# manifest.txt (`tag sid` per line), progress.log, questions.txt (a copy) and rubric.md (rendered by
# render-rubric.py from the live style definition, so the judge's rubric never goes stale).
#
# Nothing here counts, logs or judges words: length is never a measure of a reply (owner ruling
# 2026-09-05); the judge reads content and plainness.
#
#   run.sh [--questions FILE] [--style NAME] [--model ID] [--out DIR] [--record FILE]
#          [--vault DIR] [--run-id ID] [--dry-run]
#
#   --questions  default: ~/.llm-wiki/style-rerun/questions.txt if present (this vault's real questions,
#                machine-local), else questions.txt beside this script (a generic example)
#   --style      default: shortest
#   --model      default: claude-fable-5-1
#   --out        default: $HOME/.llm-wiki/style-rerun/<YYYYMMDD-HHMMSS>/
#   --record     a spawn-record file: a probe-open and a probe-closed line per session (optional)
#   --vault      the vault root the sessions run from (default: the current directory)
#   --run-id     the run id written into the record (default: run-<YYYYMMDD>-style-rerun)
#   --dry-run    validate the inputs, print the plan (one line per session) and write nothing
#
# A broken premise (no questions file, no usable line, a malformed line, no vault CUSTOMISATION.md,
# no style definition, claude not on PATH) prints PROBE FAILED and exits 2, never an empty run that
# reads as done. Exit 1 when a session's claude call returned non-zero (named in progress.log).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# The questions file: the machine-local one wins (this vault's real questions, never shipped with the
# public template), else the generic example beside this script (owner ruling 2026-09-05: vault-specific
# content stays out of the skill folder, which the export copies whole).
export PYTHONDONTWRITEBYTECODE=1   # never leave bytecode beside the shipped kit (known-issues 2026-09-03)
LOCALQ="$HOME/.llm-wiki/style-rerun/questions.txt"
if [ -f "$LOCALQ" ]; then QUESTIONS="$LOCALQ"; else QUESTIONS="$HERE/questions.txt"; fi
STYLE=shortest; MODEL=claude-fable-5-1
OUT=""; REC=""; VAULT="$PWD"; RUN_ID=""; DRY=0
while [ $# -gt 0 ]; do
	case "$1" in
		--questions) QUESTIONS="$2"; shift 2;;
		--style) STYLE="$2"; shift 2;;
		--model) MODEL="$2"; shift 2;;
		--out) OUT="$2"; shift 2;;
		--record) REC="$2"; shift 2;;
		--vault) VAULT="$2"; shift 2;;
		--run-id) RUN_ID="$2"; shift 2;;
		--dry-run) DRY=1; shift;;
		-h|--help) sed -n '2,28p' "$0"; exit 0;;
		*) echo "PROBE FAILED: unknown argument $1"; exit 2;;
	esac
done
[ -n "$OUT" ] || OUT="$HOME/.llm-wiki/style-rerun/$(date +%Y%m%d-%H%M%S)"
[ -n "$RUN_ID" ] || RUN_ID="run-$(date +%Y%m%d)-style-rerun"
case "$STYLE" in *[!A-Za-z0-9_-]*|"") echo "PROBE FAILED: a style name is one word ($STYLE)"; exit 2;; esac
[ -f "$QUESTIONS" ] || { echo "PROBE FAILED: no questions file at $QUESTIONS"; exit 2; }
[ -f "$VAULT/CUSTOMISATION.md" ] || { echo "PROBE FAILED: $VAULT is not a vault root (no CUSTOMISATION.md)"; exit 2; }

# the plan: one `tag<TAB>role<TAB>question` per usable line; a blank or # line is skipped
PLAN=""; count=0; lineno=0; used=" "
while IFS= read -r line || [ -n "$line" ]; do
	lineno=$((lineno + 1))
	case "$line" in ""|\#*) continue;; esac
	role=${line%%:*}; question=${line#*:}
	question=$(printf '%s' "$question" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	case "$role" in *[!A-Za-z0-9_-]*|"") echo "PROBE FAILED: line $lineno of $QUESTIONS is not 'role: question' ($line)"; exit 2;; esac
	[ -n "$question" ] || { echo "PROBE FAILED: line $lineno of $QUESTIONS has no question"; exit 2; }
	[ "$role" = "$line" ] && { echo "PROBE FAILED: line $lineno of $QUESTIONS has no 'role:' prefix"; exit 2; }
	count=$((count + 1)); tag="$role-$STYLE"
	case "$used" in *" $tag "*) tag="$tag-$count";; esac   # a second question for the same role keeps its own tag
	used="$used$tag "
	PLAN="$PLAN$tag	$role	$question
"
done <"$QUESTIONS"
[ "$count" -gt 0 ] || { echo "PROBE FAILED: no usable 'role: question' line in $QUESTIONS"; exit 2; }
# the style definition must render before any session is paid for (the judge needs the rubric)
python3 "$HERE/render-rubric.py" --style "$STYLE" --vault "$VAULT" >/dev/null || { echo "PROBE FAILED: render-rubric.py could not render the $STYLE style from $VAULT"; exit 2; }

if [ "$DRY" -eq 1 ]; then
	echo "dry run: $count session(s) on the $STYLE style, model $MODEL, from $VAULT"
	echo "out: $OUT (not created)"; echo "record: ${REC:-none}"; n=0
	printf '%s' "$PLAN" | while IFS='	' read -r tag role question; do
		n=$((n + 1)); echo "plan $n: tag=$tag prompt=\"$role, $STYLE. $question\""
	done
	exit 0
fi

command -v claude >/dev/null 2>&1 || { echo "PROBE FAILED: claude is not on PATH"; exit 2; }
mkdir -p "$OUT" || { echo "PROBE FAILED: cannot create $OUT"; exit 2; }
python3 "$HERE/render-rubric.py" --style "$STYLE" --vault "$VAULT" --out "$OUT" >/dev/null || { echo "PROBE FAILED: rubric not rendered into $OUT"; exit 2; }
[ "$(cd "$(dirname "$QUESTIONS")" && pwd)/$(basename "$QUESTIONS")" = "$OUT/questions.txt" ] || cp "$QUESTIONS" "$OUT/questions.txt"
: >"$OUT/manifest.txt"
failed=0; n=0
printf '%s' "$PLAN" >"$OUT/.plan.tsv"
while IFS='	' read -r tag role question; do
	n=$((n + 1)); sid=$(python3 -c 'import uuid; print(uuid.uuid4())')
	if [ -n "$REC" ]; then
		printf '{"ts":"%s","run":"%s","event":"probe-open","lane":"RERUN-%s","kind":"headless head session (claude -p from the vault root, hooks active)","session":"%s","model":"%s","reason":"instrument rule (a): a fresh head-shaped context under live enforcement, the observation an in-session lane cannot give; one per question on the %s style","role":"%s","style":"%s","read_tools":"Read,Grep,Glob"}\n' \
			"$(date +%Y-%m-%dT%H:%M%z)" "$RUN_ID" "$n" "$sid" "$MODEL" "$STYLE" "$role" "$STYLE" >>"$REC"
	fi
	echo "[$(date +%H:%M:%S)] start $tag sid=$sid" >>"$OUT/progress.log"
	# stdin from /dev/null: `claude -p` reads a non-terminal stdin as part of its prompt, and inside this loop
	# stdin is the remaining plan lines (the first live run, 2026-09-05, sent every session the other rows too)
	(cd "$VAULT" && claude -p "$role, $STYLE. $question" --model "$MODEL" --session-id "$sid" --allowedTools "Read,Grep,Glob" --output-format json </dev/null) >"$OUT/$tag.json" 2>"$OUT/$tag.err"
	rc=$?
	[ "$rc" -eq 0 ] || failed=$((failed + 1))
	if [ -n "$REC" ]; then
		printf '{"ts":"%s","run":"%s","event":"probe-closed","lane":"RERUN-%s","session":"%s","exit":%s}\n' \
			"$(date +%Y-%m-%dT%H:%M%z)" "$RUN_ID" "$n" "$sid" "$rc" >>"$REC"
	fi
	echo "[$(date +%H:%M:%S)] done $tag rc=$rc" >>"$OUT/progress.log"
	echo "$tag $sid" >>"$OUT/manifest.txt"
done <"$OUT/.plan.tsv"
rm -f "$OUT/.plan.tsv"
echo "ALL DONE $(date +%H:%M:%S)" >>"$OUT/progress.log"
# The run stamp (critic CRIT-3 F4): machine-local, never inside the skill folder (which the export copies
# whole). One line per successful run: date · style · sha256 of the rendered Test, so deep-lint's step 7b
# can skip a re-run when the Test has not changed (compare `render-rubric.py --style <s> --test-only | shasum -a 256`).
if [ "$failed" -eq 0 ]; then
	STAMPDIR="$HOME/.llm-wiki/style-rerun"; mkdir -p "$STAMPDIR"
	TESTHASH=$(/usr/local/bin/python3 "$HERE/render-rubric.py" --style "$STYLE" --vault "$VAULT" --test-only 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
	[ -n "$TESTHASH" ] && printf '%s %s %s %s\n' "$(date +%Y-%m-%d)" "$STYLE" "$TESTHASH" "$OUT" >> "$STAMPDIR/last-run.txt"
fi
echo "style-rerun: $n session(s) on the $STYLE style; out=$OUT; manifest=$OUT/manifest.txt; non-zero exits=$failed"
[ "$failed" -eq 0 ]
