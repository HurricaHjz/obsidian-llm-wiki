#!/usr/bin/env bash
# test_setup_customisation.sh — unit tests for setup.sh seeding the customisation layer.
# Runs the shipped payload/setup.sh in an isolated temp dir; NEVER touches the real vault.
# Run:  bash test_setup_customisation.sh
set -uo pipefail
PAY="$(cd "$(dirname "${BASH_SOURCE[0]}")/payload" && pwd)/setup.sh"
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${TMPDIR:-/tmp}/setuptest.$$"
CUST="CUSTOMISATION.md"
DEFS="CUSTOMISATION-definitions.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "    ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL   — $1"; }
hash_of(){ md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
fresh(){ rm -rf "$ROOT"; mkdir -p "$ROOT"; cp "$PAY" "$ROOT/setup.sh"; }   # isolated: setup.sh cd's to its own dir

[ -f "$PAY" ] || { echo "cannot find payload/setup.sh"; exit 2; }

echo "== 1) setup.sh parses =="
if bash -n "$PAY"; then ok "valid bash syntax"; else no "syntax error"; fi

echo "== 2) plain init seeds a valid Customisation =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 )
[ -f "$ROOT/$CUST" ]                          && ok "init creates $CUST"                  || no "init did not create $CUST"
grep -q '^- \*\*style\*\*: balanced' "$ROOT/$CUST" 2>/dev/null && ok "style knob seeded in ## Settings" || no "style knob missing from ## Settings"
grep -q '^## Settings' "$ROOT/$CUST" 2>/dev/null && ok "## Settings block present" || no "## Settings block missing"
sed -n '/^---$/,/^---$/p' "$ROOT/$CUST" | grep -qE '^(style|role|agent_name|language):' && no "knob still in frontmatter (import strips YAML)" || ok "no knob left in frontmatter"
grep -q '^### balanced'       "$ROOT/$CUST" 2>/dev/null && ok "default style defined in CORE" || no "default style has no ### section in core"
[ -f "$ROOT/$DEFS" ]                          && ok "init creates $DEFS (on-demand half)"  || no "init did not create $DEFS"
grep -q '^### detailed'       "$ROOT/$DEFS" 2>/dev/null && ok "detailed style in definitions file" || no "detailed style missing from $DEFS"
grep -q '^### summary'        "$ROOT/$DEFS" 2>/dev/null && ok "summary style in definitions file"  || no "summary style missing from $DEFS"
grep -q '^### brief'          "$ROOT/$DEFS" 2>/dev/null && ok "brief style in definitions file"    || no "brief style missing from $DEFS"
grep -q '^### detailed'       "$ROOT/$CUST" 2>/dev/null && no "detailed leaked into core (split broken)" || ok "core carries no non-default style (split holds)"
grep -q 'Definitions split'   "$ROOT/$CUST" 2>/dev/null && ok "Definitions-split rule seeded in core" || no "Definitions-split rule missing from core"
grep -q 'one canonical home per definition' "$ROOT/$CUST" 2>/dev/null && ok "block-move rule seeded" || no "block-move rule missing"
DUP=$(comm -12 <(grep '^### ' "$ROOT/$CUST" 2>/dev/null | sort) <(grep '^### ' "$ROOT/$DEFS" 2>/dev/null | sort))
[ -z "$DUP" ]                                 && ok "no ### heading duplicated across the pair" || no "duplicated heading(s): $DUP"
grep -q '\[\[About Me\]\]'    "$ROOT/$CUST" 2>/dev/null && ok "Related links [[About Me]] (no orphan)" || no "missing ## Related backlink"
grep -q '^- \*\*role\*\*: generalist' "$ROOT/$CUST" 2>/dev/null && ok "role knob seeded in ## Settings" || no "role knob missing from ## Settings"
grep -q '^## Roles'           "$ROOT/$CUST" 2>/dev/null && ok "Roles section present"                  || no "Roles section missing"
grep -q "^### generalist" "$ROOT/$CUST" 2>/dev/null && ok "role seeded in core: generalist (default)" || no "role missing from core: generalist"
for r in researcher engineer tutor examiner; do
  grep -q "^### $r" "$ROOT/$DEFS" 2>/dev/null && ok "role seeded in definitions: $r" || no "role missing from definitions: $r"
done
grep -q "^### researcher" "$ROOT/$CUST" 2>/dev/null && no "researcher leaked into core (split broken)" || ok "core carries no non-default role (split holds)"
grep -Eq '^- overrides[ :]' "$ROOT/$CUST" && no "retired override syntax still seeded" || ok "no marked-override lines (mechanism retired 2026-08-17)"
grep -q 'no role may change the active style' "$ROOT/$CUST" 2>/dev/null && ok "roles-never-change-style clause seeded" || no "clause missing"
grep -q 'offer the full report' "$ROOT/$DEFS" 2>/dev/null && ok "examiner compression-notice line seeded" || no "notice line missing"
grep -q 'status line'         "$ROOT/$CUST" 2>/dev/null && ok "status-line rule shipped"               || no "status-line rule missing"
grep -q "never the agent's internal reasoning" "$ROOT/$CUST" 2>/dev/null && ok "reasoning-invariance clause shipped" || no "reasoning-invariance clause missing"
grep -q 'how plainly it is put' "$ROOT/$CUST" 2>/dev/null && ok "plainness dimension seeded (two-dimension ladder, v0.8.8)" || no "plainness preamble missing"
grep -q '| depth | per request; ingest picks per source' "$ROOT/$CUST" 2>/dev/null && ok "depth axis row seeded (v0.8.8 vocabulary)" || no "depth axis row missing/stale"
grep -q '^### customised' "$ROOT/$CUST" 2>/dev/null && ok "customised span seeded (№56)" || no "customised span missing"
grep -q 'a claim, never a label' "$ROOT/$CUST" 2>/dev/null && ok "status-line claim rule seeded (№56)" || no "status-line claim rule missing"
T=$(( $(grep -c 'Test:' "$ROOT/$CUST" 2>/dev/null || echo 0) + $(grep -c 'Test:' "$ROOT/$DEFS" 2>/dev/null || echo 0) ))
[ "$T" -ge 6 ] && ok "per-style Test clauses seeded across the pair ($T lines)" || no "Test clauses missing ($T lines across pair, need >=6)"
RAW=$(python3 -c "
import re,sys
s=open('$ROOT/$CUST').read()
b=re.sub(r'\A---\n.*?\n---\n','',s,flags=re.S); b=re.sub(r'<!--.*?-->','',b,flags=re.S); b=re.sub(r'\`[^\`]*\`','',b)
print(len(re.findall(r'<[a-zA-Z][\w-]*>',b)))" 2>/dev/null || echo 99)
[ "$RAW" = 0 ]                                && ok "no raw HTML-parsed tokens in rendered prose"      || no "$RAW raw <tag> token(s) leak into rendered prose"
grep -q 'CUSTOMISATION-LOADED-v1'     "$ROOT/$CUST" 2>/dev/null && ok "load marker seeded"                  || no "load marker missing"
grep -q '^@CUSTOMISATION\.md' "$VAULT/CLAUDE.md" && ok "shipped CLAUDE.md imports the preference layer" || no "CLAUDE.md import line missing"
L=$(wc -l < "$ROOT/$CUST" | tr -d ' '); B=$(wc -c < "$ROOT/$CUST" | tr -d ' ')
# leanness guard only — the old ~10 KB bound encoded the hook-transport limit retired in v0.7.6; raised 2026-07-31 for the shipped Human-expert register default; raised 2026-08-14 for the four-style delivery ladder; raised 2026-08-22 for the №56 style-ceiling enforcement layer (claim + Test clauses + customised spans)
# raised 2026-08-23 for the fourth invariant (filed work is never restated) — vault↔template parity
if grep -q "Four invariants hold across the ladder" "$ROOT/CUSTOMISATION.md" && grep -q "filed work is never restated" "$ROOT/CUSTOMISATION.md"; then ok "fourth invariant (no-restatement) seeded"; else no "fourth invariant missing from seeded CUSTOMISATION"; fi
[ "$B" -le 16384 ]                            && ok "seeded core stays lean (${B} B / $L lines)"      || no "seeded core too heavy (${B} B / $L lines)"
DB=$(wc -c < "$ROOT/$DEFS" | tr -d ' ')
# defs bound: seed measures ~7.6 kB at the 2026-08-25 split; 12288 gives ~60% headroom
[ "$DB" -le 12288 ]                           && ok "seeded definitions file stays lean (${DB} B)"    || no "seeded definitions file too heavy (${DB} B)"

echo "== 2b) definitions half is idempotent too =="
printf '\nMY DEFS EDIT\n' >> "$ROOT/$DEFS"
B2=$(hash_of "$ROOT/$DEFS"); ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); A2=$(hash_of "$ROOT/$DEFS")
[ "$A2" = "$B2" ]                             && ok "re-run preserves definitions edits"   || no "re-run overwrote definitions file"

echo "== 3) re-run is idempotent (never overwrites user edits) =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); printf '\nMY EDIT\n' >> "$ROOT/$CUST"
B=$(hash_of "$ROOT/$CUST"); ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); A=$(hash_of "$ROOT/$CUST")
[ "$A" = "$B" ]                               && ok "re-run preserves user edits"          || no "re-run overwrote user edits"

