#!/usr/bin/env bash
# export_template.sh — sync THIS LLM-Wiki framework with its public GitHub repo, ONE direction per run.
#
#   bash export_template.sh [OUT_DIR]               fresh build  (default OUT_DIR = <vault>/template-export)
#   bash export_template.sh --push <repo>           vault → repo : overlay framework + packaging into a clone
#   bash export_template.sh --pull <repo>           repo → vault : PREVIEW (git pull + diff; writes NOTHING)
#   bash export_template.sh --pull <repo> --apply   repo → vault : APPLY (CLAUDE/Manual/skills + README/LICENSE/CONTRIBUTING at root, screenshot in assets/, + payload)
#       add  --with-graph  to also pull .obsidian/graph.json (colour scheme); never app/appearance/core-plugins.
#   (--sync is kept as an alias for --push.)
#
# Exactly ONE direction per invocation — passing --pull AND --push together is an error.
# Read-only on the vault EXCEPT `--pull --apply`, which updates ONLY framework files + this skill's payload/,
# and NEVER your knowledge (wiki/ raw/ output/ + your own assets media) or your .obsidian runtime config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$SCRIPT_DIR/../../.." && pwd)"                 # vault root = 3 levels up
[ -f "$SRC/CLAUDE.md" ] || { echo "ERROR: $SRC has no CLAUDE.md — not a vault root"; exit 1; }
KIT="$SCRIPT_DIR/payload"   # the publish payload (build machinery: setup.sh, git dotfiles, seed demo) lives in this skill
[ -d "$KIT/example" ] || { echo "ERROR: skill payload missing at $KIT"; exit 1; }

DEMO_IMG="assets/framework_demo.png"   # the ONE framework asset shipped from assets/ (force-tracked); README screenshot

strip_junk() {   # drop regenerable cache / OS junk so it never ships or pollutes a pull diff
  for d in "$@"; do
    [ -e "$d" ] && find "$d" \( -name __pycache__ -o -name '*.pyc' -o -name .DS_Store \) -exec rm -rf {} + 2>/dev/null
  done
  return 0
}
strip_junk "$KIT"   # keep the payload mirror clean

list_skills() {  # echo EVERY skill folder under $1/.claude/skills — auto-discovery, so new skills ship/sync with zero edits.
  [ -d "$1/.claude/skills" ] || return 0   # export-template is included (it ships for contributors); see SKILL.md.
  for d in "$1/.claude/skills"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; d="${d##*/}"
    printf '%s\n' "$d"
  done
}

# ── vault-owned framework files: vault → $1  (build & push) ─────────────────────────────────
copy_framework() {
  local D="$1" s
  cp "$SRC/CLAUDE.md" "$SRC/Manual.md" "$D/"
  mkdir -p "$D/.claude/skills"
  for s in $(list_skills "$SRC"); do
    rm -rf "$D/.claude/skills/$s"; cp -R "$SRC/.claude/skills/$s" "$D/.claude/skills/"
  done
  mkdir -p "$D/.obsidian"
  for f in graph.json app.json core-plugins.json appearance.json; do
    [ -f "$SRC/.obsidian/$f" ] && cp "$SRC/.obsidian/$f" "$D/.obsidian/"
  done
  rm -rf "$D/examples/seed"; mkdir -p "$D/examples/seed"          # the demo (tracked, separate from wiki/raw)
  cp -R "$KIT/example/." "$D/examples/seed/"
  strip_junk "$D/.claude/skills" "$D/examples"                    # never ship __pycache__/*.pyc/.DS_Store
}

# ── publish-only packaging: vault root + payload → $1  (build & push) ────────────────────────
copy_packaging() {
  local D="$1" f
  for f in README.md LICENSE.md CONTRIBUTING.md; do                                 # canonical at the vault root
    [ -f "$SRC/$f" ] || { echo "ERROR: $SRC/$f missing — it is canonical at the vault root"; exit 1; }
    cp "$SRC/$f" "$D/$f"
  done
  rm -f "$D/LICENSE"; rm -rf "$D/docs"                                              # drop legacy no-ext LICENSE + old docs/ folder
  [ -f "$SRC/$DEMO_IMG" ] && { mkdir -p "$D/assets"; cp "$SRC/$DEMO_IMG" "$D/$DEMO_IMG"; }   # README screenshot (force-tracked)
  cp "$KIT/gitignore.txt"      "$D/.gitignore"
  cp "$KIT/gitattributes.txt"  "$D/.gitattributes"
  cp "$KIT/setup.sh"           "$D/setup.sh"; chmod +x "$D/setup.sh"
}

