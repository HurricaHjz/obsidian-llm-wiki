#!/usr/bin/env python3
"""fable-share.py — post-run metering and attribution for a delegated run.

The delegate skill's section 2a ("Metering and attribution") makes the metered figure the
close-out truth: lane-reported numbers are estimates. This script produces that figure from
the harness transcripts, reporting three head quantities and every lane's usage:

  - output — the head session's output tokens over the run's turns (the quantity the
    fable-minimising objective targets);
  - flow   — input + cache creation + cache read + output, the whole token flow;
  - peak   — the largest single call's context (input + cache creation + cache read).

Method (section 2a, transcript form): parse JSON records, never substring greps; dedupe
assistant records by message id keeping the FINAL usage record per id, because a step's
earlier records carry a placeholder output count; sum the four usage fields per model. The
model and effort mixes are counted over the same de-duplicated calls, so both sum to the
call count.

Read-only by construction: it opens files for reading, prints to stdout, and creates,
moves or deletes nothing anywhere. Diagnostics go to stderr.

Premise discipline: a figure is only ever printed when the probe demonstrably ran. Any
broken premise prints, exactly,

    fable share: unmetered (<reason>)

and exits 2 — in text and JSON mode alike, so a consumer checks the exit code before
parsing. Broken premises: the project directory or the session transcript is missing or
unreadable; a marker does not match; the window holds no assistant record; the window is
inverted; lane scanning finds no readable transcript at all; lane discovery finds a number
of lanes other than --expect-lanes; a flag cannot yield a meaningful figure (a negative
baseline, an expectation that cannot be checked). An unforeseen error is reported the same
way, with its traceback on stderr, so a crash can never masquerade as a metered run.

A malformed record never crashes the run and is never guessed at: a record whose message is
not an object, whose id is unusable, or whose usage carries a non-numeric value is counted
and reported rather than summed. A transcript torn by a write in progress reports its
unparseable line count, saying so when the final line is the torn one.

No threshold decides anything here: every number printed is measured from a transcript,
and the only presentation constant is the single decimal place on the share percentage.
Every default the script chooses (project directory, temporary root, lane mode, window
bounds, matching fallbacks) is printed in the header so a wrong derivation is visible.

Usage (from anywhere; nothing is assumed about the working directory):

  python3 fable-share.py --session <id> [--vault <root>] [--project-dir <path>]
      [--start <iso|marker>] [--end <iso|marker>] [--lanes auto|none|<glob>...]
      [--expect-lanes <n>] [--baseline-output <n>] [--tmp-root <path>]
      [--format text|json]

  --project-dir defaults to the harness's mapping of the vault's absolute path: every
  character outside A-Za-z0-9- becomes a hyphen, under ~/.claude/projects/. The mapping was
  checked against every project directory of a harness home, comparing each transcript's own
  cwd field with the directory holding it (6 of 6 matched, one path containing an @). Paths
  carrying spaces or non-ASCII characters were not among them, and a decomposed accent maps
  to two hyphens where a composed one maps to one, so a mismatch is possible there: when the
  derived directory or the session file inside it is missing, the failure names the sibling
  directory that does hold the session, and --project-dir overrides the derivation.
  --start and --end each take either an ISO timestamp or a text marker; a marker is
  matched against user-message text for --start (the invoking prompt) and assistant-message
  text for --end (the close-out reply), falling back to any record type and saying so. A
  marker matching more than once takes the first match and reports the others.
  --lanes auto searches both known homes for in-session lane transcripts, the durable
  <project-dir>/<session>/subagents/agent-*.jsonl and the volatile
  <tmp-root>/claude-*/<project-basename>/<session>/tasks/*.output (observed 2026-09-02),
  de-duplicated by content identity: the volatile entries are frequently symlinks to the
  durable files, and some are not transcripts at all. --lanes none meters the head alone and
  asserts no share. Scanning that reaches no readable transcript is a broken premise, since
  a zero lane total would otherwise be a claim with no control behind it; --expect-lanes 0
  is how a run with genuinely no lanes asserts that on purpose.
"""
import argparse
import glob
import json
import os
import re
import sys
import traceback
from datetime import datetime, timezone