echo "== 4) --reset preserves Customisation (user config) but blanks registries =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); printf '\nMY EDIT\n' >> "$ROOT/$CUST"
B=$(hash_of "$ROOT/$CUST"); ( cd "$ROOT" && bash setup.sh --reset >/dev/null 2>&1 ); A=$(hash_of "$ROOT/$CUST")
[ "$A" = "$B" ]                               && ok "--reset keeps Customisation"          || no "--reset clobbered Customisation"
[ -f "$ROOT/wiki/index.md" ] && [ -f "$ROOT/wiki/log.md" ] && ok "--reset re-creates registries" || no "--reset missing registries"

echo "== 5) --reset seeds Customisation when absent =="
fresh; ( cd "$ROOT" && bash setup.sh --reset >/dev/null 2>&1 )
[ -f "$ROOT/$CUST" ]                          && ok "--reset seeds if missing"             || no "--reset did not seed"
[ -f "$ROOT/$DEFS" ]                          && ok "--reset seeds definitions half too"   || no "--reset did not seed $DEFS"

echo "== 6) --with-example seeds Customisation =="
fresh; ( cd "$ROOT" && bash setup.sh --with-example >/dev/null 2>&1 )
[ -f "$ROOT/$CUST" ]                          && ok "--with-example seeds Customisation"   || no "--with-example did not seed"
[ -f "$ROOT/$DEFS" ]                          && ok "--with-example seeds definitions half" || no "--with-example did not seed $DEFS"

