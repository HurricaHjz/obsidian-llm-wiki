#!/bin/sh
# test_throttle.sh — regression suite for throttle.py (delegate skill, the routing throttle).
#
# Every fixture is a throwaway vault under one `mktemp -d`: a copy of routing.json, a synthetic
# CUSTOMISATION.md, and one definition per routed role (the live `.claude/agents/` copy where the
# vault has one, a generated stand-in where it does not, so the suite also runs on a fresh clone
# that ships no definitions). `set` is never run outside those fixtures.
#
# Controls (CLAUDE.md 11): every leg that asserts a clean or empty result is paired with a leg that
# plants the fault and proves the same probe fires. The expected model/effort values are pinned as
# literals below, hand-derived from the design page's routing record, so the suite does not grade
# the code against the same file the code reads.
#
# Run:  sh test_throttle.sh          (last line: PASS n/n or FAIL k/n; exit 0 only when clean)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/throttle.py"
R="$HERE/routing.json"
VAULT=$(cd "$HERE/../../.." && pwd)      # .claude/skills/delegate -> vault root
PY="${PYTHON:-python3}"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   — $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL   — $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }

W=$(mktemp -d)
OUT="$W/out.txt"
cleanup() { chmod -R u+w "$W" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT
[ -f "$S" ] || { echo "PROBE FAILED: no throttle.py at $S"; echo "FAIL 1/1"; exit 2; }
[ -f "$R" ] || { echo "PROBE FAILED: no routing.json at $R"; echo "FAIL 1/1"; exit 2; }

run() { "$@" >"$OUT" 2>&1; RC=$?; }
has() { grep -qF -- "$2" "$OUT" && ok "$1" || no "$1 (stdout lacks '$2')"; }
hasnot() { grep -qF -- "$2" "$OUT" && no "$1 (stdout still holds '$2')" || ok "$1"; }

# The value of one frontmatter field, read by an awk parser of its own so a definition is never
# graded by the parser under test.
fmval() {
	awk -v k="$2" '
	  NR==1 { if ($0 != "---") exit }
	  NR>1  { if ($0 == "---") exit
	          if (index($0, k ":") == 1) { v = substr($0, length(k)+2)
	                                       gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$1"
}
# Everything below the frontmatter, hashed — the proof `set` touched no body byte.
bodyhash() { "$PY" "$W/bodyhash.py" "$1"; }
# One checksum manifest of a whole fixture, for the "wrote nothing" legs.
manifest() { (cd "$1" && find . -type f -print0 | xargs -0 shasum) | LC_ALL=C sort; }

# ------------------------------------------------------------------ helper scripts ----------
cat >"$W/bodyhash.py" <<'BODYHASH_SCRIPT_END'
import hashlib, sys
raw = open(sys.argv[1], "rb").read()
lines = raw.splitlines(keepends=True)
close = None
for i in range(1, len(lines)):
    if lines[i].rstrip(b"\r\n") == b"---":
        close = i
        break
body = b"".join(lines[close + 1:]) if close is not None else raw
print(hashlib.sha256(body).hexdigest())
BODYHASH_SCRIPT_END

cat >"$W/mkfix.py" <<'MKFIX_SCRIPT_END'
"""Build one throwaway vault: synthetic CUSTOMISATION.md + one definition per routed role."""
import json, os, shutil, sys

dest, vault = sys.argv[1], sys.argv[2]
rec = json.load(open(os.path.join(dest, ".claude", "skills", "delegate", "routing.json")))
custom = """`CUSTOMISATION-LOADED-v1` — load marker.

## Settings
The live knobs.

- **agent_name**: testbot — what the agent calls itself (blank = none)
- **style**: balanced — any style defined in `## Output styles`
- **role**: generalist — any role defined in `## Roles`
- **language**: English (UK) — conversation language
- **effort**: standard — delegation compute tier: light · standard · max
- **pre-report**: auto — spawn-record echo before delegated runs: on · auto · off

## Identity
- a synthetic fixture, not a vault.
"""
with open(os.path.join(dest, "CUSTOMISATION.md"), "w", encoding="utf-8") as fh:
    fh.write(custom)

# A copied definition's real description may name a current tier, which `check` reports.
# The fixture's baseline has to be clean for the drift legs to mean anything, so every
# copied description is replaced by the durable range wording, which the stand-ins carry
# too; the description legs below plant the tier form back and prove the finding fires.
DURABLE = ("description: Routing range (admitted 2026-09-02): model sonnet–fable, "
           "effort high–max; the active throttle sets the current values.\n")
STAND_IN = """---
name: %s
""" + DURABLE + """model: %s
effort: %s
disallowedTools: Agent, SendMessage
---

Body text the throttle must never touch.
"""
live = os.path.join(vault, ".claude", "agents")
for role, spec in rec["roles"].items():
    dst = os.path.join(dest, ".claude", "agents", role + ".md")
    src = os.path.join(live, role + ".md")
    if os.path.isfile(src):
        lines = open(src, encoding="utf-8").read().splitlines(keepends=True)
        in_fm = bool(lines) and lines[0].rstrip("\r\n") == "---"
        out = []
        for i, line in enumerate(lines):
            if in_fm and i > 0 and line.rstrip("\r\n") == "---":
                in_fm = False
            elif in_fm and i > 0 and line.startswith("description:"):
                line = DURABLE
            out.append(line)
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write("".join(out))
    else:
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(STAND_IN % (role, spec["model"][1], spec["effort"][1]))
MKFIX_SCRIPT_END

mkfix() {
	d="$W/$1"
	rm -rf "$d"
	mkdir -p "$d/.claude/agents" "$d/.claude/skills/delegate"
	cp "$R" "$d/.claude/skills/delegate/routing.json"
	"$PY" "$W/mkfix.py" "$d" "$VAULT" || { echo "PROBE FAILED: fixture build for $1"; exit 2; }
}

# The expected values, hand-derived from the routing record in the design page:
#   order model haiku < sonnet < opus < fable ; order effort low < medium < high < xhigh < max
#   critic opus/opus/fable + xhigh/max · gate-judge opus/opus/opus + max/max
#   wiki-compile sonnet/opus/fable + medium/max · builder sonnet/opus/fable + high/max
#   memory-hunter sonnet/sonnet/fable + high/max
# top = ceiling/ceiling · default = default/ceiling · cheap = floor/ceiling
# fast = default/floor · cheap-fast = floor/floor
pins() { # $1 throttle -> "role model effort" triples, one per line
	case "$1" in
	top) printf 'critic fable max\ngate-judge opus max\nwiki-compile fable max\nbuilder fable max\n' ;;
	default) printf 'critic opus max\ngate-judge opus max\nwiki-compile opus max\nbuilder opus max\n' ;;
	cheap) printf 'critic opus max\ngate-judge opus max\nwiki-compile sonnet max\nbuilder sonnet max\n' ;;
	fast) printf 'critic opus xhigh\ngate-judge opus max\nwiki-compile opus medium\nbuilder opus high\n' ;;
	cheap-fast) printf 'critic opus xhigh\ngate-judge opus max\nwiki-compile sonnet medium\nbuilder sonnet high\n' ;;
	esac
}
headline() {
	case "$1" in
	top | default) echo "head: fable · max" ;;
	cheap | cheap-fast) echo "head: opus · max recommended" ;;
	fast) echo "head: fable · high recommended" ;;
	esac
}