USAGE_FIELDS = ("input_tokens", "cache_creation_input_tokens",
                "cache_read_input_tokens", "output_tokens")
ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}[T ]")
# A bound with headroom, not a decision threshold: the diagnostic scan of sibling project
# directories stops here. The harness home this was written against held 6 project
# directories (2026-09-02), so the cap leaves about two orders of magnitude of room.
SIBLING_SCAN_CAP = 500


def die(reason):
    """Print the broken-premise line and exit 2. Never a number on a broken premise."""
    print("fable share: unmetered (%s)" % reason)
    sys.exit(2)


def note(msg):
    print(msg, file=sys.stderr)


def derive_project_dir(vault):
    """The harness's project-directory mapping: non [A-Za-z0-9-] -> hyphen, under ~/.claude/projects."""
    slug = re.sub(r"[^A-Za-z0-9-]", "-", os.path.abspath(os.path.expanduser(vault)))
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", slug)


def sibling_hint(project_dir, session):
    """Diagnose a wrong derivation: name the sibling directory that does hold the session."""
    parent = os.path.dirname(os.path.abspath(project_dir))
    try:
        entries = sorted(os.listdir(parent))[:SIBLING_SCAN_CAP]
    except OSError:
        return ""
    hits = [os.path.join(parent, name) for name in entries
            if os.path.isfile(os.path.join(parent, name, session + ".jsonl"))]
    if len(hits) == 1:
        return " — %s holds that session; pass it as --project-dir" % hits[0]
    if len(hits) > 1:
        return " — %d sibling directories hold that session; pass one as --project-dir" % len(hits)
    return " — no sibling directory holds it either; check --session and --vault"


def parse_ts(value):
    if not value:
        return None
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        stamp = datetime.fromisoformat(text)
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return stamp


def message_text(rec):
    """Flatten a record's message content to plain text for marker matching."""
    msg = rec.get("message")
    if not isinstance(msg, dict):
        return ""
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and isinstance(block.get("text"), str):
                parts.append(block["text"])
        return " ".join(parts)
    return ""


def label(value):
    """A hashable, printable form of a record field that should be a string but may not be."""
    if value is None or isinstance(value, str):
        return value
    return repr(value)


def compact(rec, start_marker, end_marker):
    """Retain only what the meter needs, so a very large transcript stays bounded in memory."""
    kind = rec.get("type")
    row = {"type": kind, "ts": rec.get("ts_parsed"), "sm": False, "em": False,
           "sm_any": False, "em_any": False}
    if kind in ("user", "assistant"):
        text = message_text(rec)
        if start_marker and start_marker in text:
            row["sm_any"] = True
            row["sm"] = (kind == "user")
        if end_marker and end_marker in text:
            row["em_any"] = True
            row["em"] = (kind == "assistant")
    if kind == "assistant":
        msg = rec.get("message")
        if not isinstance(msg, dict):
            msg = {}                       # a message that is not an object carries no usage
        usage = msg.get("usage")
        row["mid"] = label(msg.get("id"))
        row["model"] = label(msg.get("model"))
        row["effort"] = label(rec.get("effort"))
        row["usage"] = None
        row["usage_bad"] = False
        row["usage_partial"] = False
        if isinstance(usage, dict):
            try:
                row["usage"] = tuple(int(usage.get(field) or 0) for field in USAGE_FIELDS)
            except (TypeError, ValueError):
                row["usage_bad"] = True    # a non-numeric usage field: count it, never guess it
            else:
                row["usage_partial"] = not all(field in usage for field in USAGE_FIELDS)
    return row