# ── empty content skeleton (.gitkeep) — NO content, NO index/log (those are gitignored) ─────
make_skeleton() {
  local D="$1"
  for d in 1-articles 2-papers 3-notes 4-webinfo 5-blogs 6-social 7-reviews 8-transcripts 9-originals archives duplicates; do
    mkdir -p "$D/raw/$d"; touch "$D/raw/$d/.gitkeep"; done
  for d in concepts entities tools models benchmarks sources syntheses maps user; do
    mkdir -p "$D/wiki/$d"; touch "$D/wiki/$d/.gitkeep"; done
  mkdir -p "$D/assets" "$D/output"; touch "$D/assets/.gitkeep" "$D/output/.gitkeep"
}

# ── tune the template's Obsidian config: keep the demo + build dirs out of the graph (idempotent) ──
apply_fixes() {
  local D="$1"
  python3 - "$D/.obsidian/app.json" <<'PY' || true
import json, sys
p = sys.argv[1]
try: d = json.load(open(p))
except Exception: sys.exit(0)
flt = d.get("userIgnoreFilters", [])
for x in ["examples/", "template-export/", "okf-export/"]:
    if x not in flt: flt.append(x)
d["userIgnoreFilters"] = flt
json.dump(d, open(p, "w"), indent=2)
PY
}

# ── pull publish files from the repo: README/LICENSE/CONTRIBUTING → vault root, screenshot → assets/, rest → payload ──
refresh_local() {
  local R="$1" f
  for f in README.md LICENSE.md CONTRIBUTING.md; do                                 # canonical at the vault root
    [ -f "$R/$f" ] && cp "$R/$f" "$SRC/$f"
  done
  [ -f "$R/$DEMO_IMG" ] && { mkdir -p "$SRC/assets"; cp "$R/$DEMO_IMG" "$SRC/$DEMO_IMG"; }
  for pair in ".gitignore:gitignore.txt" ".gitattributes:gitattributes.txt" "setup.sh:setup.sh"; do
    s="${pair%%:*}"; d="${pair##*:}"; [ -f "$R/$s" ] && cp "$R/$s" "$KIT/$d"
  done
  [ -d "$R/examples/seed" ] && { rm -rf "$KIT/example"; mkdir -p "$KIT/example"; cp -R "$R/examples/seed/." "$KIT/example/"; }
  strip_junk "$KIT"
}

# ── parse: pick exactly ONE direction ───────────────────────────────────────────────────────
WANT_PULL=0; WANT_PUSH=0; APPLY=0; WITH_GRAPH=0; REPO=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pull)        WANT_PULL=1; shift; REPO="${1:?--pull needs a path to your repo clone}"; shift;;
    --push|--sync) WANT_PUSH=1; shift; REPO="${1:?--push needs a path to your repo clone}"; shift;;
    --apply)       APPLY=1;      shift;;
    --with-graph)  WITH_GRAPH=1; shift;;
    *)             POS+=("$1");  shift;;
  esac
done
[ "$WANT_PULL" = 1 ] && [ "$WANT_PUSH" = 1 ] && { echo "ERROR: pick ONE direction — --pull OR --push, never both."; exit 1; }

