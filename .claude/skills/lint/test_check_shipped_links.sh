#!/usr/bin/env bash
# test_check_shipped_links.sh — regression fixtures for check-shipped-links.py (lint Step 2g; the publish
# gate's test suite leg 14 calls the same script). Builds throwaway trees under $TMPDIR; NEVER touches the
# vault. Run:  bash test_check_shipped_links.sh   (exit 0 = all pass; each case names what it protects).
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-shipped-links.py"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "    ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL   — $1"; }
F="$(mktemp -d)"; trap 'rm -rf "$F"' EXIT
fresh(){ rm -rf "$F"; mkdir -p "$F/wiki/x" "$F/.claude/skills/t" "$F/.claude/agents" "$F/.claude/skills/x/payload/example/wiki"
  printf 'x\n' > "$F/wiki/x/Alpha.md"
  printf -- '---\ntitle: "Beta"\naliases: [Bee, "B two"]\n---\nx\n' > "$F/wiki/Beta.md"
  printf -- '---\naliases:\n  - Gam\n---\nx\n' > "$F/wiki/x/Gamma.md"; }
# expect <name> <exit> <finding-lines> <regex the first line must match>
expect(){ local name="$1" want_rc="$2" want_dead="$3" pat="$4" out rc first dead
  out="$(python3 "$S" "$F" 2>&1)"; rc=$?; first="${out%%$'\n'*}"; dead="$(printf '%s\n' "$out" | grep -c '→')"
  if [ "$rc" = "$want_rc" ] && [ "$dead" = "$want_dead" ] && printf '%s' "$first" | grep -Eq -- "$pat"; then ok "$name"
  else no "$name  [exit $rc, findings $dead: $first]"; fi; }
sk(){ printf '%s\n' "$1" > "$F/.claude/skills/t/SKILL.md"; }

fresh; sk 'see [[Alpha]] and [[Beta|b]] and [[Delta]]'; printf 'lane [[Alpha#h]]\n' > "$F/.claude/agents/a.md"
expect "planted links in a skill file and an agent definition are findings" 1 3 'dead'
fresh; sk $'```\n[[Alpha]]\n```\n`[[Beta]]` <!-- [[Alpha]] --> [[Nope]]'
expect "links inside fences, code spans and comments are not links" 0 0 '^shipped-links: clean'
fresh; printf '[[Alpha]]\n' > "$F/.claude/skills/x/payload/example/wiki/seed.md"; sk 't'
expect "vault-shaped content bundled in a skill is not a surface" 0 0 'clean.*0 wikilinks seen'
fresh; printf '[[Beta]]\n' > "$F/.claude/skills/t/templates.md"
expect "every skill Markdown file is in scope, not only SKILL.md" 1 1 'dead'
fresh; rm -rf "$F/wiki"; sk '[[Alpha]]'
expect "no wiki/ directory is a broken premise (wrong root), never clean" 2 0 'PROBE FAILED'
fresh; rm -f "$F/wiki/x/"*.md "$F/wiki/"*.md; sk '[[Alpha]]'
expect "an empty wiki/ (fresh install, the published copy) is n/a, exit 0" 0 0 '^shipped-links: n/a'
fresh; rm -rf "$F/.claude"
expect "no shipped surfaces is a broken premise" 2 0 'PROBE FAILED'
fresh; sk $'[[x/Alpha]] [[beta]] [[Alpha.md]] ![[Beta]]\n| rule | [[Alpha\\|the alpha page]] |'
expect "path-style, case, .md, embed and table-escaped-pipe forms all resolve" 1 5 'dead'
fresh; sk '[[Alphabet]] [[x]] [[Alpha 2]]'
expect "near-miss names are not findings" 0 0 'clean'
fresh; sk '[[Bee]] [[b two|x]] [[gam]]'
expect "inline and block-list frontmatter aliases resolve, any case" 1 3 'dead'
fresh; printf 'i\n' > "$F/wiki/index.md"; printf 'l\n' > "$F/wiki/log.md"; printf 's\n' > "$F/wiki/Seed.md"; printf 's\n' > "$F/.claude/skills/x/payload/example/wiki/Seed.md"; sk '[[index.md]] [[log]] [[seed]]'
expect "index, log and bundled example pages ship, so links to them are not findings" 0 0 'clean.*3 shipping names excluded'
fresh; sk '[[no-such-page]] [[Alpha]]'
expect "a link dead in both copies is counted on the control line, not flagged" 1 1 '1 targets resolving nowhere here'
fresh; printf 'bad \xff byte [[Alpha]]\n' > "$F/.claude/skills/t/SKILL.md"
expect "an undecodable shipped surface is a broken premise, not a finding" 2 0 'PROBE FAILED.*cannot read'
fresh; printf 'bad \xff byte\n' > "$F/wiki/x/Odd.md"; sk '[[Alpha]]'
expect "an undecodable wiki page is tolerated (aliases only)" 1 1 'dead'
fresh; printf 'x\n' > "$F/wiki/#odd|name].md"; sk '[[Alpha]]'
expect "the self-control does not depend on vault page names" 1 1 'dead'
fresh; printf -- '---\r\naliases: [Cee]\r\n---\r\nx\r\n' > "$F/wiki/Crlf.md"; sk '[[cee]]'
expect "CRLF frontmatter aliases resolve" 1 1 'dead'
fresh; sk 'x'; mv "$F/.claude/skills/t/SKILL.md" "$F/.claude/skills/t/SKILL.md.bak"; python3 "$S" /nonexistent >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "a nonexistent root is a broken premise" || no "a nonexistent root is a broken premise [exit $rc]"
echo "================  RESULT: $PASS passed, $FAIL failed  ================"
[ "$FAIL" -eq 0 ]
