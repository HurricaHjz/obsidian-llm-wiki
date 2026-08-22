#!/usr/bin/env bash
# test_export_template.sh — isolated, self-contained tests for export_template.sh.
# Builds a throwaway fake vault + fake git remote under $TMPDIR and exercises every mode.
# NEVER touches the real vault. Run:  bash test_export_template.sh
set -uo pipefail

REALSKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the real export-template skill (under test)
ROOT="${TMPDIR:-/tmp}/etest.$$"
V="$ROOT/vault"
REMOTE="$ROOT/remote.git"
CLONE="$ROOT/clone"
SCRIPT="$V/.claude/skills/export-template/export_template.sh"
GIT="git -c user.email=t@t -c user.name=test -c commit.gpgsign=false -c init.defaultBranch=main"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "    ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL   — $1"; }
chk(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1"; fi; }
hash_of(){ md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

build_fake_vault(){
  rm -rf "$ROOT"
  mkdir -p "$V/.claude/skills" "$V/.obsidian" "$V/wiki/sources" "$V/raw" "$V/assets" "$V/output"
  printf '# CLAUDE (test contract)\n' > "$V/CLAUDE.md"
  printf '# Manual (test)\n' > "$V/MANUAL.md"
  printf '# README (test)\n\n![graph](assets/framework_demo.png)\n\nSee the [Manual](MANUAL.md).\n\nLicence: [LICENSE](LICENSE.md)\n' > "$V/README.md"
  printf 'FAKE-PNG-BYTES\n' > "$V/assets/framework_demo.png"      # README screenshot — force-tracked
  printf 'LOCAL-USER-MEDIA\n' > "$V/assets/my_photo.png"          # user media — must NOT ship
  printf 'MIT License (test)\n' > "$V/LICENSE.md"
  printf '# Contributing (test — legacy leftover, must never ship)\n' > "$V/CONTRIBUTING.md"
  for f in app core-plugins appearance; do printf '{\n  "x": 1\n}\n' > "$V/.obsidian/$f.json"; done
  printf '{ "colorGroups": [ {"query":"path:wiki/models/","color":1} ], "showOrphans": true, "scale": 0.5, "close": true, "search": "q", "collapse-filter": true }\n' > "$V/.obsidian/graph.json"
  for s in ingest query lint oldskill output gather newskill; do  # 'newskill' tests dynamic discovery
    mkdir -p "$V/.claude/skills/$s"; printf '# %s skill\n' "$s" > "$V/.claude/skills/$s/SKILL.md"
  done
  cp -R "$REALSKILL" "$V/.claude/skills/export-template"
  # "knowledge" that must NEVER ship or be touched by pull
  printf '# secret note\npersonal data here\n' > "$V/wiki/sources/secret.md"
  printf 'raw source\n' > "$V/raw/source1.md"
  mkdir -p "$V/wiki/user"; printf -- '---\ntitle: "Customisation"\ntype: user\n---\nowner personal prefs\n' > "$V/CUSTOMISATION.md"  # personal config — must NEVER ship
  printf '# IDEAS\n- owner private idea\n' > "$V/IDEAS.md"   # personal scratchpad — must NEVER ship
  mkdir -p "$V/attic"; printf '# Attic Manifest\n- [2026-01-01] [[old-note]] retired\n' > "$V/attic/MANIFEST.md"  # cold storage — must NEVER ship
}

setup_published(){   # fake vault + bare remote + clone holding the published framework
  build_fake_vault
  $GIT init -q --bare "$REMOTE"
  $GIT clone -q "$REMOTE" "$CLONE" 2>/dev/null
  bash "$SCRIPT" --push "$CLONE" >/dev/null 2>&1
  ( cd "$CLONE" && $GIT add -A && $GIT commit -qm init && $GIT push -qu origin main ) >/dev/null 2>&1
}

[ -f "$REALSKILL/export_template.sh" ] || { echo "cannot find export_template.sh next to this test"; exit 2; }

echo "== Phase 1: fresh build =="
build_fake_vault
BUILT="$ROOT/built"
bash "$SCRIPT" "$BUILT" >/dev/null 2>&1
chk "build: README present"                 '[ -f "$BUILT/README.md" ]'
chk "build: README sourced from vault root" 'diff -q "$V/README.md" "$BUILT/README.md"'
chk "build: assets/ screenshot present"     '[ -f "$BUILT/assets/framework_demo.png" ]'
chk "build: LICENSE.md present"             '[ -f "$BUILT/LICENSE.md" ]'
chk "build: LICENSE.md sourced from root"   'diff -q "$V/LICENSE.md" "$BUILT/LICENSE.md"'
chk "build: no legacy no-ext LICENSE"       '[ ! -f "$BUILT/LICENSE" ]'
chk "build: CONTRIBUTING NOT shipped (retired)" '[ ! -f "$BUILT/CONTRIBUTING.md" ]'
chk "build: .gitignore present"             '[ -f "$BUILT/.gitignore" ]'
chk "build: setup.sh present + executable"  '[ -x "$BUILT/setup.sh" ]'
chk "build: 8 skills shipped (auto-discovered)" '[ "$(ls "$BUILT/.claude/skills" | wc -l | tr -d " ")" = 8 ]'
chk "build: NEW skill auto-shipped (dynamic)"   '[ -d "$BUILT/.claude/skills/newskill" ]'
chk "build: export-template IS shipped"     '[ -f "$BUILT/.claude/skills/export-template/export_template.sh" ]'
chk "build: export-template payload shipped" '[ -d "$BUILT/.claude/skills/export-template/payload/example" ]'
chk "build: no legacy docs/ folder"         '[ ! -d "$BUILT/docs" ]'
chk "build: user media NOT shipped"         '[ ! -f "$BUILT/assets/my_photo.png" ]'
chk "build: seed demo shipped"             '[ -d "$BUILT/examples/seed" ]'
chk "build: wiki ships empty"               '[ -z "$(find "$BUILT/wiki" -type f ! -name .gitkeep)" ]'
chk "build: raw ships empty"                '[ -z "$(find "$BUILT/raw" -type f ! -name .gitkeep)" ]'
chk "build: NO knowledge files shipped"     '[ ! -e "$BUILT/wiki/sources/secret.md" ] && [ ! -e "$BUILT/raw/source1.md" ]'
chk "build: personal Customisation NOT shipped" '[ ! -e "$BUILT/CUSTOMISATION.md" ]'
chk "build: shipped setup.sh seeds Customisation" 'grep -q mk_custom "$BUILT/setup.sh"'
chk "build: personal IDEAS.md NOT shipped"      '[ ! -e "$BUILT/IDEAS.md" ]'
chk "build: shipped setup.sh seeds IDEAS"       'grep -q mk_ideas "$BUILT/setup.sh"'
chk "build: publish allowlist ships with skill" '[ -f "$BUILT/.claude/skills/export-template/publish-allowlist.md" ]'
chk "build: attic contents NOT shipped"         '[ ! -e "$BUILT/attic/MANIFEST.md" ]'
chk "build: attic skeleton ships (.gitkeep)"    '[ -f "$BUILT/attic/.gitkeep" ]'
chk "build: shipped setup.sh seeds attic"       'grep -q mk_attic "$BUILT/setup.sh"'
chk "build: no __pycache__ shipped"         '[ -z "$(find "$BUILT" -name __pycache__)" ]'
chk "build: no .DS_Store shipped"           '[ -z "$(find "$BUILT" -name .DS_Store)" ]'
chk "build: graph.json keeps colorGroups"   'grep -q colorGroups "$BUILT/.obsidian/graph.json"'
chk "build: graph.json strips view-state"   '! grep -qE "scale|close|search|collapse-" "$BUILT/.obsidian/graph.json"'
( cd "$BUILT" && $GIT init -q && $GIT add -A ) >/dev/null 2>&1
chk "git: wiki content ignored"             '( cd "$BUILT" && git check-ignore -q wiki/sources/x.md )'
chk "git: raw content ignored"              '( cd "$BUILT" && git check-ignore -q raw/x.md )'
chk "git: output content ignored"           '( cd "$BUILT" && git check-ignore -q output/y.md )'
chk "git: attic content ignored"            '( cd "$BUILT" && git check-ignore -q attic/z.md )'
chk "git: README tracked"                   '( cd "$BUILT" && git ls-files | grep -qx README.md )'
chk "git: CLAUDE tracked"                   '( cd "$BUILT" && git ls-files | grep -qx CLAUDE.md )'
chk "git: screenshot force-tracked"         '( cd "$BUILT" && git ls-files | grep -q "assets/framework_demo.png" )'
chk "git: user media stays ignored"         '( cd "$BUILT" && cp "$V/assets/my_photo.png" assets/ 2>/dev/null; git check-ignore -q assets/my_photo.png )'
chk "git: .gitkeep tracked"                 '( cd "$BUILT" && git ls-files | grep -q ".gitkeep" )'

echo "== Phase 2: mutual exclusion (one direction per run) =="
build_fake_vault
out="$(bash "$SCRIPT" --pull "$ROOT/x" --push "$ROOT/y" 2>&1)"; rc=$?
chk "both directions → nonzero exit"        '[ "$rc" -ne 0 ]'
chk "both directions → clear error"         'echo "$out" | grep -qi "ONE direction"'

echo "== Phase 3: pull preview when in sync =="
setup_published
b_readme="$(hash_of "$V/README.md")"; b_claude="$(hash_of "$V/CLAUDE.md")"
out="$(bash "$SCRIPT" --pull "$CLONE" 2>&1)"
chk "preview: reports already matches"      'echo "$out" | grep -q "already matches"'
chk "preview: announces PREVIEW only"       'echo "$out" | grep -q "PREVIEW only"'
chk "preview: README NOT written"           '[ "$(hash_of "$V/README.md")" = "$b_readme" ]'
chk "preview: CLAUDE NOT written"           '[ "$(hash_of "$V/CLAUDE.md")" = "$b_claude" ]'

echo "== Phase 4: pull preview detects an upstream change, writes nothing =="
setup_published
printf '\nUPSTREAM EDIT\n' >> "$CLONE/README.md"
( cd "$CLONE" && $GIT commit -qam edit && $GIT push -q ) >/dev/null 2>&1
b_readme="$(hash_of "$V/README.md")"
out="$(bash "$SCRIPT" --pull "$CLONE" 2>&1)"
chk "preview: flags README update"          'echo "$out" | grep -qE "update +README"'
chk "preview: still writes nothing"         '[ "$(hash_of "$V/README.md")" = "$b_readme" ]'

echo "== Phase 5: pull --apply updates root docs + assets, pulls new skills, preserves export-template, spares knowledge =="
setup_published
printf '\nUPSTREAM EDIT v2\n' >> "$CLONE/README.md"
printf '# new contributing\n' > "$CLONE/CONTRIBUTING.md"   # legacy repo-side file — retired, must NOT flow home
printf 'NEW LICENSE v2\n' > "$CLONE/LICENSE.md"
mkdir -p "$CLONE/.claude/skills/repoonly"; printf '# repoonly\n' > "$CLONE/.claude/skills/repoonly/SKILL.md"   # exists only upstream
( cd "$CLONE" && $GIT add -A && $GIT commit -qam edit2 && $GIT push -q ) >/dev/null 2>&1
b_secret="$(hash_of "$V/wiki/sources/secret.md")"
bash "$SCRIPT" --pull "$CLONE" --apply >/dev/null 2>&1
chk "apply: README updated at root"         'grep -q "UPSTREAM EDIT v2" "$V/README.md"'
chk "apply: LICENSE.md updated at root"     'grep -q "NEW LICENSE v2" "$V/LICENSE.md"'
chk "apply: CONTRIBUTING NOT pulled (retired)" '! grep -q "new contributing" "$V/CONTRIBUTING.md"'
chk "apply: assets/ screenshot present"     '[ -f "$V/assets/framework_demo.png" ]'
chk "apply: repo-only skill pulled (dynamic)" '[ -d "$V/.claude/skills/repoonly" ]'
chk "apply: user media untouched"           '[ -f "$V/assets/my_photo.png" ]'
chk "apply: demo NOT pulled to vault root"  '[ ! -d "$V/examples" ]'
chk "apply: export-template PRESERVED"      '[ -f "$V/.claude/skills/export-template/export_template.sh" ]'
chk "apply: knowledge untouched"            '[ "$(hash_of "$V/wiki/sources/secret.md")" = "$b_secret" ]'
chk "apply: raw untouched"                  '[ -f "$V/raw/source1.md" ]'

echo "== Phase 6: bytecode / OS junk ignored in the pull diff =="
setup_published
mkdir -p "$V/.claude/skills/oldskill/__pycache__"; printf 'x' > "$V/.claude/skills/oldskill/__pycache__/m.pyc"
printf 'junk' > "$V/.claude/skills/gather/.DS_Store"
out="$(bash "$SCRIPT" --pull "$CLONE" 2>&1)"
chk "junk: oldskill NOT flagged"            '! echo "$out" | grep -q "oldskill"'
chk "junk: gather NOT flagged"              '! echo "$out" | grep -q "gather"'
chk "junk: overall already matches"         'echo "$out" | grep -q "already matches"'

echo "== Phase 7: --with-graph pulls graph.json only =="
setup_published
printf '{ "graph": "v2" }\n' > "$CLONE/.obsidian/graph.json"
printf '{ "app": "v2" }\n'   > "$CLONE/.obsidian/app.json"
( cd "$CLONE" && $GIT commit -qam obs && $GIT push -q ) >/dev/null 2>&1
b_app="$(hash_of "$V/.obsidian/app.json")"
bash "$SCRIPT" --pull "$CLONE" --with-graph --apply >/dev/null 2>&1
chk "graph: graph.json pulled"              'grep -q "v2" "$V/.obsidian/graph.json"'
chk "graph: app.json NOT pulled"            '[ "$(hash_of "$V/.obsidian/app.json")" = "$b_app" ]'

echo "== Phase 8: push → pull round-trip is clean (idempotent) =="
setup_published
out="$(bash "$SCRIPT" --pull "$CLONE" 2>&1)"
chk "roundtrip: no framework changes"       'echo "$out" | grep -q "already matches"'
bash "$SCRIPT" --push "$CLONE" >/dev/null 2>&1
( cd "$CLONE" && $GIT add -A ) >/dev/null 2>&1
chk "roundtrip: re-push yields no staged diff" '[ -z "$(cd "$CLONE" && git diff --cached --name-only)" ]'

echo "== Phase 9: README links resolve; none point to payload =="
build_fake_vault
BUILT="$ROOT/built2"
bash "$SCRIPT" "$BUILT" >/dev/null 2>&1
chk "links: no payload/ reference in README"   '! grep -q "payload/" "$BUILT/README.md"'
miss=0
while IFS= read -r tgt; do [ -e "$BUILT/$tgt" ] || { miss=1; echo "      missing target: $tgt"; }; done \
  < <(grep -oE '\]\([^)]+\)' "$BUILT/README.md" | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^https?://|^#|^mailto:')
chk "links: all relative README links resolve" '[ "$miss" = 0 ]'

echo "== Phase 10: pull self-updates export-template (running script replaced safely) =="
setup_published
printf '\n# UPSTREAM EXPORT-TEMPLATE MARKER\n' >> "$CLONE/.claude/skills/export-template/SKILL.md"
( cd "$CLONE" && $GIT add -A && $GIT commit -qam et && $GIT push -q ) >/dev/null 2>&1
bash "$SCRIPT" --pull "$CLONE" --apply >/dev/null 2>&1; rc=$?
chk "self-update: pull completed cleanly (exit 0)"      '[ "$rc" = 0 ]'
chk "self-update: vault export-template got the change" 'grep -q "UPSTREAM EXPORT-TEMPLATE MARKER" "$V/.claude/skills/export-template/SKILL.md"'
chk "self-update: export_template.sh still present"     '[ -f "$V/.claude/skills/export-template/export_template.sh" ]'

echo "== 13) the REAL vault README's images can actually ship =="
VAULT_ROOT="$(cd "$REALSKILL/../../.." && pwd)"
IMGS=$(grep -oE 'assets/[A-Za-z0-9._-]+\.(png|jpg|jpeg|gif|webp)' "$VAULT_ROOT/README.md" | sort -u)
chk "control: README references at least one assets/ image" '[ -n "$IMGS" ]'
for img in $IMGS; do
  chk "README image exists in vault: $img"            "[ -f \"$VAULT_ROOT/$img\" ]"
  chk "shipped .gitignore un-ignores it: $img"        "grep -qF '!/$img' \"$REALSKILL/payload/gitignore.txt\""
  chk "export copies it (readme_images matches): $img" "grep -oE 'assets/[A-Za-z0-9._-]+\\.(png|jpg|jpeg|gif|webp)' \"$VAULT_ROOT/README.md\" | grep -qx '$img'"
done

echo "== 14) shipped skills carry no wikilink to a page that does not ship =="
VROOT="$(cd "$REALSKILL/../../.." && pwd)"
DEADLINKS=$(python3 - "$VROOT" <<'PYEOF'
import os,glob,re,sys
v=sys.argv[1]
pages={os.path.splitext(os.path.basename(f))[0] for f in glob.glob(os.path.join(v,"wiki","**","*.md"),recursive=True)}
out=[]
for f in glob.glob(os.path.join(v,".claude","skills","*","SKILL.md")):
    for m in re.findall(r"\[\[([^\]]+)\]\]", open(f,encoding="utf-8").read()):
        if m.split("|")[0].split("#")[0].strip() in pages:
            out.append(os.path.basename(os.path.dirname(f))+":"+m)
print(" ".join(out))
PYEOF
)
chk "control: vault has wiki pages to link against" '[ -d "$VROOT/wiki" ]'
chk "no skill links to a non-shipping wiki page"    '[ -z "$DEADLINKS" ]'
[ -n "$DEADLINKS" ] && echo "      dead: $DEADLINKS"

echo "== 15) every shipped skill is documented in README + MANUAL =="
SKDIR15="$(cd "$REALSKILL/.." && pwd)"            # the real .claude/skills/
VROOT15="$(cd "$REALSKILL/../../.." && pwd)"      # the real vault root
SKILLS15=$(cd "$SKDIR15" && ls -d */ | tr -d '/')
chk "control: shipped skills enumerated"        "[ -n \"$SKILLS15\" ]"
MISS_R15=""; MISS_M15=""
for s in $SKILLS15; do
  grep -qF "| \`$s\` |" "$VROOT15/README.md" || MISS_R15="$MISS_R15 $s"
  grep -qF "\`$s\`"     "$VROOT15/MANUAL.md" || MISS_M15="$MISS_M15 $s"
done
chk "every shipped skill has a README skill-table row" "[ -z \"$MISS_R15\" ]"
chk "every shipped skill is named in MANUAL"           "[ -z \"$MISS_M15\" ]"
[ -n "$MISS_R15" ] && echo "      README missing:$MISS_R15"
[ -n "$MISS_M15" ] && echo "      MANUAL missing:$MISS_M15"
chk "control: probe fails on a fabricated skill" "! grep -qF '| \`no-such-skill\` |' \"$VROOT15/README.md\""

echo
echo "================  RESULT: $PASS passed, $FAIL failed  ================"
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