# ── PULL mode (repo → vault) ────────────────────────────────────────────────────────────────
if [ "$WANT_PULL" = 1 ]; then
  REPO="$(cd "$REPO" && pwd)"
  [ -d "$REPO/.git" ]      || { echo "ERROR: $REPO is not a git clone"; exit 1; }
  [ -f "$REPO/CLAUDE.md" ] || { echo "ERROR: $REPO has no CLAUDE.md — not the framework repo"; exit 1; }
  echo "PULL ← $REPO   (your knowledge — wiki/ raw/ output/ + your assets media — and .obsidian config are never touched)"
  git -C "$REPO" pull --ff-only || { echo "ERROR: 'git pull' failed; resolve it in $REPO, then retry."; exit 1; }

  echo "--- framework changes pull would apply to your vault ---"
  CHG=0
  for f in CLAUDE.md Manual.md README.md LICENSE.md CONTRIBUTING.md; do
    diff -q "$REPO/$f" "$SRC/$f" >/dev/null 2>&1 || { echo "  update  $f"; CHG=1; }
  done
  if [ -f "$REPO/$DEMO_IMG" ]; then
    diff -q "$REPO/$DEMO_IMG" "$SRC/$DEMO_IMG" >/dev/null 2>&1 || { echo "  update  $DEMO_IMG"; CHG=1; }
  fi
  for s in $(list_skills "$REPO"); do
    diff -rq -x __pycache__ -x '*.pyc' -x .DS_Store "$REPO/.claude/skills/$s" "$SRC/.claude/skills/$s" >/dev/null 2>&1 || { echo "  update  .claude/skills/$s"; CHG=1; }
  done
  if [ "$WITH_GRAPH" = 1 ] && [ -f "$REPO/.obsidian/graph.json" ]; then
    diff -q "$REPO/.obsidian/graph.json" "$SRC/.obsidian/graph.json" >/dev/null 2>&1 || { echo "  update  .obsidian/graph.json"; CHG=1; }
  fi
  [ "$CHG" = 0 ] && echo "  (vault framework already matches the repo)"
  echo "  + payload refresh (setup.sh, .gitignore/.gitattributes, seed demo)"

  if [ "$APPLY" != 1 ]; then
    G=""; [ "$WITH_GRAPH" = 1 ] && G=" --with-graph"
    echo
    echo "PREVIEW only — nothing written. To apply, re-run with --apply:"
    echo "  bash .claude/skills/export-template/export_template.sh --pull \"$REPO\" --apply$G"
    exit 0
  fi

  cp "$REPO/CLAUDE.md" "$SRC/CLAUDE.md"
  cp "$REPO/Manual.md" "$SRC/Manual.md"
  for s in $(list_skills "$REPO"); do                    # per-name copy, incl. export-template itself —
    rm -rf "$SRC/.claude/skills/$s"; cp -R "$REPO/.claude/skills/$s" "$SRC/.claude/skills/"   # replacing the running script is Unix-safe (old inode stays open; new version applies next run)
  done
  [ "$WITH_GRAPH" = 1 ] && [ -f "$REPO/.obsidian/graph.json" ] && cp "$REPO/.obsidian/graph.json" "$SRC/.obsidian/graph.json"
  refresh_local "$REPO"
  echo "DONE — vault framework updated from $REPO. Re-read CLAUDE.md; reopen Obsidian if skills/graph changed."
  exit 0
fi

# ── PUSH mode (vault → repo) ────────────────────────────────────────────────────────────────
if [ "$WANT_PUSH" = 1 ]; then
  REPO="$(cd "$REPO" && pwd)"
  [ -d "$REPO/.git" ] || { echo "ERROR: $REPO is not a git clone"; exit 1; }
  echo "PUSH → overlaying framework + packaging into $REPO (knowledge never copied; .git untouched)"
  copy_framework "$REPO"
  copy_packaging "$REPO"     # publish files: README/LICENSE/CONTRIBUTING + screenshot from the vault; machinery from payload
  make_skeleton  "$REPO"     # idempotent (re-touches .gitkeep); creates the skeleton on a first publish
  apply_fixes    "$REPO"
  echo "DONE. Guided publish next: git -C \"$REPO\" pull --ff-only → add -A → diff → confirm → commit → push"
  exit 0
fi

# ── FRESH BUILD (standalone content-free copy) ──────────────────────────────────────────────
OUT="${POS[0]:-$SRC/template-export}"
echo "BUILD → $OUT"
rm -rf "$OUT"; mkdir -p "$OUT"
copy_framework "$OUT"
make_skeleton  "$OUT"
copy_packaging "$OUT"
apply_fixes    "$OUT"

# ── verify ───────────────────────────────────────────────────────────────────────────────
echo "--- shipped skills (auto-discovered, incl. export-template) ---"; ls "$OUT/.claude/skills" | tr '\n' ' '; echo
echo "--- wiki/raw ship empty (only .gitkeep)? ---"; find "$OUT/wiki" "$OUT/raw" -type f ! -name .gitkeep | sed 's/^/  STRAY: /' || true
echo "--- top-level ---"; ls -1A "$OUT"
echo "DONE → $OUT   (next: see .claude/skills/export-template/RUNBOOK.md → Publish)"
