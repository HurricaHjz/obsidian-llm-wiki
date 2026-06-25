#!/usr/bin/env bash
# test_token_isolation.sh — verify the git/sync features add NO token cost to normal vault ops.
#
# Tokens are spent when a file is READ into the agent's context. The skill architecture loads a skill's
# body only when that skill is invoked; CLAUDE.md + every skill's frontmatter description load each session.
# So the git/sync engine (export_template.sh, SPEC/RUNBOOK, payload, the long SKILL body) must be reachable
# ONLY via an explicit /export-template — never referenced by CLAUDE.md or by the frequent everyday skills.
set -uo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"; cd "$VAULT"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "    ok   — $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL   — $1"; }

NORMAL="ingest query lint output gather"          # the frequent everyday ops
GITPAT='export_template|export-template|--push|--pull|--with-graph'

echo "== 1) frequent everyday skills never reference the git/sync features =="
for s in $NORMAL; do
  if grep -rEiq "$GITPAT" ".claude/skills/$s/" 2>/dev/null; then no "skill '$s' references git features"; else ok "skill '$s' free of git refs (loads no git content)"; fi
done

echo "== 2) CLAUDE.md (loaded every session) does not pull in the heavy git files =="
if grep -Eq 'export_template\.sh|export-template/(SPEC|RUNBOOK|payload|test_)' CLAUDE.md; then no "CLAUDE.md references heavy git files"; else ok "CLAUDE.md free of heavy git-file refs"; fi

echo "== 3) the sync engine lives ONLY under export-template/ =="
OUT=$(grep -rEl 'copy_packaging|refresh_local|copy_framework' .claude/skills 2>/dev/null | grep -vc 'export-template/')
if [ "$OUT" = 0 ]; then ok "sync engine confined to export-template/"; else no "sync engine leaks into $OUT file(s) outside export-template/"; fi

echo "== 4) log.md stays append-only in frequent ops (never whole-file read) =="
# positively detect a real READ of log.md (Read tool / bare cat / python .read); appends (cat >>),
# create/seed, existence checks and glob-excludes are all fine.
R=$(grep -rnE 'Read.{0,2}wiki/log\.md|cat +wiki/log\.md|open\([^)]*log\.md[^)]*\)\.read' .claude/skills/{ingest,query,lint,output,gather}/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$R" = 0 ]; then ok "no whole-file log.md read in frequent ops (append-only)"; else no "$R real log.md read(s) in frequent ops"; fi

echo "== 5) export-template's always-on description stays lean (<=160 words) =="
W=$(python3 -c "import re;t=open('.claude/skills/export-template/SKILL.md').read();m=re.search(r'^description:\s*(.*?)(?=^\w[\w-]*:\s|\n---)',t,re.S|re.M);print(len(m.group(1).split()) if m else 999)")
if [ "$W" -le 160 ]; then ok "export-template description lean ($W words, the only always-on git surface)"; else no "export-template description too long ($W words)"; fi

echo
echo "================  RESULT: $PASS passed, $FAIL failed  ================"
[ "$FAIL" -eq 0 ]
