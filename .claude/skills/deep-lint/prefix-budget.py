#!/usr/bin/env python3
"""Always-on prefix reconciliation measurement for deep-lint Step 1 (read-only).

Report-only by construction: this script prints to stdout and stderr and writes nothing.

It measures every always-on context layer — the bytes that ride into the model on every
request of every session — and prints the runbook's own line so the run records it verbatim:

  prefix budget: CLAUDE.md <N> B · skills <M> B (<name> <n> · ...) · agents <A> B (<name> <n> · ...)
  · customisation <K> B · MCP <k> declared · total ≈<T> tok/request

Layers and their conventions:
  - CLAUDE.md — whole file;
  - each `.claude/skills/*/SKILL.md` frontmatter block, per skill — the ever-loaded name and
    description block, measured from the first `---` line through the second, MARKERS INCLUDED
    (the markers are 8 B per file; measuring them inconsistently once produced a phantom
    uniform -8 B across eight skills that took a re-measurement to attribute);
  - each `.claude/agents/*.md` frontmatter block, per definition, the same convention — the
    harness surfaces every definition's name and description in every session's system prompt;
  - CUSTOMISATION.md — whole file (the schema imports it on every request);
  - project-declared MCP servers, reported as `k declared`, never a bare `k`: user-level servers
    load into the session too and this probe does not see them, so a bare count would overstate
    what was checked.

With --diff-log it finds the LAST `prefix budget:` line in the given log, parses its per-layer
and per-name figures, and prints each delta (new names, retired names, changed bytes). Deltas
only: attributing a delta to its cause is the agent's job, not the script's.

A missing layer SOURCE is a broken premise, not a zero: the layer prints PROBE FAILED and the run
exits 2 with every other layer still measured. The one exception is `.claude/agents/`, which a
fresh machine legitimately does not have: an absent directory reports `agents n/a (no directory)`
and the run continues at exit 0, the same `n/a` precedent the lint injection guard uses. An EMPTY
but present skills or agents directory is a real zero and reports as one, beside the number of
candidates inspected so the zero carries its scope.

Usage (from the vault root):
  python3 .claude/skills/deep-lint/prefix-budget.py
  python3 .claude/skills/deep-lint/prefix-budget.py --vault <root> --diff-log wiki/log.md

Exit codes: 0 = every layer measured or legitimately absent; 2 = a layer's premise failed.
"""

import argparse
import json
import os
import re
import sys

# Bytes per token, the standard rough English ratio used for the prefix line; a bound, not a
# decider — nothing here fires on the token figure.
BYTES_PER_TOKEN = 4
# The frontmatter block, matched only at the very START of the file and markers included. Anchoring
# it matters: a file with no frontmatter but two `---` rules in its body otherwise measures as a
# phantom always-on layer, and a stray README under .claude/agents/ then enters the budget line.
# CRLF is accepted, and a closing marker with no trailing newline ends the block at end of file.
FM_BYTES_RE = re.compile(rb"\A---[ \t]*\r?\n.*?\r?\n---[ \t]*(?:\r?\n|\Z)", re.S)
# A UTF-8 byte-order mark; it precedes the marker, so skip it before matching and never count it.
BOM_BYTES = b"\xef\xbb\xbf"


