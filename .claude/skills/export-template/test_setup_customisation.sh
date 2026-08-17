#!/usr/bin/env bash
# test_setup_customisation.sh — unit tests for setup.sh seeding the customisation layer.
# Runs the shipped payload/setup.sh in an isolated temp dir; NEVER touches the real vault.
# Run:  bash test_setup_customisation.sh
set -uo pipefail
PAY="$(cd "$(dirname "${BASH_SOURCE[0]}")/payload" && pwd)/setup.sh"
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${TMPDIR:-/tmp}/setuptest.$$"
CUST="CUSTOMISATION.md"
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
grep -q '^### balanced'       "$ROOT/$CUST" 2>/dev/null && ok "default style defined in-file" || no "default style has no ### section"
grep -q '^### detailed'       "$ROOT/$CUST" 2>/dev/null && ok "detailed style present"     || no "detailed style missing"
grep -q '^### summary'        "$ROOT/$CUST" 2>/dev/null && ok "summary style present"      || no "summary style missing"
grep -q '^### brief'          "$ROOT/$CUST" 2>/dev/null && ok "brief style present"        || no "brief style missing"
grep -q '\[\[About Me\]\]'    "$ROOT/$CUST" 2>/dev/null && ok "Related links [[About Me]] (no orphan)" || no "missing ## Related backlink"
grep -q '^- \*\*role\*\*: generalist' "$ROOT/$CUST" 2>/dev/null && ok "role knob seeded in ## Settings" || no "role knob missing from ## Settings"
grep -q '^## Roles'           "$ROOT/$CUST" 2>/dev/null && ok "Roles section present"                  || no "Roles section missing"
for r in generalist researcher engineer tutor examiner; do
  grep -q "^### $r" "$ROOT/$CUST" 2>/dev/null && ok "role seeded: $r" || no "role missing: $r"
done
grep -Eq '^- overrides[ :]' "$ROOT/$CUST" && no "retired override syntax still seeded" || ok "no marked-override lines (mechanism retired 2026-08-17)"
grep -q 'no role may change the active style' "$ROOT/$CUST" 2>/dev/null && ok "roles-never-change-style clause seeded" || no "clause missing"
grep -q 'offer the full report' "$ROOT/$CUST" 2>/dev/null && ok "examiner compression-notice line seeded" || no "notice line missing"
grep -q 'status line'         "$ROOT/$CUST" 2>/dev/null && ok "status-line rule shipped"               || no "status-line rule missing"
grep -q "never the agent's internal reasoning" "$ROOT/$CUST" 2>/dev/null && ok "reasoning-invariance clause shipped" || no "reasoning-invariance clause missing"
RAW=$(python3 -c "
import re,sys
s=open('$ROOT/$CUST').read()
b=re.sub(r'\A---\n.*?\n---\n','',s,flags=re.S); b=re.sub(r'<!--.*?-->','',b,flags=re.S); b=re.sub(r'\`[^\`]*\`','',b)
print(len(re.findall(r'<[a-zA-Z][\w-]*>',b)))" 2>/dev/null || echo 99)
[ "$RAW" = 0 ]                                && ok "no raw HTML-parsed tokens in rendered prose"      || no "$RAW raw <tag> token(s) leak into rendered prose"
grep -q 'CUSTOMISATION-LOADED-v1'     "$ROOT/$CUST" 2>/dev/null && ok "load marker seeded"                  || no "load marker missing"
grep -q '^@CUSTOMISATION\.md' "$VAULT/CLAUDE.md" && ok "shipped CLAUDE.md imports the preference layer" || no "CLAUDE.md import line missing"
L=$(wc -l < "$ROOT/$CUST" | tr -d ' '); B=$(wc -c < "$ROOT/$CUST" | tr -d ' ')
# leanness guard only — the old ~10 KB bound encoded the hook-transport limit retired in v0.7.6; raised 2026-07-31 for the shipped Human-expert register default; raised 2026-08-14 for the four-style delivery ladder
[ "$B" -le 14336 ]                            && ok "seeded template stays lean (${B} B / $L lines)"      || no "seeded template too heavy (${B} B / $L lines)"

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

echo "== 6) --with-example seeds Customisation =="
fresh; ( cd "$ROOT" && bash setup.sh --with-example >/dev/null 2>&1 )
[ -f "$ROOT/$CUST" ]                          && ok "--with-example seeds Customisation"   || no "--with-example did not seed"

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