ROLES=$("$PY" -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["roles"]))' "$R")
NROLES=$("$PY" -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["roles"]))' "$R")

echo "throttle.py suite — $NROLES routed roles, fixtures under $W"

# ================================================================== 1 · show ==========
mkfix show1
run "$PY" "$S" show --root "$W/show1"
eq "L01a show exits 0" "$RC" "0"
has "L01b show reports the absent Settings line" "throttle: default (line absent)"
eq "L01c show prints the pinned default row for wiki-compile" \
	"$(awk '$1=="wiki-compile"{print $2, $3}' "$OUT")" "opus max"
has "L01d show prints the head recommendation" "head: fable · max"
seen=0
for r in $ROLES; do
	awk -v r="$r" '$1==r{f=1} END{exit !f}' "$OUT" && seen=$((seen + 1))
done
eq "L01e show prints one table row per routed role" "$seen" "$NROLES"

# ================================================================== 2 · set + check ===
for T in top default cheap fast cheap-fast; do
	mkfix "s_$T"
	d="$W/s_$T"
	run "$PY" "$S" set "$T" --root "$d"
	eq "L02.$T set exits 0" "$RC" "0"
	run "$PY" "$S" check --root "$d"
	eq "L03.$T check clean after set" "$RC" "0"
	has "L04.$T check reports clean against '$T'" "match throttle '$T'"
	has "L05.$T check carries its comparator control" "control: comparator caught 2/2 planted drifts"
	bad=0
	pins "$T" | while read -r role m e; do
		[ "$(fmval "$d/.claude/agents/$role.md" model)" = "$m" ] || echo "$role model" >>"$W/pinfail"
		[ "$(fmval "$d/.claude/agents/$role.md" effort)" = "$e" ] || echo "$role effort" >>"$W/pinfail"
	done
	if [ -s "$W/pinfail" ]; then
		no "L06.$T pinned values on disk ($(tr '\n' ',' <"$W/pinfail"))"
		rm -f "$W/pinfail"
	else
		ok "L06.$T pinned values on disk"
	fi
	run "$PY" "$S" show --root "$d"
	eq "L07.$T show's head recommendation" "$(grep -F 'head: ' "$OUT")" "$(headline "$T")"
	bad=$bad
