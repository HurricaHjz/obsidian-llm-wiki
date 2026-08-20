#!/usr/bin/env python3
"""run_ledger.py — per-run hard state for /gather (gather v3.1).

Evidence, not authority: the ledger records budget, captures, explicit drops, gate
resolutions and each round's queries + shown rows in /tmp/gather-run-<id>.json so
cross-round state survives context pressure and a broken run can resume. The gate echo
remains what the owner trusts; on any ledger-versus-memory mismatch the run STOPS and
asks (see SKILL.md). Auto-on when --rounds > 1 or budget >= 30; --no-ledger opts out.
Pure stdlib. Verbs:
    init --id ID --budget B [--force]      create a fresh ledger (refuses to overwrite;
                                           --force refuses once the file records state)
    add-capture --id ID --url U --slug S   record one written capture
    add-drop --id ID --url U [--reason R]  record an explicit owner drop
    add-gate --id ID --resolved TEXT --count N   record a gate's resolved set
    add-round --id ID --round N --queries "q1 | q2" [--shown "url1 url2"]
                                           record a round's literal queries + shown rows
                                           (feeds Step 6's anti-repeat rule)
    raise-budget --id ID --to N --reason R mid-run budget change, audited in `gates`
                                           (never init --force; refuses < pages captured)
    read --id ID [--full]                  print summary (+ --full: the whole ledger)
"""
import argparse, datetime, json, os, sys

HARD_CEILING = 100  # mirrors funnel_knobs.py / gather_links.py — non-overridable


def path_for(run_id):
    safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in run_id)
    return os.path.join("/tmp", f"gather-run-{safe}.json")


def _now():
    return datetime.datetime.now().isoformat(timespec="seconds")


def load(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    for key in ("run_id", "budget", "captures", "drops", "gates"):
        if key not in data:
            raise ValueError(f"ledger malformed: missing '{key}' — stop and ask the owner")
    data.setdefault("rounds", [])  # pre-№49 ledgers lack it; tolerate, never error
    return data


def save(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    os.replace(tmp, path)


def init(run_id, budget, force=False):
    if budget < 1:
        raise ValueError("--budget must be >= 1")
    budget = min(budget, HARD_CEILING)
    path = path_for(run_id)
    if os.path.exists(path):
        if not force:
            raise FileExistsError(f"{path} exists — a stale or concurrent run? "
                                  "Use a fresh --id, or --force only for a deliberate restart")
        state = None
        try:
            state = load(path)
        except ValueError:
            pass  # unreadable/malformed file guards no trusted state — overwriting loses nothing
        if state is not None and (state["captures"] or state["drops"] or state["gates"]
                                  or state["rounds"]):
            raise FileExistsError(
                f"{path} records run state ({len(state['captures'])} captures, "
                f"{len(state['drops'])} drops, {len(state['gates'])} gates, "
                f"{len(state['rounds'])} rounds) — --force would "
                "erase it, including the persistent-drop record. For a budget change use "
                "raise-budget; --force restarts only a ledger with nothing recorded")
    save(path, {"run_id": run_id, "budget": budget, "created": _now(),
                "captures": [], "drops": [], "gates": [], "rounds": []})
    return path


def raise_budget(data, to, reason):
    """Mid-run budget change: in place, audited in `gates`, floored at pages captured."""
    if to < 1:
        raise ValueError("--to must be >= 1")
    new = min(to, HARD_CEILING)
    captured = len(data["captures"])
    if new < captured:
        raise ValueError(f"budget {new} is below pages already captured ({captured}) — refused")
    entry = {"budget_change": f"{data['budget']}->{new}", "reason": reason, "ts": _now()}
    if to > HARD_CEILING:
        entry["clamped_from"] = to
    data["budget"] = new
    data["gates"].append(entry)


def add_round(data, round_no, queries, shown):
    """Record a round's literal queries + the rows shown at its gate (anti-repeat evidence)."""
    data["rounds"].append({"round": round_no, "queries": queries, "shown": shown, "ts": _now()})


def summary(data):
    captured = len(data["captures"])
    return {"run_id": data["run_id"], "budget": data["budget"],
            "pages_captured": captured,
            "remaining": max(0, data["budget"] - captured),
            "drops": [d["url"] for d in data["drops"]],
            "gates": len(data["gates"]),
            "rounds": len(data.get("rounds", [])),
            "queries_run": [q for r in data.get("rounds", []) for q in r["queries"]]}


def main():
    ap = argparse.ArgumentParser(description="Per-run hard state for /gather (v3.1).")
    ap.add_argument("verb", choices=["init", "add-capture", "add-drop", "add-gate",
                                     "add-round", "raise-budget", "read"])
    ap.add_argument("--id", required=True, help="run id (also names the /tmp file)")
    ap.add_argument("--budget", type=int, help="init: capture budget")
    ap.add_argument("--url"), ap.add_argument("--slug"), ap.add_argument("--reason")
    ap.add_argument("--resolved", help="add-gate: the resolved set, one line")
    ap.add_argument("--count", type=int, help="add-gate: resolved page count")
    ap.add_argument("--round", type=int, help="add-round: round number")
    ap.add_argument("--queries", help="add-round: literal queries, '|'-separated")
    ap.add_argument("--shown", help="add-round: shown-row URLs, space/comma-separated")
    ap.add_argument("--to", type=int, help="raise-budget: the new budget")
    ap.add_argument("--full", action="store_true", help="read: print the whole ledger")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    path = path_for(a.id)
    try:
        if a.verb == "init":
            if a.budget is None:
                raise ValueError("init needs --budget")
            print(f"ledger: {init(a.id, a.budget, a.force)}")
            if a.budget > HARD_CEILING:
                print(f"note: budget clamped {a.budget}->{HARD_CEILING} (hard ceiling)")
            return
        data = load(path)
        if a.verb == "add-capture":
            if not (a.url and a.slug):
                raise ValueError("add-capture needs --url and --slug")
            data["captures"].append({"url": a.url, "slug": a.slug, "ts": _now()})
        elif a.verb == "add-drop":
            if not a.url:
                raise ValueError("add-drop needs --url")
            data["drops"].append({"url": a.url, "reason": a.reason or "", "ts": _now()})
        elif a.verb == "add-gate":
            if a.resolved is None or a.count is None:
                raise ValueError("add-gate needs --resolved and --count")
            data["gates"].append({"resolved": a.resolved, "count": a.count, "ts": _now()})
        elif a.verb == "add-round":
            if a.round is None or not a.queries:
                raise ValueError("add-round needs --round and --queries")
            queries = [q.strip() for q in a.queries.split("|") if q.strip()]
            shown = [u for chunk in (a.shown or "").split(",") for u in chunk.split() if u]
            add_round(data, a.round, queries, shown)
        elif a.verb == "raise-budget":
            if a.to is None or not a.reason:
                raise ValueError("raise-budget needs --to and --reason (the raise is audited)")
            raise_budget(data, a.to, a.reason)
        if a.verb != "read":
            save(path, data)
        if a.verb == "read" and a.full:
            print(json.dumps(data, indent=1))
            return
        print(json.dumps(summary(data), indent=1))
    except FileNotFoundError:
        print(f"run_ledger: {path} missing — fall back to model memory AND declare the "
              "fallback in the funnel block (SKILL.md, ledger guard)", file=sys.stderr)
        sys.exit(2)
    except (ValueError, FileExistsError) as e:
        print(f"run_ledger: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