def read_transcript(path, start_marker=None, end_marker=None):
    """Stream a JSONL transcript into compact rows. Returns (rows, stats)."""
    rows = []
    stats = {"unparseable": 0, "tail_truncated": False}
    last_parsed = True
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip():
                continue
            rec = None
            try:
                rec = json.loads(line)
            except ValueError:
                rec = None
            if not isinstance(rec, dict):
                stats["unparseable"] += 1
                last_parsed = False
                continue
            last_parsed = True
            rec["ts_parsed"] = parse_ts(rec.get("timestamp"))
            rows.append(compact(rec, start_marker, end_marker))
    # A torn final line is the signature of a transcript read while it was being written.
    stats["tail_truncated"] = bool(stats["unparseable"]) and not last_parsed
    return rows, stats


def aggregate(rows):
    """Dedupe assistant rows by message id, keeping the final usage record per id, then sum."""
    final = {}
    raw = 0
    bad_usage = 0
    for index, row in enumerate(rows):
        if row.get("type") != "assistant":
            continue
        if row.get("usage_bad"):
            bad_usage += 1
            continue
        if not row.get("usage"):
            continue
        raw += 1
        key = row.get("mid") or "position-%d" % index   # no id: it can only count as its own call
        final[key] = row
    totals = {"calls": len(final), "records": raw, "output": 0, "flow": 0, "peak": 0,
              "models": {}, "efforts": {}, "bad_usage": bad_usage, "partial_usage": 0}
    for row in final.values():
        inp, cache_write, cache_read, out = row["usage"]
        totals["output"] += out
        totals["flow"] += inp + cache_write + cache_read + out
        totals["peak"] = max(totals["peak"], inp + cache_write + cache_read)
        model = row.get("model") or "unknown"
        totals["models"][model] = totals["models"].get(model, 0) + 1
        effort = row.get("effort")
        if effort is not None:
            totals["efforts"][effort] = totals["efforts"].get(effort, 0) + 1
        if row.get("usage_partial"):
            totals["partial_usage"] += 1
    return totals


def fmt_models(models):
    if not models:
        return "none"
    return ", ".join("%s:%d" % (name, count) for name, count in sorted(models.items()))


def plural(count, word):
    return "%d %s%s" % (count, word, "" if count == 1 else "s")


def data_clause(totals):
    """The malformed-record clause, printed only when there is something to report."""
    parts = []
    if totals["bad_usage"]:
        parts.append("%s with unusable usage skipped" % plural(totals["bad_usage"], "assistant record"))
    if totals["partial_usage"]:
        parts.append("%s missing a usage field (counted as 0)" % plural(totals["partial_usage"], "call"))
    return " · ".join(parts)