done

# ================================================================== 3 · idempotency ===
d="$W/s_default"
BEFORE=$(manifest "$d")
run "$PY" "$S" set default --root "$d"
eq "L08a second set exits 0" "$RC" "0"
has "L08b second set says there is nothing to do" "nothing to do (already at 'default')"
eq "L08c second set left every byte identical" "$(manifest "$d")" "$BEFORE"

# ================================================================== 4 · planted drift =
# Control pair for L03.default: the same check on the same fixture, one field moved.
d="$W/drift"
mkfix drift
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
eq "L09a control — check is clean before the plant" "$RC" "0"
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_DRIFT_END'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read().replace("\neffort: max\n", "\neffort: low\n", 1)
open(p, "w", encoding="utf-8").write(t)
PLANT_DRIFT_END
run "$PY" "$S" check --root "$d"
eq "L09b planted drift exits 1" "$RC" "1"
has "L09c planted drift names the file and the field" "DRIFT .claude/agents/critic.md: effort low ≠ max"

# ================================================================== 5 · Settings line =
d="$W/absent"
mkfix absent
run "$PY" "$S" set default --root "$d"
n=$(grep -n -F -- '- **pre-report**:' "$d/CUSTOMISATION.md" | head -1 | cut -d: -f1)
nxt=$(sed -n "$((n + 1))p" "$d/CUSTOMISATION.md")
case "$nxt" in
'- **throttle**: default — subagent routing throttle: top · default · cheap · fast · cheap-fast; semantics in the delegate skill §2 (say "set throttle to X"; the head runs throttle.py set)')
	ok "L10a set inserts the exact Settings line directly after pre-report" ;;
*) no "L10a set inserts the exact Settings line directly after pre-report (got '$nxt')" ;;
esac
"$PY" - "$d/CUSTOMISATION.md" <<'DROP_LINE_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?mi)^-\s*\*\*throttle\*\*:.*\n", "", open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
DROP_LINE_END
run "$PY" "$S" check --root "$d"
eq "L10b a missing Settings line is not a failure" "$RC" "0"
has "L10c the missing line is reported once" "throttle: default (Settings line absent)"

# ================================================================== 6 · broken premises
d="$W/premise"
mkfix premise
run "$PY" "$S" check --root "$d"
# The intact fixture may be clean (stand-in definitions) or hold a drift (a live definition
# already off the routing default); either is a run. Only exit 2 would mean the probe never ran.
eq "L11a control — the premise fixture checks without a probe failure" \
	"$(if [ "$RC" = "2" ]; then echo probe-failed; else echo ran; fi)" "ran"
hasnot "L11b control — no PROBE FAILED on the intact fixture" "PROBE FAILED"

sed -i.bak 's/^- \*\*pre-report\*\*: auto/- **throttle**: turbo — bogus\
- **pre-report**: auto/' "$d/CUSTOMISATION.md"
run "$PY" "$S" check --root "$d"
eq "L12a unknown throttle name exits 2" "$RC" "2"
has "L12b unknown throttle name names it" "PROBE FAILED: unknown throttle 'turbo'"
mv "$d/CUSTOMISATION.md.bak" "$d/CUSTOMISATION.md"

RJ="$d/.claude/skills/delegate/routing.json"
mv "$RJ" "$W/rj.keep"
run "$PY" "$S" check --root "$d"
eq "L13a a missing routing record exits 2 (never a silent fallback to another copy)" "$RC" "2"
has "L13b the missing record names its path" "PROBE FAILED: no routing record at"
mv "$W/rj.keep" "$RJ"

printf '{"order": {"model": [' >"$RJ.broken"
cp "$RJ" "$W/rj.keep"
cp "$RJ.broken" "$RJ"
run "$PY" "$S" check --root "$d"
eq "L14a invalid JSON exits 2" "$RC" "2"
has "L14b invalid JSON says so" "is not valid JSON"
cp "$W/rj.keep" "$RJ"

