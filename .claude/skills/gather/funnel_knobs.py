#!/usr/bin/env python3
"""funnel_knobs.py — deterministic funnel derivation for /gather search mode (gather v3.1).

Given the page budget and the brief's sub-question count (plus optional overrides), it fixes
every Discover-round knob — queries, menu (shortlist), pool, date-check policy, remainder
display — clamps out-of-range values, and reports every clamp. The rendered block is echoed
VERBATIM at the Discover gate, so the knobs a run actually used are always auditable (the
2026-08-13 pilot showed prose-only bands drift). v3.1: --advice N (the agent's judged
worth-capturing count) widens the one-liner display, never what a rule may buy; --ledger-id
reads pages-captured AND the audited budget from the run ledger instead of trusting supplied
numbers (a raise-budget amendment flows through automatically; an override is declared). Pure stdlib,
read-only, no network. Run:
    python3 funnel_knobs.py --max-pages N --facets F [--shortlist N] [--queries N]
            [--pages-captured N] [--advice N] [--ledger-id ID] [--date-window] [--json]
"""
import argparse, json, math, sys

HARD_CEILING = 100           # cumulative page ceiling — mirrors gather_links.py, non-overridable
SHORTLIST_CAP_DEFAULT = 12   # default full-detail menu rows (human review bandwidth)
SHORTLIST_MAX = 20           # --shortlist clamp
QUERIES_PER_FACET = 2
QUERIES_BAND = (3, 12)       # band for the DERIVED value; an explicit --queries clamps to [1, 12]
POOL_SHORTLIST_FACTOR = 3.0  # ranking headroom over the menu (v2 parity: default run -> pool 30)
POOL_BUDGET_FACTOR = 1.5     # selection headroom over the capture budget (rule needs choice)
POOL_CEILING = 60            # snippet-cost ceiling: <=12 searches (~1k tokens each) fill it
DATECHECK_BASELINE = 6       # WebFetch date checks per round when no hard date window


def derive(max_pages, facets, shortlist=None, queries=None, pages_captured=0,
           date_window=False, advice=None):
    """Return the round's knobs as a dict; every clamp is appended to result['clamps']."""
    if facets < 1:
        raise ValueError("--facets must be >= 1 (state the brief's sub-question count)")
    if pages_captured < 0:
        raise ValueError("--pages-captured must be >= 0")
    if advice is not None and advice < 0:
        raise ValueError("--advice must be >= 0")
    clamps = []
    budget = max_pages
    if budget > HARD_CEILING:
        clamps.append(f"--max-pages {budget} > hard ceiling -> {HARD_CEILING}")
        budget = HARD_CEILING
    if budget < 1:
        clamps.append(f"--max-pages {budget} < 1 -> 1")
        budget = 1
    remaining = budget - pages_captured
    if remaining <= 0:
        return {"exhausted": True, "budget": budget, "remaining": 0, "clamps": clamps,
                "note": "budget spent — stop, or raise --max-pages"}
    if shortlist is None:
        k = min(SHORTLIST_CAP_DEFAULT, remaining)
    else:
        k = shortlist
        if k > SHORTLIST_MAX:
            clamps.append(f"--shortlist {k} -> {SHORTLIST_MAX}")
            k = SHORTLIST_MAX
        if k < 1:
            clamps.append(f"--shortlist {k} -> 1")
            k = 1
    if queries is None:
        q = QUERIES_PER_FACET * facets
        lo, hi = QUERIES_BAND
        if q < lo:
            clamps.append(f"queries {QUERIES_PER_FACET}x{facets}={q} -> band floor {lo}")
            q = lo
        if q > hi:
            clamps.append(f"queries {QUERIES_PER_FACET}x{facets}={q} -> band cap {hi}")
            q = hi
    else:
        q = queries
        if q > QUERIES_BAND[1]:
            clamps.append(f"--queries {q} -> {QUERIES_BAND[1]}")
            q = QUERIES_BAND[1]
        if q < 1:
            clamps.append(f"--queries {q} -> 1")
            q = 1
    pool = min(POOL_CEILING, max(math.ceil(POOL_SHORTLIST_FACTOR * k),
                                 math.ceil(POOL_BUDGET_FACTOR * remaining)))
    if advice is not None and advice > pool:
        clamps.append(f"--advice {advice} > pool -> {pool}")
        advice = pool
    # Display is wider than consent: one-liners show when budget OR advice outruns the menu;
    # what a rule may buy stays capped at `remaining` regardless (SKILL.md, Discover gate).
    show_remainder = remaining > k or (advice or 0) > k
    raise_marker = k > remaining or (show_remainder and pool > remaining)
    date_checks = k if date_window else DATECHECK_BASELINE
    return {"exhausted": False, "budget": budget, "remaining": remaining, "facets": facets,
            "shortlist": k, "queries": q, "pool": pool, "date_checks": date_checks,
            "date_window": date_window, "advice": advice,
            "show_remainder": show_remainder, "raise_marker": raise_marker,
            "reachable": min(remaining, pool), "clamps": clamps}