def resolve_window(rows, start, end):
    """Locate the run's records. Returns (start_index, end_index, notes)."""
    notes = {}
    last = len(rows) - 1
    if start is None:
        si, notes["start"] = 0, "first record (no --start given)"
        notes["start_matches"] = 0
    elif ISO_RE.match(start):
        bound = parse_ts(start)
        if bound is None:
            die("start reads as a timestamp but will not parse (a marker beginning with a date "
                "is read as a timestamp): %s" % start)
        si = next((i for i, r in enumerate(rows) if r["ts"] and r["ts"] >= bound), None)
        if si is None:
            die("no record at or after the start timestamp: %s" % start)
        notes["start"] = "first record at or after %s" % start
        notes["start_matches"] = 0
    else:
        hits = [i for i, r in enumerate(rows) if r["sm"]]
        if hits:
            si = hits[0]
            notes["start"] = 'marker "%s" in a user message' % start
        else:
            hits = [i for i, r in enumerate(rows) if r["sm_any"]]
            if not hits:
                die("start marker not found: %s" % start)
            si = hits[0]
            notes["start"] = 'marker "%s" (matched on any record type, not a user message)' % start
        notes["start_matches"] = len(hits)
        if len(hits) > 1:
            # An over-broad marker silently shifting the window is the failure this names.
            notes["start"] += " · %s later, first taken" % plural(len(hits) - 1, "further match")

    if end is None:
        ei, notes["end"] = last, "last record (no --end given)"
        notes["end_matches"] = 0
    elif ISO_RE.match(end):
        bound = parse_ts(end)
        if bound is None:
            die("end reads as a timestamp but will not parse (a marker beginning with a date "
                "is read as a timestamp): %s" % end)
        ei = next((i for i in range(last, -1, -1) if rows[i]["ts"] and rows[i]["ts"] <= bound), None)
        if ei is None:
            die("no record at or before the end timestamp: %s" % end)
        notes["end"] = "last record at or before %s" % end
        notes["end_matches"] = 0
    else:
        hits = [i for i in range(si + 1, len(rows)) if rows[i]["em"]]
        kind = "in an assistant reply"
        if not hits:
            hits = [i for i in range(si + 1, len(rows)) if rows[i]["em_any"]]
            kind = "(matched on any record type, not an assistant reply)"
        if not hits:
            earlier = sum(1 for i in range(0, si + 1) if rows[i]["em_any"])
            if earlier:
                die('end marker matches only at or before the start bound (%s): %s'
                    % (plural(earlier, "earlier match"), end))
            die("end marker not found: %s" % end)
        ei = hits[0]
        notes["end"] = 'marker "%s" %s' % (end, kind)
        notes["end_matches"] = len(hits)
        if len(hits) > 1:
            notes["end"] += " · %s later, first taken" % plural(len(hits) - 1, "further match")

    if ei < si:
        die("the end bound precedes the start bound")
    return si, ei, notes


def window_bounds(rows, si, ei):
    """The window's wall-clock edges, used to select each lane's own records."""
    first = next((rows[i]["ts"] for i in range(si, ei + 1) if rows[i]["ts"]), None)
    lastc = next((rows[i]["ts"] for i in range(ei, si - 1, -1) if rows[i]["ts"]), None)
    return first, lastc


def lane_patterns(mode, patterns, project_dir, session, tmp_root):
    """The globs a lane scan will search — printed in a failure so the probe stays auditable."""
    if mode == "auto":
        return [os.path.join(project_dir, session, "subagents", "agent-*.jsonl"),
                os.path.join(tmp_root, "claude-*", os.path.basename(project_dir),
                             session, "tasks", "*.output")]
    return [os.path.expanduser(pattern) for pattern in patterns]


def discover_lanes(mode, patterns, project_dir, session, tmp_root):
    """Both known lane homes, de-duplicated by content identity. Returns (paths, scan_counts)."""
    durable, volatile = [], []
    if mode == "auto":
        durable = sorted(glob.glob(os.path.join(project_dir, session, "subagents", "agent-*.jsonl")))
        volatile = sorted(glob.glob(os.path.join(
            tmp_root, "claude-*", os.path.basename(project_dir), session, "tasks", "*.output")))
        candidates = durable + volatile
    else:
        candidates = []
        for pattern in patterns:
            candidates.extend(sorted(glob.glob(os.path.expanduser(pattern))))
    unique, seen, skipped = [], set(), 0
    for path in candidates:
        # isfile() is False for a directory, a dangling link and a symlink loop alike, and
        # raises for none of them; each is a candidate that cannot be a transcript.
        if not os.path.isfile(path):
            skipped += 1
            continue
        try:
            key = os.path.realpath(path)
        except OSError:
            skipped += 1
            continue
        if key in seen:
            continue
        seen.add(key)
        unique.append(path)
    return unique, {"durable": len(durable), "volatile": len(volatile),
                    "candidates": len(candidates), "unique": len(unique),
                    "skipped": skipped, "identity_duplicates": 0, "no_window_records": 0}


