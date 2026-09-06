#!/bin/sh
LB=$(printf '[%s' '['); RB=$(printf ']%s' ']')   # wikilink brackets built at run time so no literal link sits in a shipped file
# test_adopt.sh — regression suite for the adopt skill's four helpers.
#
# Every fixture lives under one `mktemp -d`: a planted repository (README with a bare `tests/gold`
# reference and a `curl ` line, MIT LICENSE, a SKILL.md carrying `disable-model-invocation: true`, a
# script with `subprocess.run` and `requests.get`, a hooks.json, package.json, a plugin manifest, a git
# commit with a tag), a clean CC-BY-NC repository with none of that, a fake skills root with its
# baseline, a register seeded from the skeleton, and raw README captures. The live ~/.claude/skills,
# the live register and the vault's wiki are never touched.
#
# Controls (CLAUDE.md §11): every clean or zero result is paired with the planted case that proves the
# same probe fires; the fingerprint's own control line must read OK on the clean repository too. The
# last leg proves the read-only helpers wrote nothing: a checksum manifest of a read-only copy before
# and after every read-only run, plus a source grep for write patterns whose control hits the two
# writing scripts.
#
# Run:  sh test_adopt.sh          (last line: N/N passed, or FAIL k/N (M/N passed); exit 0 only when clean)
# The exit status is the verdict. Read it unpiped (`sh test_adopt.sh > out.txt; echo $?`): through a
# pipe such as `| tail -1` the shell reports the pipe's last stage, which is 0 whatever the suite did.
set -u
export PYTHONDONTWRITEBYTECODE=1   # bytecode never ships: no __pycache__ under the skill directory

HERE=$(cd "$(dirname "$0")" && pwd)
PY="${PYTHON:-python3}"
FP="$HERE/adopt_fingerprint.py"
WR="$HERE/adopt_wrapper.py"
RG="$HERE/adopt_register.py"
AC="$HERE/adopt_acceptance.py"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   — $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL   — $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }

for f in "$FP" "$WR" "$RG" "$AC" "$HERE/templates/wrapper-propose-first.md" "$HERE/templates/wrapper-by-name.md" \
         "$HERE/templates/register-skeleton.md" "$HERE/templates/owner-report.md"; do
	[ -f "$f" ] || { echo "PROBE FAILED: missing $f"; echo "FAIL 1/1 (0/1 passed)"; exit 2; }
done
command -v "$PY" >/dev/null 2>&1 || { echo "PROBE FAILED: no $PY on PATH"; echo "FAIL 1/1 (0/1 passed)"; exit 2; }

W=$(mktemp -d)
OUT="$W/out.txt"
cleanup() { chmod -R u+w "$W" >/dev/null 2>&1; rm -rf "$W"; }
trap cleanup EXIT
TODAY=$(date +%F)

