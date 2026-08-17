#!/usr/bin/env python3
"""funnel_knobs.py — deterministic funnel derivation for /gather search mode (gather v3).

Given the page budget and the brief's facet count (plus optional overrides), it fixes every
Discover-round knob — queries, shortlist, pool, spot-check policy, policy tier — clamps
out-of-range values, and reports every clamp. The rendered block is echoed VERBATIM at the
Discover gate, so the knobs a run actually used are always auditable (the 2026-08-13 pilot
showed prose-only bands drift). Pure stdlib, read-only, no network. Run:
    python3 funnel_knobs.py --max-pages N --facets F [--shortlist N] [--queries N]
            [--pages-captured N] [--date-window] [--json]
"""
import argparse, json, math, sys

HARD_CEILING = 100           # cumulative page ceiling — mirrors gather_links.py, non-overridable
SHORTLIST_CAP_DEFAULT = 12   # default full-detail rows (human review bandwidth)
SHORTLIST_MAX = 20           # --shortlist clamp
QUERIES_PER_FACET = 2
QUERIES_BAND = (3, 12)       # band for the DERIVED value; an explicit --queries clamps to [1, 12]
POOL_SHORTLIST_FACTOR = 3.0  # ranking headroom over the menu (v2 parity: default run -> pool 30)
POOL_BUDGET_FACTOR = 1.5     # selection headroom over the capture budget (rule needs choice)
POOL_CEILING = 60            # snippet-cost ceiling: <=12 searches (~1k tokens each) fill it
SPOTCHECK_BASELINE = 6       # WebFetch date spot-checks per round when no hard date window


def derive(max_pages, facets, shortlist=None, queries=None, pages_captured=0,
           date_window=False):
    """Return the round's knobs as a dict; every clamp is appended to result['clamps']."""
    if facets < 1:
        raise ValueError("--facets must be >= 1 (state the brief's facet count)")
    if pages_captured < 0:
        raise ValueError("--pages-captured must be >= 0")
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
                "note": "no further Discover round; stop, or raise --max-pages"}
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
    policy_tier = remaining > k
    spot_cap = k if date_window else SPOTCHECK_BASELINE
    return {"exhausted": False, "budget": budget, "remaining": remaining, "facets": facets,
            "shortlist": k, "queries": q, "pool": pool, "spot_checks": spot_cap,
            "date_window": date_window, "policy_tier": policy_tier, "clamps": clamps}


def render(k):
    """The human-readable block the agent echoes at the Discover gate."""
    clamp_str = "; ".join(k["clamps"]) if k["clamps"] else "none"
    if k.get("exhausted"):
        return (f"FUNNEL  budget {k['budget']} exhausted — {k['note']}\n"
                f"        clamps: {clamp_str}")
    lines = [(f"FUNNEL  budget {k['budget']} (remaining {k['remaining']}) · "
              f"shortlist {k['shortlist']} · queries {k['queries']} "
              f"({k['facets']} facet{'s' if k['facets'] != 1 else ''} × {QUERIES_PER_FACET}) · "
              f"pool ≤{k['pool']}")]
    if k["date_window"]:
        lines.append(f"        spot-checks: date-window — verify ALL top-{k['shortlist']} "
                     f"pre-gate (baseline {SPOTCHECK_BASELINE}, overrun declared); "
                     f"below-fold rows checked at capture")
    else:
        lines.append(f"        spot-checks ≤{k['spot_checks']} (unclear finalists only)")
    tier = ("ENGAGED — ranked remainder capturable by rule" if k["policy_tier"]
            else "dormant (remaining ≤ shortlist)")
    lines.append(f"        policy tier: {tier} · clamps: {clamp_str}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(
        description="Derive the /gather search-mode funnel knobs (gather v3).")
    ap.add_argument("--max-pages", type=int, required=True,
                    help="capture budget for the run (hard ceiling 100)")
    ap.add_argument("--facets", type=int, required=True,
                    help="number of distinct facets in the brief (agent-stated, printed)")
    ap.add_argument("--shortlist", type=int, default=None,
                    help="override the full-detail row count (clamp <=20)")
    ap.add_argument("--queries", type=int, default=None,
                    help="override queries per round (clamp <=12)")
    ap.add_argument("--pages-captured", type=int, default=0,
                    help="pages already captured this run (later rounds)")
    ap.add_argument("--date-window", action="store_true",
                    help="a hard recency bound is active — full top-tier date verification")
    ap.add_argument("--json", action="store_true", dest="as_json")
    a = ap.parse_args()
    try:
        k = derive(a.max_pages, a.facets, a.shortlist, a.queries, a.pages_captured,
                   a.date_window)
    except ValueError as e:
        print(f"funnel_knobs: {e}", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(k, indent=2) if a.as_json else render(k))


if __name__ == "__main__":
    main()
