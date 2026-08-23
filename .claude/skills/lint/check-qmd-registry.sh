#!/bin/sh
# Guard: wiki/log.md must never enter the qmd semantic index.
#
# Why: qmd keys embeddings on a file's whole-content hash, so every append re-embeds the entire
# timeline, and a hit on it invites an ~80k-token whole-file read via `qmd get`. The exclusion lives
# in ~/.config/qmd/index.yml — OUTSIDE the vault and outside both git repos — so it can vanish
# silently (it did once, 2026-07-21, when a folder rename left 0 files indexed). This asserts it.
#
# Dormant-safe: silent no-op wording when qmd is absent or disabled (CLAUDE.md §10).
# Never reports clean on a broken probe: an empty listing or a missing positive control is a FAILURE,
# not a pass (CLAUDE.md §11).
#
# Usage: sh .claude/skills/lint/check-qmd-registry.sh [vault-root] [collection]
#   exit 0 = clean or n/a · exit 1 = finding or broken probe
ROOT="${1:-.}"
COLL="${2:-wiki}"

command -v qmd >/dev/null 2>&1 || { echo "qmd-registry: n/a (qmd not installed)"; exit 0; }
[ -e "$ROOT/.qmd-off" ] && { echo "qmd-registry: n/a (qmd disabled by .qmd-off)"; exit 0; }

LIST=$(qmd ls "$COLL" 2>&1)
N=$(printf '%s\n' "$LIST" | grep -c "qmd://$COLL/")
if [ "$N" -eq 0 ]; then
  echo "qmd-registry: PROBE FAILED — 'qmd ls $COLL' listed no files (collection missing, renamed, or index empty)"
  exit 1
fi

# Positive control: index.md is deliberately KEPT in the index, so its absence means the probe
# or the config is broken, not that the vault is clean.
if ! printf '%s\n' "$LIST" | grep -q "qmd://$COLL/index\.md$"; then
  echo "qmd-registry: PROBE FAILED — control missing (index.md is not indexed; $N files listed)"
  exit 1
fi

if printf '%s\n' "$LIST" | grep -q "qmd://$COLL/log\.md$"; then
  echo "qmd-registry: FAIL — log.md is in the qmd index; restore 'ignore: [\"**/log.md\"]' on the $COLL collection in ~/.config/qmd/index.yml"
  exit 1
fi

echo "qmd-registry: ok — log.md excluded ($N files indexed; control: index.md present)"
exit 0