chmod 000 "$RJ"
if [ -r "$RJ" ]; then
	no "L15 unreadable-record leg (chmod 000 left the file readable — leg cannot run)"
else
	run "$PY" "$S" check --root "$d"
	if [ "$RC" = "2" ] && grep -qF -- "unreadable" "$OUT"; then
		ok "L15 an unreadable routing record exits 2"
	else
		no "L15 an unreadable routing record exits 2 (rc=$RC)"
	fi
fi
chmod 644 "$RJ"

"$PY" - "$RJ" <<'NONMONOTONE_END'
import json, sys
p = sys.argv[1]
rec = json.load(open(p))
rec["roles"]["critic"]["model"] = ["fable", "opus", "sonnet"]   # ceiling below the floor
json.dump(rec, open(p, "w"))
NONMONOTONE_END
BEFORE=$(manifest "$d")
run "$PY" "$S" set top --root "$d"
eq "L16a a non-monotone record refuses set, exit 2" "$RC" "2"
has "L16b the refusal names the role and axis" "role \`critic\` model range is not floor"
eq "L16c the refused set wrote nothing" "$(manifest "$d")" "$BEFORE"
cp "$W/rj.keep" "$RJ"
BEFORE=$(manifest "$d")
run "$PY" "$S" set top --root "$d"
eq "L16d control — with the record repaired the same set does write" \
	"$(if [ "$(manifest "$d")" = "$BEFORE" ]; then echo unchanged; else echo changed; fi)" "changed"

d="$W/badfm"
mkfix badfm
"$PY" - "$d/.claude/agents/verifier.md" <<'BREAK_FM_END'
import sys
p = sys.argv[1]
open(p, "w", encoding="utf-8").write("no frontmatter here\nmodel: opus\n")
BREAK_FM_END
run "$PY" "$S" check --root "$d"
eq "L17a an unparseable definition exits 2" "$RC" "2"
has "L17b it names the file and the reason" "verifier.md: no frontmatter"

run "$PY" "$S" set nitro --root "$W/badfm"
eq "L18a an unknown NAME on set exits 2" "$RC" "2"
has "L18b it lists the known names" "PROBE FAILED: unknown throttle 'nitro'"

# ================================================================== 7 · roster findings
d="$W/roster"
mkfix roster
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
eq "L19a control — the roster fixture is clean before the plant" "$RC" "0"
printf -- '---\nname: stranger\nmodel: opus\neffort: max\n---\n\nbody\n' >"$d/.claude/agents/stranger.md"
run "$PY" "$S" check --root "$d"
eq "L19b an unrouted definition is a finding" "$RC" "1"
has "L19c it is named as UNROUTED" "UNROUTED .claude/agents/stranger.md"
rm -f "$d/.claude/agents/stranger.md"
rm -f "$d/.claude/agents/reflector.md"
run "$PY" "$S" check --root "$d"
eq "L20a a routed role with no definition is a finding" "$RC" "1"
has "L20b it is named as MISSING" "MISSING .claude/agents/reflector.md"

# ================================================================== 8 · --require =====
d="$W/require"
mkfix require
run "$PY" "$S" set cheap --root "$d"
run "$PY" "$S" check --root "$d" --require cheap
eq "L21a control — --require matching the active throttle is clean" "$RC" "0"
run "$PY" "$S" check --root "$d" --require default
eq "L21b --require default against a cheap vault exits 1" "$RC" "1"
has "L21c the require finding names both" "REQUIRE default: the active throttle is cheap"

# ================================================================== 9 · --dry-run =====
d="$W/dry"
mkfix dry
BEFORE=$(manifest "$d")
run "$PY" "$S" set top --root "$d" --dry-run
eq "L22a --dry-run exits 0" "$RC" "0"
has "L22b --dry-run says nothing was written" "(dry run — nothing written)"
eq "L22c --dry-run left every byte identical" "$(manifest "$d")" "$BEFORE"
run "$PY" "$S" set top --root "$d"
eq "L22d control — the same set without --dry-run does write" \
	"$(if [ "$(manifest "$d")" = "$BEFORE" ]; then echo unchanged; else echo changed; fi)" "changed"

# ================================================================== 10 · body bytes ===
d="$W/body"
mkfix body
for role in $ROLES; do
	bodyhash "$d/.claude/agents/$role.md" >>"$W/body.before"