def lane_identity(path):
    """A lane's content id: its own agent id where the transcript carries one, else the file stem."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict) and rec.get("agentId"):
                    return str(rec["agentId"])
    except OSError:
        return None
    stem = os.path.basename(path)
    for suffix in (".jsonl", ".output"):
        if stem.endswith(suffix):
            stem = stem[:-len(suffix)]
    if stem.startswith("agent-"):
        stem = stem[len("agent-"):]
    return stem


def scan_clause(scan):
    """The lane-scan control, with each silently-dropped candidate class named."""
    text = ("control: %s scanned (%d durable, %d volatile, %d unique after de-duplication)"
            % (plural(scan["candidates"], "candidate transcript"),
               scan["durable"], scan["volatile"], scan["unique"]))
    if scan["skipped"]:
        text += " · %d skipped (not a regular file)" % scan["skipped"]
    if scan["identity_duplicates"]:
        text += " · %d dropped as a duplicate identity" % scan["identity_duplicates"]
    if scan["no_window_records"]:
        text += " · %d with no records in the window" % scan["no_window_records"]
    return text


def main():
    ap = argparse.ArgumentParser(add_help=True, description="Meter a delegated run's head and lane usage.")
    ap.add_argument("--session", required=True, help="head session id (the transcript stem)")
    ap.add_argument("--vault", default=".", help="vault root; the project directory is derived from it")
    ap.add_argument("--project-dir", default=None, help="override the derived project directory")
    ap.add_argument("--start", default=None, help="ISO timestamp or a text marker in the invoking user message")
    ap.add_argument("--end", default=None, help="ISO timestamp or a text marker in the close-out reply")
    ap.add_argument("--lanes", nargs="+", default=["auto"], help="auto | none | one or more transcript globs")
    ap.add_argument("--expect-lanes", type=int, default=None, help="fail the premise unless exactly this many lanes are found")
    ap.add_argument("--baseline-output", type=int, default=None, help="prior head output, for the delta line")
    # The volatile lane home lives under the system temporary directory; resolving /tmp keeps
    # the default right on a platform that symlinks it, without a platform literal in source.
    ap.add_argument("--tmp-root", default=os.path.realpath("/tmp"), help="root of the volatile lane home")
    ap.add_argument("--format", choices=("text", "json"), default="text", help="output format")
    args = ap.parse_args()

    if args.expect_lanes is not None and args.expect_lanes < 0:
        die("--expect-lanes cannot be negative: %d" % args.expect_lanes)
    if args.baseline_output is not None and args.baseline_output < 0:
        die("--baseline-output cannot be negative: %d" % args.baseline_output)

    session = args.session.strip()
    if session.endswith(".jsonl"):
        session = session[:-len(".jsonl")]          # the transcript's file name is a fair thing to paste
    separators = [sep for sep in (os.sep, os.altsep) if sep]
    if not session or session in (".", "..") or any(sep in session for sep in separators):
        die("session must be a bare session id, not a path: %s" % args.session)

    project_dir = args.project_dir or derive_project_dir(args.vault)
    derivation = "given" if args.project_dir else "derived from vault %s" % os.path.abspath(os.path.expanduser(args.vault))
    if not os.path.isdir(project_dir):
        die("project directory not found (%s): %s%s"
            % (derivation, project_dir, sibling_hint(project_dir, session)))
    session_path = os.path.join(project_dir, session + ".jsonl")
    if not os.path.isfile(session_path):
        die("session transcript not found: %s%s" % (session_path, sibling_hint(project_dir, session)))
    try:
        rows, stats = read_transcript(session_path, args.start, args.end)
    except OSError as exc:
        die("session transcript unreadable: %s" % exc)
    if not rows:
        die("session transcript holds no parseable records: %s (%d unparseable line(s))"
            % (session_path, stats["unparseable"]))

    si, ei, notes = resolve_window(rows, args.start, args.end)
    head = aggregate(rows[si:ei + 1])
    if head["calls"] == 0:
        die("no assistant records with usage in the window (records %d..%d%s)"
            % (si, ei, "" if not head["bad_usage"]
               else "; %s had unusable usage" % plural(head["bad_usage"], "record")))
    win_start, win_end = window_bounds(rows, si, ei)

    mode = "auto"
    patterns = []
    if len(args.lanes) == 1 and args.lanes[0] in ("auto", "none"):
        mode = args.lanes[0]
    else:
        mode, patterns = "globs", args.lanes

    lanes = []
    scan = {"durable": 0, "volatile": 0, "candidates": 0, "unique": 0,
            "skipped": 0, "identity_duplicates": 0, "no_window_records": 0}
    lane_totals = {"output": 0, "flow": 0, "calls": 0, "models": {}}
    if mode == "none":
        if args.expect_lanes is not None:
            die("--expect-lanes %d cannot be checked with --lanes none" % args.expect_lanes)
    else:
        if win_start is None or win_end is None:
            die("the window carries no timestamps, so lane records cannot be selected")
        searched = lane_patterns(mode, patterns, project_dir, session, args.tmp_root)
        paths, scan = discover_lanes(mode, patterns, project_dir, session, args.tmp_root)
        if scan["unique"] == 0 and args.expect_lanes != 0:
            # A zero lane total off a scan that reached nothing would be a claim with no
            # control behind it, so it is a broken premise rather than a share of 100%.
            die("no readable lane transcript found (%d candidate(s), %d skipped) under: %s "
                "— use --lanes none to meter the head alone, or --expect-lanes 0 to assert there were none"
                % (scan["candidates"], scan["skipped"], " ".join(searched)))
        seen_ids = set()
        for path in paths:
            ident = lane_identity(path)
            if ident and ident in seen_ids:
                scan["identity_duplicates"] += 1
                continue
            if ident:
                seen_ids.add(ident)
            try:
                lane_rows, lane_stats = read_transcript(path)
            except OSError as exc:
                note("skipped unreadable lane transcript %s (%s)" % (path, exc))
                scan["skipped"] += 1
                continue
            in_window = [r for r in lane_rows if r["ts"] and win_start <= r["ts"] <= win_end]
            totals = aggregate(in_window)
            if totals["calls"] == 0:
                scan["no_window_records"] += 1
                continue
            totals["name"] = ident or os.path.basename(path)
            totals["path"] = path
            totals["unparseable"] = lane_stats["unparseable"]
            totals["tail_truncated"] = lane_stats["tail_truncated"]
            lanes.append(totals)
            lane_totals["output"] += totals["output"]
            lane_totals["flow"] += totals["flow"]
            lane_totals["calls"] += totals["calls"]
            for model, count in totals["models"].items():
                lane_totals["models"][model] = lane_totals["models"].get(model, 0) + count
        if args.expect_lanes is not None and len(lanes) != args.expect_lanes:
            die("expected %d lane transcripts in the window, found %d" % (args.expect_lanes, len(lanes)))

    share = None
    if mode != "none":
        denominator = head["output"] + lane_totals["output"]
        share = (head["output"] / denominator) if denominator else None
    share_text = "n/a" if share is None else "%.1f%%" % (share * 100)
    lanes_clause = ("not scanned" if mode == "none"
                    else "%s out (%s)" % (format(lane_totals["output"], ","), fmt_models(lane_totals["models"])))
    main_line = ("fable share: head %s out / %s flow / %s peak · lanes %s · share %s"
                 % (format(head["output"], ","), format(head["flow"], ","),
                    format(head["peak"], ","), lanes_clause, share_text))
    delta = None if args.baseline_output is None else head["output"] - args.baseline_output
    basis = ("not asserted: lanes not scanned (--lanes none)" if mode == "none"
             else "head output / (head + lane output)")

    if args.format == "json":
        payload = {
            "session": session,
            "project_dir": project_dir,
            "project_dir_source": derivation,
            "window": {"start_index": si, "end_index": ei,
                       "start": win_start.isoformat() if win_start else None,
                       "end": win_end.isoformat() if win_end else None,
                       "start_match": notes["start"], "end_match": notes["end"],
                       "start_marker_matches": notes["start_matches"],
                       "end_marker_matches": notes["end_matches"]},
            "head": {"calls": head["calls"], "records": head["records"], "output": head["output"],
                     "flow": head["flow"], "peak": head["peak"], "models": head["models"],
                     "efforts": head["efforts"], "unusable_usage_records": head["bad_usage"],
                     "partial_usage_calls": head["partial_usage"]},
            "lanes_mode": mode,
            "lane_scan": scan,
            "lanes": [{"name": l["name"], "path": l["path"], "models": l["models"],
                       "calls": l["calls"], "records": l["records"], "output": l["output"],
                       "flow": l["flow"], "peak": l["peak"],
                       "efforts": l["efforts"], "distinct_efforts": len(l["efforts"]),
                       "unusable_usage_records": l["bad_usage"],
                       "unparseable_lines": l["unparseable"],
                       "tail_truncated": l["tail_truncated"]}
                      for l in lanes],
            "lane_totals": {"lanes": len(lanes), "output": lane_totals["output"],
                            "flow": lane_totals["flow"], "calls": lane_totals["calls"],
                            "models": lane_totals["models"]},
            "share": share,
            "share_basis": basis,
            "baseline_output": args.baseline_output,
            "baseline_delta": delta,
            "unparseable_session_lines": stats["unparseable"],
            "session_tail_truncated": stats["tail_truncated"],
            "line": main_line,
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    print("fable-share: session %s · project-dir %s (%s) · tmp-root %s · lanes %s · format %s"
          % (session, project_dir, derivation, args.tmp_root,
             mode if mode != "globs" else " ".join(patterns), args.format))
    torn = "" if not stats["unparseable"] else (
        " · %s unparseable%s" % (plural(stats["unparseable"], "session line"),
                                 " (the final one: a transcript read mid-write looks like this)"
                                 if stats["tail_truncated"] else ""))
    print("window: records %d..%d of %d · %s -> %s · start = %s · end = %s%s"
          % (si, ei, len(rows),
             win_start.isoformat() if win_start else "no timestamp",
             win_end.isoformat() if win_end else "no timestamp",
             notes["start"], notes["end"], torn))
    print("head: %s (%s) · models %s · efforts %s   (nonzero counts = probe ran)"
          % (plural(head["calls"], "call"), plural(head["records"], "assistant record"),
             fmt_models(head["models"]), fmt_models(head["efforts"])))
    if data_clause(head):
        print("head data: %s" % data_clause(head))
    if mode == "none":
        print("lanes: not scanned (--lanes none), so the share is not asserted")
    else:
        expected = ("" if args.expect_lanes is None
                    else " (matches --expect-lanes %d)" % args.expect_lanes)
        print("lanes: %d in window%s · %s" % (len(lanes), expected, scan_clause(scan)))
        for lane in lanes:
            extra = data_clause(lane)
            if lane["unparseable"]:
                extra = " · ".join(filter(None, [
                    extra, "%s unparseable%s" % (plural(lane["unparseable"], "line"),
                                                 " (the final one)" if lane["tail_truncated"] else "")]))
            print("  lane %s: models %s · %s (%s) · %s out · efforts %d (%s)%s"
                  % (lane["name"], fmt_models(lane["models"]), plural(lane["calls"], "call"),
                     plural(lane["records"], "record"),
                     format(lane["output"], ","), len(lane["efforts"]), fmt_models(lane["efforts"]),
                     "" if not extra else " · " + extra))
    print(main_line)
    if delta is not None:
        print("head output delta vs baseline: %s" % format(delta, "+,"))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:                        # a belt: no traceback may pass for a metered run
        traceback.print_exc(file=sys.stderr)
        die("unexpected error, see stderr: %s: %s" % (type(exc).__name__, exc))