echo "== 7) mk_log seeds the full action list incl. deep-lint =="
fresh; ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 )
grep -q 'deep-lint' "$ROOT/wiki/log.md"       && ok "log.md action list includes deep-lint" || no "log.md missing deep-lint"

echo "== 8) IDEAS.md scratchpad seeded =="
[ -f "$ROOT/IDEAS.md" ]                                    && ok "init seeds IDEAS.md at vault root"      || no "IDEAS.md not seeded"
grep -q '^## 📋 Overview' "$ROOT/IDEAS.md" 2>/dev/null     && ok "Overview table section present"         || no "Overview section missing"
grep -q 'ignores this file in normal runs' "$ROOT/IDEAS.md" 2>/dev/null && ok "ignore-by-default rule stated" || no "ignore rule missing"
printf '\n- my idea\n' >> "$ROOT/IDEAS.md"
B=$(hash_of "$ROOT/IDEAS.md"); ( cd "$ROOT" && bash setup.sh >/dev/null 2>&1 ); A=$(hash_of "$ROOT/IDEAS.md")
[ "$A" = "$B" ]                                            && ok "re-run preserves owner's IDEAS edits"   || no "re-run overwrote IDEAS.md"

echo
echo "================  RESULT: $PASS passed, $FAIL failed  ================"
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