done
run "$PY" "$S" set cheap-fast --root "$d"
for role in $ROLES; do
	bodyhash "$d/.claude/agents/$role.md" >>"$W/body.after"
done
eq "L23a set changed no body byte in any definition" \
	"$(cat "$W/body.before")" "$(cat "$W/body.after")"
eq "L23b control — the frontmatter did move" \
	"$(fmval "$d/.claude/agents/wiki-compile.md" effort)" "medium"

# ================================================================== 11 · other fields =
d="$W/fields"
mkfix fields
cat >"$d/.claude/agents/gate-judge.md" <<'GATE_FIXTURE_END'
---
name: gate-judge
description: A fixture definition carrying every extra frontmatter shape the vault uses.
model: haiku
effort: low
tools: Read, Grep, Glob
memory: local
skills:
  - ingest
---

Body text the throttle must never touch.
GATE_FIXTURE_END
run "$PY" "$S" set top --root "$d"
eq "L24a set rewrote the two routed fields" \
	"$(fmval "$d/.claude/agents/gate-judge.md" model)/$(fmval "$d/.claude/agents/gate-judge.md" effort)" \
	"opus/max"
eq "L24b every other frontmatter line survived byte-identical" \
	"$(sed -n '2,$p' "$d/.claude/agents/gate-judge.md" | sed -n '/^---$/q;p' | grep -v '^model:\|^effort:')" \
	"$(printf 'name: gate-judge\ndescription: A fixture definition carrying every extra frontmatter shape the vault uses.\ntools: Read, Grep, Glob\nmemory: local\nskills:\n  - ingest')"

# ================================================================== 12 · absent fields
d="$W/nofields"
mkfix nofields
cat >"$d/.claude/agents/planner.md" <<'NOFIELDS_FIXTURE_END'
---
name: planner
description: A fixture definition with neither routed field.
disallowedTools: Agent, SendMessage
---

Body text the throttle must never touch.
NOFIELDS_FIXTURE_END
run "$PY" "$S" check --root "$d"
eq "L25a an absent field is a finding" "$RC" "1"
has "L25b the finding says the field is absent" "DRIFT .claude/agents/planner.md: model absent ≠ opus"
run "$PY" "$S" set default --root "$d"
eq "L25c set adds both fields, exit 0" "$RC" "0"
eq "L25d the added fields hold the resolved values" \
	"$(fmval "$d/.claude/agents/planner.md" model)/$(fmval "$d/.claude/agents/planner.md" effort)" \
	"opus/max"
run "$PY" "$S" check --root "$d"
eq "L25e check is clean once the fields exist" "$RC" "0"

# ================================================================== 13 · stdout only ==
# `show` and `check` must need no write permission at all, and must leave every byte alone.
d="$W/ro"
mkfix ro
run "$PY" "$S" set default --root "$d"
BEFORE=$(manifest "$d")
chmod -R a-w "$d"
run "$PY" "$S" show --root "$d"
RC1=$RC
run "$PY" "$S" check --root "$d"
RC2=$RC
run "$PY" "$S" check --root "$d" --require default
RC3=$RC
run "$PY" "$S" set top --root "$d" --dry-run
RC4=$RC
chmod -R u+w "$d"
eq "L26a show/check/--require/--dry-run all ran on a read-only copy" "$RC1$RC2$RC3$RC4" "0000"
eq "L26b the read-only copy is byte-identical afterwards" "$(manifest "$d")" "$BEFORE"

# Source grep: one write call site, reached only from cmd_set. Its own positive control is that
# the pattern must hit at all — a zero-hit grep would "prove" the script never writes.
WRITES=$(grep -c -E 'open\([^)]*"w"|os\.remove|os\.replace|os\.rename|shutil\.|\.unlink\(' "$S")
eq "L27a exactly one write call site in the source (control: the pattern hits)" "$WRITES" "1"
eq "L27b that call site sits inside write_text" \
	"$(grep -n -E 'open\([^)]*"w"' "$S" | cut -d: -f1)" \
	"$(awk '/^def write_text/{d=NR} /open\([^)]*"w"/{if (NR>d && d) {print NR; exit}}' "$S")"
eq "L27c write_text is called from exactly one place" "$(grep -c '^ *write_text(' "$S")" "1"
eq "L27d and that place is cmd_set" \
	"$(awk '/^def cmd_set/{s=NR} /^def main/{m=NR} /^ *write_text\(/{c=NR} END{print (c>s && c<m) ? "yes" : "no"}' "$S")" \
	"yes"