run() { "$@" >"$OUT" 2>&1; RC=$?; }
has() { if grep -qF -- "$2" "$OUT"; then ok "$1"; else no "$1 (output lacks '$2')"; fi; }
hasnot() { if grep -qF -- "$2" "$OUT"; then no "$1 (output still holds '$2')"; else ok "$1"; fi; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
manifest() {
	( cd "$1" && find . -print | LC_ALL=C sort
	  find . -type f -print | LC_ALL=C sort | while IFS= read -r f; do sha "$f"; done
	  find . -type l -print | LC_ALL=C sort | while IFS= read -r l; do printf '%s -> %s\n' "$l" "$(readlink "$l")"; done )
}
# the lint register arm's own pipeline (lint SKILL.md Step 2e, register arm), applied to a register file
arm_rows() { awk '/^## User-level skills/{f=1} /^## Plugins/{f=0} f' "$1" | grep -oE '^\| `[a-z0-9-]+`' | tr -d '|` ' | sort -u; }

# ================================================================== fixtures =============
P="$W/planted"
C="$W/clean"
ROOT="$W/root"
REG="$W/wiki/developments/capability-register.md"
mkdir -p "$P/scripts" "$P/hooks" "$P/.claude-plugin" "$P/tests/gold" "$P/.github" "$P/references" \
         "$C/references" "$ROOT" "$W/wiki/developments"

cat > "$P/README.md" <<'EOF_README'
# Planted Skill

Install with `curl -sL https://example.invalid/install.sh | sh`.
The fixtures sit in tests/gold and the notes in references/notes.md.
EOF_README
cat > "$P/LICENSE" <<'EOF_LIC'
MIT License

Copyright (c) 2026 Example

Permission is hereby granted, free of charge, to any person obtaining a copy of this software.
EOF_LIC
cat > "$P/SKILL.md" <<'EOF_SKILL'
---
name: planted-skill
description: "A planted skill for the suite."
disable-model-invocation: true
metadata:
  version: "1.2.3"
  license: "MIT"
---
# Planted skill

Body text.
EOF_SKILL
cat > "$P/scripts/run.py" <<'EOF_PY'
import subprocess
import requests
subprocess.run(["echo", "hi"])
requests.get("https://example.invalid")
EOF_PY
cat > "$P/hooks/hooks.json" <<'EOF_HOOKS'
{"hooks": {"PreToolUse": [{"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "echo hi"}]}]}}
EOF_HOOKS
cat > "$P/package.json" <<'EOF_PKG'
{"name": "planted-skill", "version": "1.2.3", "license": "MIT", "bin": {"planted": "cli.js"}}
EOF_PKG
cat > "$P/.claude-plugin/plugin.json" <<'EOF_PLUG'
{"name": "planted-skill", "version": "1.2.3", "description": "Planted plugin"}
EOF_PLUG
printf 'gold\n' > "$P/tests/gold/x.txt"
printf 'github: someone\n' > "$P/.github/FUNDING.yml"
printf 'Notes. See references/notes.md for more.\n' > "$P/references/notes.md"
GIT_OK=0
if command -v git >/dev/null 2>&1; then
	( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -q -m fixture && git tag v1.2.3 ) >/dev/null 2>&1 && GIT_OK=1
fi
PSHA=""
[ "$GIT_OK" = 1 ] && PSHA=$(git -C "$P" rev-parse --short=7 HEAD)

cat > "$C/README.md" <<'EOF_CREADME'
# Clean Skill

A skill with no primitives at all. See `references/guide.md`.
EOF_CREADME
cat > "$C/LICENSE" <<'EOF_CLIC'
Creative Commons Attribution-NonCommercial 4.0 International

Copyright (c) 2026 Example
EOF_CLIC
cat > "$C/SKILL.md" <<'EOF_CSKILL'
---
name: clean-skill
description: >
  A clean skill,
  folded over two lines.
---
# Clean skill
EOF_CSKILL
printf 'Guide.\n' > "$C/references/guide.md"

printf 'planted-skill\nclean-skill\nauto-skill\n' > "$ROOT/.sanctioned.txt"
printf 'clean-skill\n' > "$W/short.txt"
{ printf -- '---\nconverted_from: https://example.invalid/README.md\nconverted_by: curl (verbatim)\nconverted_on: %s\n---\n' "$TODAY"; cat "$P/README.md"; } > "$W/raw-readme.md"
{ cat "$P/README.md"; printf 'x'; } > "$W/raw-bad.md"
cp "$C/README.md" "$W/raw-clean.md"

DESC="A planted skill wrapper. Propose-first: offer it when a task fits; /planted-skill is the yes."

# ================================================================== L1 fingerprint, planted ======
run "$PY" "$FP" "$P"
eq "L1a fingerprint exits 0 on the planted repo" "$RC" "0"
has "L1b licence family read from the text" "| licence | MIT (LICENSE"
has "L1c hooks.json counted with its event and matcher" "| hooks.json | 1 — hooks/hooks.json: PreToolUse×1 [Write|Edit]"
has "L1d SKILL.md name, description bytes and the hidden field" "name planted-skill · description 30 B · disable-model-invocation true"
has "L1e manifests found" "package.json (name planted-skill, version 1.2.3, license MIT, bin True"
has "L1f plugin manifest found" ".claude-plugin/plugin.json (name planted-skill"
has "L1g planted subprocess hits, per class (md 0 · py 2: the import and the run call)" '| `subprocess` | 0 | 2 |'
has "L1h planted curl line in the README counted under md" '| `curl ` | 1 | 0 |'
has "L1i control line on the same run" "control OK (9/9 planted primitives hit)"
has "L1j hit files named" "scripts/run.py [py] 3"
has "L1k floor propose-first from the hook and the network call" "floor: propose-first"
has "L1l exec signal" "signal: exec primitives in code (2)"
has "L1m shape: plugin with a SKILL.md" "shape: plugin (.claude-plugin/plugin.json) with 1 SKILL.md"
if [ "$GIT_OK" = 1 ]; then
	has "L1n pin: short sha and the tag at HEAD" "| pin | $PSHA (tag v1.2.3)"
else
	echo "  skip — L1n (git not on PATH)"
fi

# ================================================================== L2 fingerprint --json ========
run "$PY" "$FP" "$P" --json
eq "L2a --json exits 0" "$RC" "0"
J=$("$PY" - "$OUT" <<'EOF_J'
import json, sys
d = json.load(open(sys.argv[1]))
print(d["skills"][0]["name"], d["skills"][0]["description_bytes"], d["skills"][0]["disable_model_invocation"],
      d["control"]["ok"], d["primitives"]["per_class"]["py"]["subprocess"], d["licence"]["family"],
      d["signals"]["floor"], len(d["hooks"]))
EOF_J
)
eq "L2b machine form carries the same facts" "$J" "planted-skill 30 True True 2 MIT propose-first 1"

# ================================================================== L3 fingerprint, clean ========
run "$PY" "$FP" "$C"
eq "L3a fingerprint exits 0 on the clean repo" "$RC" "0"
has "L3b zero primitives never bare: scanned count and control on the line" "exec/network primitives: 0 hits in 0 of 4 files scanned"
has "L3c control OK on the clean run too" "control OK (9/9 planted primitives hit)"
hasnot "L3d no primitive table on a clean run" '| `subprocess`'
has "L3e non-commercial licence recognised" "| licence | CC-BY-NC-4.0 (LICENSE"
has "L3f hooks 0" "| hooks.json | 0 |"
has "L3g folded description measured" "name clean-skill · description 37 B · disable-model-invocation absent"
has "L3h not a repository, said plainly" "not a git repository"
has "L3i floor none" "floor: none"
has "L3j non-commercial signal" "signal: non-commercial licence (CC-BY-NC-4.0)"

# ================================================================== L4 fingerprint premise =======
run "$PY" "$FP" "$W/does-not-exist"
eq "L4a a missing directory is PROBE FAILED, exit 2" "$RC" "2"
has "L4b says so" "PROBE FAILED"
mkdir -p "$W/empty"
run "$PY" "$FP" "$W/empty"
eq "L4c an empty tree is PROBE FAILED, never clean" "$RC" "2"
has "L4d names the reason" "PROBE FAILED: no files under"

# ================================================================== L5 wrapper dry-run ===========
run "$PY" "$WR" --name planted-skill --upstream "$P" --level propose-first --description "$DESC" --skills-root "$ROOT"
eq "L5a dry-run exits 0" "$RC" "0"
has "L5b prints the wrapper with the gate paragraph" 'Use level `propose-first`'
has "L5c says it is a dry run" "dry-run: pass --write to apply"
[ ! -e "$ROOT/planted-skill" ] && ok "L5d dry-run created nothing" || no "L5d dry-run created $ROOT/planted-skill"

# ================================================================== L6 wrapper --write ===========
run "$PY" "$WR" --name planted-skill --upstream "$P" --level propose-first --description "$DESC" --skills-root "$ROOT" --write
eq "L6a --write exits 0" "$RC" "0"
[ -f "$ROOT/planted-skill/SKILL.md" ] && ok "L6b SKILL.md written" || no "L6b no SKILL.md"
[ -L "$ROOT/planted-skill/upstream" ] && ok "L6c upstream is a symlink" || no "L6c upstream is not a symlink"
UP=$("$PY" -c 'import os,sys; print(os.path.realpath(sys.argv[1]) == os.path.realpath(sys.argv[2]))' "$ROOT/planted-skill/upstream" "$P")
eq "L6d upstream resolves to the pinned directory" "$UP" "True"
grep -q '^name: planted-skill$' "$ROOT/planted-skill/SKILL.md" && ok "L6e frontmatter name" || no "L6e frontmatter name missing"
grep -q 'disable-model-invocation' "$ROOT/planted-skill/SKILL.md" && no "L6f propose-first carries no hidden field" || ok "L6f propose-first carries no hidden field"
grep -qF "wait for the owner's yes" "$ROOT/planted-skill/SKILL.md" && ok "L6g gate text on disk" || no "L6g gate text missing on disk"
grep -q '{{' "$ROOT/planted-skill/SKILL.md" && no "L6h placeholders filled" || ok "L6h placeholders filled"
S1=$(sha "$ROOT/planted-skill/SKILL.md")

# ================================================================== L7 wrapper idempotence =======
run "$PY" "$WR" --name planted-skill --upstream "$P" --level propose-first --description "$DESC" --skills-root "$ROOT" --write
eq "L7a a second identical --write exits 0" "$RC" "0"
has "L7b and reports unchanged" "unchanged:"
eq "L7c bytes untouched" "$(sha "$ROOT/planted-skill/SKILL.md")" "$S1"
run "$PY" "$WR" --name planted-skill --upstream "$P" --level propose-first --description "$DESC (v2)" --skills-root "$ROOT" --write
eq "L7d a differing --write without --force exits 1" "$RC" "1"
has "L7e and says why" "exists and differs"
eq "L7f bytes still untouched" "$(sha "$ROOT/planted-skill/SKILL.md")" "$S1"
run "$PY" "$WR" --name planted-skill --upstream "$P" --level propose-first --description "$DESC (v2)" --skills-root "$ROOT" --write --force
eq "L7g --force exits 0" "$RC" "0"
grep -qF "(v2)" "$ROOT/planted-skill/SKILL.md" && ok "L7h --force replaced the wrapper" || no "L7h --force did not replace"

# ================================================================== L8 wrapper by-name ===========
run "$PY" "$WR" --name clean-skill --upstream "$C" --level by-name --description "A clean skill wrapper, by name only." --skills-root "$ROOT" --write
eq "L8a by-name --write exits 0" "$RC" "0"
awk 'NR==1,/^---$/ && NR>1' "$ROOT/clean-skill/SKILL.md" | grep -q '^disable-model-invocation: true$' && ok "L8b hidden field in the frontmatter" || no "L8b hidden field missing"
grep -qF 'Use level `by-name`' "$ROOT/clean-skill/SKILL.md" && ok "L8c by-name gate text" || no "L8c by-name gate text missing"
[ -L "$ROOT/clean-skill/upstream" ] && ok "L8d upstream link" || no "L8d upstream link missing"

# ================================================================== L9 wrapper auto ==============
run "$PY" "$WR" --name auto-skill --upstream "$C" --level auto --skills-root "$ROOT" --write
eq "L9a auto --write exits 0" "$RC" "0"
[ -L "$ROOT/auto-skill" ] && ok "L9b auto is a symlink" || no "L9b auto is not a symlink"
AUP=$("$PY" -c 'import os,sys; print(os.path.realpath(sys.argv[1]) == os.path.realpath(sys.argv[2]))' "$ROOT/auto-skill" "$C")
eq "L9c symlink resolves to the upstream directory" "$AUP" "True"
run "$PY" "$WR" --name auto-skill --upstream "$C" --level auto --skills-root "$ROOT" --write
has "L9d second auto --write is unchanged" "unchanged:"
run "$PY" "$WR" --name auto-skill --upstream "$P" --level auto --skills-root "$ROOT" --write
eq "L9e re-pointing without --force exits 1" "$RC" "1"

# ================================================================== L10 wrapper refusals =========
run "$PY" "$WR" --name Bad_Name --upstream "$P" --level auto --skills-root "$ROOT" --write
eq "L10a a name outside [a-z0-9-] is PROBE FAILED" "$RC" "2"
run "$PY" "$WR" --name no-skill --upstream "$W/empty" --level auto --skills-root "$ROOT" --write
eq "L10b an upstream without SKILL.md is PROBE FAILED" "$RC" "2"
mkdir -p "$ROOT/busy" && printf 'keep\n' > "$ROOT/busy/notes.txt"
run "$PY" "$WR" --name busy --upstream "$C" --level propose-first --description d --skills-root "$ROOT" --write --force
eq "L10c a directory with other files is refused even under --force" "$RC" "2"
[ -f "$ROOT/busy/notes.txt" ] && ok "L10d and its file survives" || no "L10d the user's file was deleted"
run "$PY" "$WR" --name x-skill --upstream "$C" --level propose-first --skills-root "$ROOT" --write
eq "L10e a wrapper level without --description is PROBE FAILED" "$RC" "2"

# ================================================================== L11 register --seed ==========
run "$PY" "$RG" --register "$REG" --seed --date 2026-01-01
eq "L11a seed dry-run exits 0" "$RC" "0"
has "L11b prints the skeleton" "--- skeleton ---"
[ ! -e "$REG" ] && ok "L11c dry-run created nothing" || no "L11c dry-run created the register"
run "$PY" "$RG" --register "$REG" --seed --date 2026-01-01 --write
eq "L11d seed --write exits 0" "$RC" "0"
grep -q '^## User-level skills' "$REG" && grep -q '^## Plugins' "$REG" && ok "L11e skeleton carries the two headings the lint arm keys on" || no "L11e headings missing"
grep -q '^updated: 2026-01-01$' "$REG" && ok "L11f dates filled" || no "L11f dates not filled"
grep -q '{{' "$REG" && no "L11g no placeholder left" || ok "L11g no placeholder left"
grep -q '\[\[' "$REG" && no "L11h skeleton carries no wikilinks" || ok "L11h skeleton carries no wikilinks"
R0=$(sha "$REG")
run "$PY" "$RG" --register "$REG" --seed --write
eq "L11i seed on a present register exits 0" "$RC" "0"
has "L11j and says nothing to seed" "register present"
eq "L11k bytes untouched" "$(sha "$REG")" "$R0"

# ================================================================== L12 register --row ===========
ROW='planted-skill|propose-first (owner, '"$TODAY"')|wrapper + `upstream`|'"${PSHA:-abc1234}"' (v1.2.3) · example|listed; `/planted-skill` answers|fetch + checkout tag|'"${LB}planted-skill${RB}"''
run "$PY" "$RG" --register "$REG" --row "$ROW" --date "$TODAY"
eq "L12a --row dry-run exits 0" "$RC" "0"
has "L12b announces ADD" "ADD row"
eq "L12c dry-run wrote nothing" "$(sha "$REG")" "$R0"
run "$PY" "$RG" --register "$REG" --row "$ROW" --date "$TODAY" --write
eq "L12d --row --write exits 0" "$RC" "0"
eq "L12e exactly one row for the name" "$(grep -c -F '| `planted-skill` |' "$REG")" "1"
arm_rows "$REG" | grep -qx 'planted-skill' && ok "L12f the lint arm's own pipeline extracts the name" || no "L12f the lint arm does not see the row"
grep -q "^updated: $TODAY\$" "$REG" && ok "L12g updated: stamped" || no "L12g updated: not stamped"
eq "L12h no temp file left beside the register (atomic replace)" "$(ls -A "$W/wiki/developments" | wc -l | tr -d ' ')" "1"
grep -q '^| `planted-skill` |' "$REG" && awk '/^## User-level skills/{f=1} /^## Plugins/{exit} f && /^\| `planted-skill`/{found=1} END{exit !found}' "$REG" && ok "L12i row sits under the user-level heading, above Plugins" || no "L12i row misplaced"

# ================================================================== L13 register update/refusals =
ROW2='planted-skill|by-name (owner, '"$TODAY"')|wrapper + hidden field|'"${PSHA:-abc1234}"' (v1.2.3) · example|absent from the listing; `/planted-skill` answers|fetch + checkout tag|'"${LB}planted-skill${RB}"''
run "$PY" "$RG" --register "$REG" --row "$ROW2" --date "$TODAY" --write
eq "L13a a second --row for the name exits 0" "$RC" "0"
has "L13b and updates in place" "UPDATE (in place)"
eq "L13c still exactly one live row" "$(grep -c -F '| `planted-skill` |' "$REG")" "1"
grep -qF '| `planted-skill` | by-name (owner' "$REG" && ok "L13d the level cell changed" || no "L13d the level cell did not change"
run "$PY" "$RG" --register "$REG" --row 'six|auto|c|d|e|f' --write
eq "L13e six fields is PROBE FAILED" "$RC" "2"
run "$PY" "$RG" --register "$REG" --row 'seven|auto||d|e|f|g' --write
eq "L13f an empty field is PROBE FAILED" "$RC" "2"
run "$PY" "$RG" --register "$REG" --row 'seven|sometimes|c|d|e|f|g' --write
eq "L13g an unknown level is PROBE FAILED" "$RC" "2"
run "$PY" "$RG" --register "$REG" --row 'Bad Name|auto|c|d|e|f|g' --write
eq "L13h a bad name is PROBE FAILED" "$RC" "2"
eq "L13i refusals wrote no row" "$(grep -c -E '^\| `(six|seven)`' "$REG")" "0"

# ================================================================== L14 register --retire ========
R1=$(sha "$REG")
run "$PY" "$RG" --register "$REG" --retire planted-skill --date "$TODAY"
eq "L14a retire dry-run exits 0" "$RC" "0"
eq "L14b and writes nothing" "$(sha "$REG")" "$R1"
run "$PY" "$RG" --register "$REG" --retire planted-skill --date "$TODAY" --write
eq "L14c retire --write exits 0" "$RC" "0"
grep -qF '| ~~`planted-skill`~~ retired '"$TODAY"' | retired '"$TODAY"' (was by-name (owner' "$REG" && ok "L14d row kept, struck through with the date and its old level" || no "L14d retired row shape wrong"
arm_rows "$REG" | grep -qx 'planted-skill' && no "L14e the lint arm no longer counts a retired row" || ok "L14e the lint arm no longer counts a retired row"
run "$PY" "$RG" --register "$REG" --retire planted-skill --write
eq "L14f retiring twice is PROBE FAILED" "$RC" "2"
has "L14g and says it was already retired" "(already retired)"
run "$PY" "$RG" --register "$REG" --retire ghost-skill --write
eq "L14h retiring an unknown name is PROBE FAILED" "$RC" "2"
run "$PY" "$RG" --register "$REG" --row "$ROW" --date "$TODAY" --write
eq "L14i re-adopting after a retire adds a fresh live row" "$RC" "0"
eq "L14j one live row and one retired row for the name" "$(grep -c -E '^\| (~~)?`planted-skill`' "$REG")" "2"

# ================================================================== L15 register malformed =======
cp "$REG" "$W/dup.md"
grep -F '| `planted-skill` |' "$REG" >> "$W/dup.md.row"
awk -v row="$(cat "$W/dup.md.row")" '{print} /^\| `planted-skill` \|/{print row}' "$REG" > "$W/dup.md"
run "$PY" "$RG" --register "$W/dup.md" --row "$ROW" --write
eq "L15a two live rows for a name is PROBE FAILED" "$RC" "2"
has "L15b and names the malformation" "register malformed: 2 live rows"
run "$PY" "$RG" --register "$W/wiki/no-such.md" --row "$ROW" --write
eq "L15c a missing register is PROBE FAILED" "$RC" "2"
printf '# no table here\n' > "$W/notable.md"
run "$PY" "$RG" --register "$W/notable.md" --row "$ROW" --write
eq "L15d a register without the table is PROBE FAILED" "$RC" "2"

# ================================================================== L16 acceptance, clean ========
# planted-skill is propose-first on disk (L7h); its live row says propose-first again (L14i)
run "$PY" "$RG" --register "$REG" --row 'clean-skill|by-name (owner, '"$TODAY"')|wrapper + hidden field|(none) · example|absent from the listing; `/clean-skill` answers|pinned fixture: re-adopt to change|'"${LB}clean-skill${RB}"'' --date "$TODAY" --write
run "$PY" "$RG" --register "$REG" --row 'auto-skill|auto|symlink to the clone|(none) · example|listed|fetch + checkout tag|'"${LB}clean-skill${RB}"'' --date "$TODAY" --write
run "$PY" "$AC" --name planted-skill --register "$REG" --repo "$P" --exclude .github --raw "$W/raw-readme.md" --upstream-readme "$P/README.md" --skills-root "$ROOT"
eq "L16a all legs clean: exit 0" "$RC" "0"
has "L16b leg a: 0 references, with a live control through the same pattern" "0 references to .github in"
has "L16c leg a control hit a kept directory" 'control OK: `references/` (kept) referenced'
has "L16d leg b: row with every join field" "| b register row | ok | level propose-first"
has "L16e leg c: identical after the provenance frontmatter" "byte-identical after the provenance frontmatter"
has "L16f leg d: propose-first wrapper shape" "| d wrapper shape | ok | propose-first: name ok · gate text present · hidden field absent"
has "L16g leg e: baseline line with its negative control" "| e baseline | ok | \`planted-skill\` is a line of"
has "L16h summary line" "acceptance: 5 legs · 5 ok · 0 FAIL · 0 n/a"
run "$PY" "$AC" --name clean-skill --register "$REG" --raw "$W/raw-clean.md" --upstream-readme "$C/README.md" --skills-root "$ROOT"
eq "L16i by-name wrapper accepted" "$RC" "0"
has "L16j hidden field seen" "by-name: name ok · gate text present · hidden field present"
has "L16k byte-identical raw README" "| c raw README | ok | byte-identical ("
has "L16l legs without inputs read n/a, never ok" "| a excluded refs | n/a |"
run "$PY" "$AC" --name auto-skill --register "$REG" --skills-root "$ROOT"
eq "L16m auto symlink accepted" "$RC" "0"
has "L16n symlink resolved" "| d wrapper shape | ok | auto: symlink ->"

# ================================================================== L17 acceptance, one failure per leg
run "$PY" "$AC" --name planted-skill --register "$REG" --repo "$P" --exclude tests,.github --skills-root "$ROOT"
eq "L17a (a) a bare-name reference to an excluded directory fails" "$RC" "1"
has "L17b names the hit by bare name" '`tests/` 1 hit(s) in 1 file(s): README.md:4:'
has "L17c the control still reported" "control OK"
run "$PY" "$AC" --name ghost-skill --register "$REG" --skills-root "$ROOT"
eq "L17d (b) a missing row fails" "$RC" "1"
has "L17e says no live row" "no live row \`ghost-skill\`"
has "L17f (d) is not guessed without a level" "not checked: the level comes from the register row"
run "$PY" "$RG" --register "$REG" --row 'ph-skill|auto|directory|unrecorded|listed|none recorded|'"${LB}ph-skill${RB}"'' --date "$TODAY" --write
ln -s "$C" "$ROOT/ph-skill"
run "$PY" "$AC" --name ph-skill --register "$REG" --skills-root "$ROOT" --baseline "$ROOT/.sanctioned.txt"
eq "L17g (b) placeholder join fields fail" "$RC" "1"
has "L17h names the placeholder fields" "empty or placeholder join field(s): pin_publisher, bump"
run "$PY" "$AC" --name planted-skill --register "$REG" --raw "$W/raw-bad.md" --upstream-readme "$P/README.md" --skills-root "$ROOT"
eq "L17i (c) a one-byte difference fails" "$RC" "1"
has "L17j with the sizes and offset" "| c raw README | FAIL | differs: raw"
ROOT2="$W/root2"
cp -R "$ROOT" "$ROOT2"
sed -i.bak "s/then stop and wait for the owner's yes/then stop/" "$ROOT2/planted-skill/SKILL.md" && rm -f "$ROOT2/planted-skill/SKILL.md.bak"
run "$PY" "$AC" --name planted-skill --register "$REG" --skills-root "$ROOT2"
eq "L17k (d) a wrapper without the gate text fails" "$RC" "1"
has "L17l names the missing text" "gate text missing"
sed -i.bak '/^disable-model-invocation: true$/d' "$ROOT2/clean-skill/SKILL.md" && rm -f "$ROOT2/clean-skill/SKILL.md.bak"
run "$PY" "$AC" --name clean-skill --register "$REG" --skills-root "$ROOT2"
eq "L17m (d) a by-name wrapper without the hidden field fails" "$RC" "1"
has "L17n names the field" "disable-model-invocation: true missing on a by-name wrapper"
rm "$ROOT2/planted-skill/upstream" && ln -s "$W/nowhere" "$ROOT2/planted-skill/upstream"
run "$PY" "$AC" --name planted-skill --register "$REG" --skills-root "$ROOT2"
eq "L17o (d) a dangling upstream link fails" "$RC" "1"
has "L17p says the link does not resolve" "does not resolve"
rm "$ROOT2/auto-skill" && mkdir "$ROOT2/auto-skill" && cp "$C/SKILL.md" "$ROOT2/auto-skill/"
run "$PY" "$AC" --name auto-skill --register "$REG" --skills-root "$ROOT2"
eq "L17q (d) an auto row whose entry is a directory fails" "$RC" "1"
has "L17r expects a symlink" "auto expects a symlink"
run "$PY" "$AC" --name planted-skill --register "$REG" --skills-root "$ROOT" --baseline "$W/short.txt"
eq "L17s (e) a baseline without the name fails" "$RC" "1"
has "L17t says which file" "\`planted-skill\` is not in $W/short.txt"
run "$PY" "$AC" --name planted-skill --register "$REG" --skills-root "$ROOT" --baseline "$W/absent.txt"
eq "L17u (e) an absent baseline fails, never passes" "$RC" "1"
has "L17v names the fresh-machine case" "baseline absent"

# ================================================================== L18 acceptance premise =======
run "$PY" "$AC" --name planted-skill --register "$W/wiki/no-such.md" --skills-root "$ROOT"
eq "L18a a missing register is PROBE FAILED" "$RC" "2"
run "$PY" "$AC" --name planted-skill --register "$REG" --skills-root "$W/no-root"
eq "L18b a missing skills root is PROBE FAILED" "$RC" "2"

# ================================================================== L19 wrote nothing ============
RO="$W/ro"
mkdir -p "$RO/wiki/developments"
cp -R "$P" "$RO/planted"
cp -R "$C" "$RO/clean"
cp -R "$ROOT" "$RO/root"
cp "$REG" "$RO/wiki/developments/capability-register.md"
cp "$W/raw-readme.md" "$W/raw-bad.md" "$RO/"
chmod -R a-w "$RO"
manifest "$RO" > "$W/manifest-before.txt"
[ -s "$W/manifest-before.txt" ] || { no "L19 manifest empty (premise)"; }
RREG="$RO/wiki/developments/capability-register.md"
FAILS=""
run "$PY" "$FP" "$RO/planted";                      [ "$RC" = 0 ] || FAILS="$FAILS fp-planted($RC)"
run "$PY" "$FP" "$RO/planted" --json;               [ "$RC" = 0 ] || FAILS="$FAILS fp-json($RC)"
run "$PY" "$FP" "$RO/clean";                        [ "$RC" = 0 ] || FAILS="$FAILS fp-clean($RC)"
run "$PY" "$AC" --name planted-skill --register "$RREG" --repo "$RO/planted" --exclude .github --raw "$RO/raw-readme.md" --upstream-readme "$RO/planted/README.md" --skills-root "$RO/root"
[ "$RC" = 0 ] || FAILS="$FAILS ac-clean($RC)"
run "$PY" "$AC" --name planted-skill --register "$RREG" --repo "$RO/planted" --exclude tests --raw "$RO/raw-bad.md" --upstream-readme "$RO/planted/README.md" --skills-root "$RO/root"
[ "$RC" = 1 ] || FAILS="$FAILS ac-fail($RC)"
run "$PY" "$WR" --name new-skill --upstream "$RO/clean" --level propose-first --description d --skills-root "$RO/root"
[ "$RC" = 0 ] || FAILS="$FAILS wr-dry($RC)"
run "$PY" "$RG" --register "$RREG" --row 'new-skill|auto|symlink|p · q|listed|none: fixture|'"${LB}new-skill${RB}"''
[ "$RC" = 0 ] || FAILS="$FAILS rg-row-dry($RC)"
run "$PY" "$RG" --register "$RREG" --retire planted-skill
[ "$RC" = 0 ] || FAILS="$FAILS rg-retire-dry($RC)"
run "$PY" "$RG" --register "$RREG" --seed
[ "$RC" = 0 ] || FAILS="$FAILS rg-seed-present($RC)"
[ -z "$FAILS" ] && ok "L19a every read-only run exited as expected on a read-only tree" || no "L19a unexpected exits on the read-only tree:$FAILS"
manifest "$RO" > "$W/manifest-after.txt"
if cmp -s "$W/manifest-before.txt" "$W/manifest-after.txt"; then
	ok "L19b checksum manifest identical before and after ($(wc -l < "$W/manifest-before.txt" | tr -d ' ') manifest lines)"
else
	no "L19b the read-only runs changed the tree:"; diff "$W/manifest-before.txt" "$W/manifest-after.txt" | head -20
fi
WRITE_PAT='open\([^)]*["'"'"'][wa]|os\.replace|os\.rename|os\.symlink|os\.remove|os\.unlink|os\.mkdir|makedirs|shutil\.|mkstemp|NamedTemporaryFile|rmtree|os\.rmdir'
eq "L19c no write primitive in adopt_fingerprint.py" "$(grep -c -E "$WRITE_PAT" "$FP")" "0"
eq "L19d no write primitive in adopt_acceptance.py" "$(grep -c -E "$WRITE_PAT" "$AC")" "0"
[ "$(grep -c -E "$WRITE_PAT" "$WR")" -ge 1 ] && ok "L19e control: the same grep hits adopt_wrapper.py" || no "L19e control missed adopt_wrapper.py"
[ "$(grep -c -E "$WRITE_PAT" "$RG")" -ge 1 ] && ok "L19f control: the same grep hits adopt_register.py" || no "L19f control missed adopt_register.py"
grep -l -F '[[' "$HERE/templates/wrapper-propose-first.md" "$HERE/templates/wrapper-by-name.md" "$HERE/templates/register-skeleton.md" "$HERE/templates/owner-report.md" >/dev/null 2>&1 \
	&& no "L19g a template carries a wikilink" || ok "L19g templates carry no wikilinks"

# ================================================================== tally =============
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
	echo "$PASS/$TOTAL passed"
	exit 0
fi
echo "FAIL $FAIL/$TOTAL ($PASS/$TOTAL passed)"
exit 1