def frontmatter_bytes(path):
    """Bytes of the leading frontmatter block, markers included; -1 when the file has none."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data.startswith(BOM_BYTES):
        data = data[len(BOM_BYTES):]
    match = FM_BYTES_RE.match(data)
    return len(match.group(0)) if match else -1


def measure_dir(directory, pattern):
    """Measure each frontmatter block under a directory. Returns (rows, failures, candidates)."""
    rows, failures = [], []
    candidates = 0
    try:
        names = sorted(os.listdir(directory))
    except OSError as exc:
        return [], [f"{directory} could not be listed ({exc.__class__.__name__})"], 0
    for name in names:
        path, label = pattern(directory, name)
        if path is None:
            continue
        candidates += 1
        try:
            size = frontmatter_bytes(path)
        except OSError as exc:
            # A path that is not a readable file — a directory named `x.md`, a broken symlink, a
            # permission-denied file — is reported, never allowed to abort the whole measurement.
            failures.append(f"{label} ({path}) could not be read ({exc.__class__.__name__})")
            continue
        if size < 0:
            failures.append(f"{label} ({path}) does not begin with a frontmatter block")
            continue
        rows.append((label, size))
    return rows, failures, candidates


def skill_pattern(directory, name):
    path = os.path.join(directory, name, "SKILL.md")
    if os.path.isdir(os.path.join(directory, name)) and os.path.exists(path):
        return path, name
    return None, None


def agent_pattern(directory, name):
    if name.endswith(".md"):
        return os.path.join(directory, name), name[:-3]
    return None, None


def mcp_servers(root):
    """Project-declared MCP server names, with the files actually checked."""
    names, checked, failures = set(), [], []
    for rel, key in ((".mcp.json", "mcpServers"), (os.path.join(".claude", "settings.json"), "mcpServers")):
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            checked.append(f"{rel} absent")
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except (ValueError, OSError) as exc:
            failures.append(f"{rel} could not be parsed ({exc.__class__.__name__})")
            checked.append(f"{rel} unparseable")
            continue
        block = data.get(key) if isinstance(data, dict) else None
        found = sorted(block) if isinstance(block, dict) else []
        names.update(found)
        checked.append(f"{rel} present ({len(found)})")
    return sorted(names), checked, failures


def parse_pairs(blob):
    """Parse `name 123 · other 456` into a name -> bytes mapping."""
    out = {}
    for chunk in blob.split("·"):
        chunk = chunk.strip()
        if not chunk:
            continue
        parts = chunk.rsplit(None, 1)
        if len(parts) == 2 and parts[1].isdigit():
            out[parts[0].strip()] = int(parts[1])
    return out


def parse_previous(line):
    """Parse a previous `prefix budget:` line into its layers; missing layers stay None."""
    got = {"claude": None, "skills": None, "skill_rows": None, "agents": None,
           "agent_rows": None, "customisation": None, "mcp": None, "total": None}
    m = re.search(r"CLAUDE\.md\s+(\d+)\s*B", line)
    if m:
        got["claude"] = int(m.group(1))
    m = re.search(r"skills\s+(\d+)\s*B\s*\(([^)]*)\)", line)
    if m:
        got["skills"] = int(m.group(1))
        got["skill_rows"] = parse_pairs(m.group(2))
    m = re.search(r"agents\s+(\d+)\s*B\s*\(([^)]*)\)", line)
    if m:
        got["agents"] = int(m.group(1))
        got["agent_rows"] = parse_pairs(m.group(2))
    m = re.search(r"customisation\s+(\d+)\s*B", line)
    if m:
        got["customisation"] = int(m.group(1))
    m = re.search(r"MCP\s+(\d+)\s+declared", line)
    if m:
        got["mcp"] = int(m.group(1))
    m = re.search(r"total\s*[≈~]?\s*(\d+)\s*tok/request", line)
    if m:
        got["total"] = int(m.group(1))
    return got


def diff_layer(label, old, new, unit="B"):
    if new is None:
        return f"  {label}: n/a this run — the layer's source is absent, so it is not diffed"
    if old is None:
        return f"  {label}: no figure in the previous line — format baseline, cannot diff"
    delta = new - old
    sign = "+" if delta > 0 else ""
    state = "no change" if delta == 0 else f"{sign}{delta}"
    return f"  {label}: {old} -> {new} {unit} ({state})"


def diff_rows(kind, old_rows, new_rows):
    lines = []
    if new_rows is None:
        return [f"    {kind} per name: n/a this run — the layer's source is absent"]
    if old_rows is None:
        return [f"  {kind} per name: no figures in the previous line — format baseline, cannot diff"]
    for name in sorted(set(old_rows) | set(new_rows)):
        was, now = old_rows.get(name), new_rows.get(name)
        if was is None:
            lines.append(f"    new {kind}: {name} {now} B")
        elif now is None:
            lines.append(f"    retired {kind}: {name} (was {was} B)")
        elif was != now:
            delta = now - was
            lines.append(f"    {kind} {name}: {was} -> {now} B ({'+' if delta > 0 else ''}{delta})")
    if not lines:
        lines.append(f"    {kind} per name: no change")
    return lines


def main():
    parser = argparse.ArgumentParser(
        description="Deep-lint always-on prefix measurement (read-only; prints, never writes).")
    parser.add_argument("--vault", default=".", help="vault root (default: the current directory)")
    parser.add_argument("--diff-log", default=None,
                        help="log file to diff against (its last `prefix budget:` line)")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args()

    # A file name that is not valid UTF-8 arrives here as a surrogate; without this the first print
    # touching it aborts the whole report. Mangled beats missing, and it changes nothing otherwise.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")

    root = os.path.abspath(args.vault)
    failures = []

    claude_path = os.path.join(root, "CLAUDE.md")
    claude_bytes = 0
    if os.path.isfile(claude_path):
        claude_bytes = os.path.getsize(claude_path)
    else:
        failures.append("CLAUDE.md is absent")

    skills_dir = os.path.join(root, ".claude", "skills")
    skill_rows, skill_candidates = [], 0
    if os.path.isdir(skills_dir):
        skill_rows, skill_failures, skill_candidates = measure_dir(skills_dir, skill_pattern)
        failures.extend(skill_failures)
    else:
        failures.append(".claude/skills is absent or is not a directory")

    # `.claude/agents/` is the one optional layer: a fresh machine has no definitions yet, and that
    # is a legitimate vault state rather than a broken premise. Report it as `n/a`, keep every other
    # layer measured, and stay at exit 0 — the same `n/a` the lint injection guard prints when the
    # surface it checks does not exist. A present directory is measured exactly as before.
    agents_dir = os.path.join(root, ".claude", "agents")
    agent_rows, agent_candidates = [], 0
    agents_present = os.path.isdir(agents_dir)
    if agents_present:
        agent_rows, agent_failures, agent_candidates = measure_dir(agents_dir, agent_pattern)
        failures.extend(agent_failures)

    cust_path = os.path.join(root, "CUSTOMISATION.md")
    cust_bytes = 0
    if os.path.isfile(cust_path):
        cust_bytes = os.path.getsize(cust_path)
    else:
        failures.append("CUSTOMISATION.md is absent")

    servers, checked, mcp_failures = mcp_servers(root)
    failures.extend(mcp_failures)

    skills_bytes = sum(size for _, size in skill_rows)
    agents_bytes = sum(size for _, size in agent_rows) if agents_present else None
    total = claude_bytes + skills_bytes + (agents_bytes or 0) + cust_bytes
    tokens = total // BYTES_PER_TOKEN

    agents_clause = (f"agents {agents_bytes} B ({' · '.join(f'{n} {b}' for n, b in agent_rows)})"
                     if agents_present else "agents n/a (no directory)")
    budget_line = (
        f"prefix budget: CLAUDE.md {claude_bytes} B · "
        f"skills {skills_bytes} B ({' · '.join(f'{n} {b}' for n, b in skill_rows)}) · "
        f"{agents_clause} · "
        f"customisation {cust_bytes} B · MCP {len(servers)} declared · "
        f"total ≈{tokens} tok/request"
    )

    diff_lines = []
    previous_line = None
    if args.diff_log:
        log_path = args.diff_log if os.path.isabs(args.diff_log) else os.path.join(root, args.diff_log)
        if not os.path.exists(log_path):
            failures.append(f"--diff-log {args.diff_log} does not exist")
        else:
            for line in open(log_path, encoding="utf-8", errors="replace"):
                found = line.rfind("prefix budget:")
                if found >= 0:
                    # A log entry is one long line, so keep only the budget clause: parsing the
                    # whole line would let unrelated figures earlier in it match a layer regex.
                    previous_line = line[found:].strip()
            if previous_line is None:
                diff_lines.append(f"  no previous prefix budget line in {args.diff_log} — "
                                  f"this run is the baseline")
            else:
                old = parse_previous(previous_line)
                diff_lines.append(diff_layer("CLAUDE.md", old["claude"], claude_bytes))
                diff_lines.append(diff_layer("skills", old["skills"], skills_bytes))
                diff_lines.extend(diff_rows("skill", old["skill_rows"], dict(skill_rows)))
                diff_lines.append(diff_layer("agents", old["agents"], agents_bytes))
                diff_lines.extend(diff_rows("agent", old["agent_rows"],
                                            dict(agent_rows) if agents_present else None))
                diff_lines.append(diff_layer("customisation", old["customisation"], cust_bytes))
                diff_lines.append(diff_layer("MCP", old["mcp"], len(servers), unit="declared"))
                diff_lines.append(diff_layer("total", old["total"], tokens, unit="tok/request"))

    result = {
        "vault": root,
        "claude_md": claude_bytes,
        "skills": {"total": skills_bytes, "rows": dict(skill_rows), "count": len(skill_rows),
                   "candidates": skill_candidates},
        "agents": {"present": agents_present, "total": agents_bytes,
                   "rows": dict(agent_rows) if agents_present else None,
                   "count": len(agent_rows), "candidates": agent_candidates},
        "customisation": cust_bytes,
        "mcp": {"declared": len(servers), "names": servers, "checked": checked},
        "total_bytes": total,
        "tokens": tokens,
        "budget_line": budget_line,
        "previous_line": previous_line,
        "diff": diff_lines,
        "probe_failures": failures,
    }

    if args.format == "json":
        json.dump(result, sys.stdout, indent=1, sort_keys=True)
        sys.stdout.write("\n")
        for note in failures:
            print(f"PROBE FAILED: {note}", file=sys.stderr)
        return 2 if failures else 0

    agents_scope = (f"agents measured={len(agent_rows)} of {agent_candidates} candidates"
                    if agents_present else "agents n/a (no .claude/agents directory)")
    print(f"prefix-budget: vault={root} skills measured={len(skill_rows)} of {skill_candidates} "
          f"candidates {agents_scope} bytes/token={BYTES_PER_TOKEN}   "
          f"(the candidate counts are the scope a zero would be measured over)")
    print(f"mcp-probe: {' · '.join(checked)} — {len(servers)} declared"
          + (f" ({', '.join(servers)})" if servers else ""))
    print(budget_line)
    if args.diff_log:
        print(f"--- DIFF vs {args.diff_log} ---")
        if previous_line:
            print(f"  previous: {previous_line[:160]}")
        for line in diff_lines:
            print(line)
        if not diff_lines:
            print("  no delta computed — the log named above could not be read; see the probe "
                  "failure below")
    for note in failures:
        print(f"PROBE FAILED: {note}")
    return 2 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