# ================================================================== 14 · description ==
# A description naming a CURRENT tier goes stale the moment a throttle moves it. `set` never
# rewrites prose, so `check` reports it for a human to reword.
d="$W/desc"
mkfix desc
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
eq "L28a control — the durable range wording is clean" "$RC" "0"
hasnot "L28b no DESCRIPTION-TIER line on the durable wording" "DESCRIPTION-TIER"
DESC_BEFORE=$(grep -c -F 'the active throttle sets the current values' "$d/.claude/agents/critic.md")
eq "L28c set left the description line in place" "$DESC_BEFORE" "1"
for tier in low medium high xhigh max; do
	"$PY" - "$d/.claude/agents/critic.md" "$tier" <<'PLANT_DESC_END'
import re, sys
p, tier = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
t = re.sub(r"(?m)^description:.*$",
           "description: Routing (owner-set 2026-08-27) opus · %s effort; per-call override." % tier,
           t, count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_DESC_END
	run "$PY" "$S" check --root "$d"
	if [ "$RC" = "1" ] && grep -qF -- "DESCRIPTION-TIER .claude/agents/critic.md" "$OUT"; then
		ok "L29.$tier a description naming '$tier' is a finding"
	else
		no "L29.$tier a description naming '$tier' is a finding (rc=$RC)"
	fi
done
# A word after the separator that is not a tier must not fire: the probe keys on the tier list.
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_NONTIER_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?m)^description:.*$",
           "description: Routing (owner-set 2026-08-27) opus · sonnet effort; per-call override.",
           open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_NONTIER_END
run "$PY" "$S" check --root "$d"
eq "L30a a non-tier word after the separator does not fire" "$RC" "0"
hasnot "L30b and no DESCRIPTION-TIER line is printed" "DESCRIPTION-TIER"
# Live miss 2026-09-02: the reflector wording names a tier without the word "effort".
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_REFL_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?m)^description:.*$",
           "description: Read-only lane. Routing (owner-admitted 2026-08-28) opus · max; fable escalation discouraged.",
           open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_REFL_END
run "$PY" "$S" check --root "$d"
if [ "$RC" = "1" ] && grep -qF -- "DESCRIPTION-TIER .claude/agents/critic.md" "$OUT"; then
	ok "L29r a tier after a middle dot without the word effort is a finding"
else
	no "L29r a tier after a middle dot without the word effort is a finding (rc=$RC)"
fi
# `set` must not rewrite prose, tier-naming or not.
"$PY" - "$d/.claude/agents/critic.md" <<'PLANT_STALE_END'
import re, sys
p = sys.argv[1]
t = re.sub(r"(?m)^description:.*$",
           "description: Routing (owner-set 2026-08-27) opus · max effort; per-call override.",
           open(p, encoding="utf-8").read(), count=1)
open(p, "w", encoding="utf-8").write(t)
PLANT_STALE_END
DESC_BEFORE=$(grep -F 'description:' "$d/.claude/agents/critic.md")
run "$PY" "$S" set cheap --root "$d"
eq "L31 set never rewrites a description, stale tier and all" \
	"$(grep -F 'description:' "$d/.claude/agents/critic.md")" "$DESC_BEFORE"

# ================================================================== 15 · N of M =======
d="$W/count"
mkfix count
run "$PY" "$S" set default --root "$d"
run "$PY" "$S" check --root "$d"
has "L32a the summary names how many of the routed roles were diffed" "$NROLES of $NROLES diffed"
rm -f "$d/.claude/agents/verifier.md"
run "$PY" "$S" check --root "$d"
has "L32b control — one definition short, the count drops" "$((NROLES - 1)) of $NROLES diffed"

# ================================================================== 16 · no agents ====
d="$W/noagents"
mkfix noagents
run "$PY" "$S" check --root "$d"
eq "L33a control — the fixture checks while the directory is there" \
	"$(if [ "$RC" = "2" ]; then echo probe-failed; else echo ran; fi)" "ran"
rm -rf "$d/.claude/agents"
run "$PY" "$S" check --root "$d"
eq "L33b an absent .claude/agents directory is a broken premise, exit 2" "$RC" "2"
has "L33c it says which directory is missing" "PROBE FAILED: no definitions directory at .claude/agents"
run "$PY" "$S" set default --root "$d"
eq "L33d set refuses the same way" "$RC" "2"

# ================================================================== tally =============
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
	echo "PASS $PASS/$TOTAL"
	exit 0
fi
echo "FAIL $FAIL/$TOTAL"
exit 1
