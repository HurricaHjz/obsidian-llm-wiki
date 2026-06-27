#!/usr/bin/env python3
"""Ensure .obsidian/graph.json carries the framework's per-type colour palette.

Single source of truth for the graph colours: the canonical groups live in
`.claude/skills/lint/palette.json`. This script MERGES any missing framework groups into
`.obsidian/graph.json` -> colorGroups, preserving any custom groups the user added.
Idempotent: if every framework group is already present, it changes nothing.

Used by `setup.sh` (first-run), `ingest`'s first-run bootstrap, and the `lint` on-demand
graph-colour restore — all share this one definition. Read only on those paths, never on a
routine lint.

Usage (run from the vault root):
  python3 .claude/skills/lint/apply-palette.py --check   # report missing groups; exit 1 if any, else 0. No write.
  python3 .claude/skills/lint/apply-palette.py --apply   # add missing groups, write graph.json (default).
Optional final arg: vault root (defaults to the current directory).
"""
import json
import os
import sys

mode = "--apply"
root = "."
for a in sys.argv[1:]:
    if a in ("--check", "--apply"):
        mode = a
    else:
        root = a

palette_path = os.path.join(root, ".claude", "skills", "lint", "palette.json")
graph_path = os.path.join(root, ".obsidian", "graph.json")

try:
    with open(palette_path) as f:
        palette = json.load(f)
except Exception as e:  # noqa: BLE001 - report any read/parse failure plainly
    print(f"ERROR: cannot read palette {palette_path}: {e}")
    sys.exit(2)

try:
    with open(graph_path) as f:
        graph = json.load(f)
except FileNotFoundError:
    graph = {}
except Exception as e:  # noqa: BLE001
    print(f"ERROR: cannot parse {graph_path}: {e}")
    sys.exit(2)

groups = graph.get("colorGroups") or []
existing = {g.get("query") for g in groups}
missing = [g for g in palette if g.get("query") not in existing]

if mode == "--check":
    if missing:
        print("MISSING: " + ", ".join(g["query"] for g in missing))
        sys.exit(1)
    print("OK: all framework colour groups present")
    sys.exit(0)

# --apply (default)
if not missing:
    print("OK: palette already complete; no change")
    sys.exit(0)

groups.extend(missing)
graph["colorGroups"] = groups
with open(graph_path, "w") as f:
    json.dump(graph, f, indent=2)
print("APPLIED: added " + ", ".join(g["query"] for g in missing))
sys.exit(0)