def render(k):
    """The human-readable block the agent echoes at the Discover gate."""
    clamp_str = "; ".join(k["clamps"]) if k["clamps"] else "none"
    if k.get("exhausted"):
        return (f"FUNNEL  budget {k['budget']} spent — stop, or raise --max-pages\n"
                f"        clamps: {clamp_str}")
    advice = k["advice"]
    lines = [(f"FUNNEL  {k['queries']} searches → pool ≤{k['pool']} ranked → "
              f"menu {k['shortlist']} → your approval → capture ≤{k['reachable']}"),
             (f"        budget {k['budget']} ({k['remaining']} left) · "
              f"queries {k['queries']} ({k['facets']} sub-question"
              f"{'s' if k['facets'] != 1 else ''} × {QUERIES_PER_FACET}) · "
              f"advice {'~' + str(advice) + ' worth capturing' if advice is not None else '—'}")]
    if k["date_window"]:
        lines.append(f"        date checks: cutoff active — all {k['shortlist']} menu rows "
                     f"verified pre-gate (baseline {DATECHECK_BASELINE}, overrun declared); "
                     f"below-menu rows checked at capture")
    else:
        lines.append(f"        date checks ≤{k['date_checks']} (unclear rows only)")
    state = ("one-liners shown below the menu — rule-selectable"
             if k["show_remainder"]
             else "budget fits the menu — further rows collapsed (say 'show all')")
    lines.append(f"        {state} · clamps: {clamp_str}")
    if k["raise_marker"]:
        lines.append(f"        rows beyond №{k['remaining']} need an explicit budget raise "
                     f"(rules cap at {k['remaining']})")
    if k["remaining"] > k["pool"]:
        lines.append(f"        budget exceeds this round's pool — reachable this round "
                     f"≤{k['pool']}; consider --rounds")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(
        description="Derive the /gather search-mode funnel knobs (gather v3.1).")
    ap.add_argument("--max-pages", type=int, required=True,
                    help="capture budget for the run (hard ceiling 100)")
    ap.add_argument("--facets", type=int, required=True,
                    help="number of distinct sub-questions in the brief (agent-stated, printed)")
    ap.add_argument("--shortlist", type=int, default=None,
                    help="override the menu row count (clamp <=20)")
    ap.add_argument("--queries", type=int, default=None,
                    help="override queries per round (clamp <=12)")
    ap.add_argument("--pages-captured", type=int, default=0,
                    help="pages already captured this run (later rounds)")
    ap.add_argument("--advice", type=int, default=None,
                    help="agent-judged worth-capturing count (widens display, never consent)")
    ap.add_argument("--ledger-id", default=None,
                    help="read --pages-captured from this run ledger (overrides the flag)")
    ap.add_argument("--date-window", action="store_true",
                    help="a hard recency bound is active — full menu date verification")
    ap.add_argument("--json", action="store_true", dest="as_json")
    a = ap.parse_args()
    pages = a.pages_captured
    if a.ledger_id:
        import run_ledger
        try:
            data = run_ledger.load(run_ledger.path_for(a.ledger_id))
            pages = len(data["captures"])
            if data["budget"] != a.max_pages:
                print(f"funnel_knobs: ledger budget {data['budget']} overrides --max-pages "
                      f"{a.max_pages} (raises are audited in the ledger) — DECLARE this at "
                      f"the gate", file=sys.stderr)
                a.max_pages = data["budget"]
        except (FileNotFoundError, ValueError) as e:
            print(f"funnel_knobs: ledger unreadable ({e}) — falling back to "
                  f"--pages-captured {pages}; DECLARE this fallback at the gate",
                  file=sys.stderr)
    try:
        k = derive(a.max_pages, a.facets, a.shortlist, a.queries, pages,
                   a.date_window, a.advice)
    except ValueError as e:
        print(f"funnel_knobs: {e}", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(k, indent=2) if a.as_json else render(k))


if __name__ == "__main__":
    main()
