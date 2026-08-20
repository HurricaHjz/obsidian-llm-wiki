#!/usr/bin/env python3
"""Unit tests for funnel_knobs.py — run: python3 test_funnel_knobs.py"""
import json, subprocess, sys
import funnel_knobs as f

P = F = 0
def check(name, cond):
    global P, F
    if cond: P += 1; print(f"  PASS  {name}")
    else:    F += 1; print(f"  FAIL  {name}")

print("== defaults (v2 parity) ==")
k = f.derive(10, 3)
check("default budget 10",        k["budget"] == 10 and k["remaining"] == 10)
check("default shortlist 10",     k["shortlist"] == 10)          # min(12, remaining)
check("default queries 6",        k["queries"] == 6)             # 2 x 3 facets
check("default pool 30",          k["pool"] == 30)               # 3 x shortlist (v2 parity)
check("default date-checks 6",    k["date_checks"] == 6)
check("default remainder hidden", k["show_remainder"] is False)
check("default no marker",        k["raise_marker"] is False)
check("default no clamps",        k["clamps"] == [])

print("== query band ==")
check("1 facet -> band floor 3",  f.derive(10, 1)["queries"] == 3)
check("floor clamp reported",     f.derive(10, 1)["clamps"] != [])
check("7 facets -> band cap 12",  f.derive(10, 7)["queries"] == 12)
check("cap clamp reported",       any("band cap" in c for c in f.derive(10, 7)["clamps"]))
check("--queries 15 -> 12",       f.derive(10, 3, queries=15)["queries"] == 12)
check("--queries 2 allowed",      f.derive(10, 3, queries=2)["queries"] == 2)
check("--queries 0 -> 1",         f.derive(10, 3, queries=0)["queries"] == 1)

print("== shortlist ==")
check("--shortlist 25 -> 20",     f.derive(40, 4, shortlist=25)["shortlist"] == 20)
check("--shortlist 0 -> 1",       f.derive(40, 4, shortlist=0)["shortlist"] == 1)
check("small budget shrinks it",  f.derive(5, 3)["shortlist"] == 5)
check("override kept in range",   f.derive(40, 4, shortlist=8)["shortlist"] == 8)

print("== pool ==")
k = f.derive(40, 5)
check("big run shortlist 12",     k["shortlist"] == 12)
check("big run queries 10",       k["queries"] == 10)
check("big run pool 60",          k["pool"] == 60)               # 1.5 x 40 = 60
check("big run remainder shown",  k["show_remainder"] is True)
check("pool ceiling 60",          f.derive(100, 6)["pool"] == 60)
check("pool floor 3x shortlist",  f.derive(12, 3)["pool"] == 36)  # 3x12 > 1.5x12

print("== budget & ceiling ==")
k = f.derive(250, 4)
check("250 clamps to 100",        k["budget"] == 100)
check("ceiling clamp reported",   any("hard ceiling" in c for c in k["clamps"]))
check("0 clamps to 1",            f.derive(0, 3)["budget"] == 1)

print("== rounds (remaining budget) ==")
k = f.derive(40, 5, pages_captured=30)
check("remaining 10",             k["remaining"] == 10)
check("shortlist follows 10",     k["shortlist"] == 10)
check("pool follows 30",          k["pool"] == 30)
check("remainder off at 10<=10",  k["show_remainder"] is False)
check("collapsed label rendered", "further rows collapsed" in f.render(f.derive(30, 3, pages_captured=25)))
k = f.derive(40, 5, pages_captured=40)
check("exhausted flagged",        k["exhausted"] is True)
check("spent renders once",       f.render(k).count("spent") == 1)

print("== display boundary ==")
check("budget 12 = menu, hidden", f.derive(12, 4)["show_remainder"] is False)
check("budget 13 > menu, shown",  f.derive(13, 4)["show_remainder"] is True)

print("== advice (v3.1: widens display, never consent) ==")
k = f.derive(10, 4, advice=15)                       # remaining 10 = menu 10, advice 15
check("advice > menu shows rows", k["show_remainder"] is True)
check("advice sets raise marker", k["raise_marker"] is True)
check("advice kept in dict",      k["advice"] == 15)
check("advice <= menu no show",   f.derive(10, 4, advice=7)["show_remainder"] is False)
check("advice > pool clamps",     f.derive(10, 4, advice=99)["advice"] == 30)
check("advice clamp reported",    any("--advice" in c for c in f.derive(10, 4, advice=99)["clamps"]))
check("advice line rendered",     "~15 worth capturing" in f.render(f.derive(10, 4, advice=15)))
check("no advice renders dash",   "advice —" in f.render(f.derive(10, 4)))
try: f.derive(10, 3, advice=-1); check("advice -1 raises", False)
except ValueError: check("advice -1 raises", True)

print("== raise marker & reachability (v3.1) ==")
check("oversized shortlist marks", f.derive(6, 3, shortlist=10)["raise_marker"] is True)
check("engaged pool>R marks",      f.derive(40, 5)["raise_marker"] is True)   # pool 60 > 40
check("marker line rendered",      "explicit budget raise" in f.render(f.derive(40, 5)))
check("reachable = min(R, pool)",  f.derive(100, 6)["reachable"] == 60)
check("reachability line at R>P",  "consider --rounds" in f.render(f.derive(100, 6)))
check("no reachability at R<=P",   "consider --rounds" not in f.render(f.derive(10, 4)))

print("== date window ==")
k = f.derive(40, 5, date_window=True)
check("window checks = menu",     k["date_checks"] == 12)
check("cutoff in render",         "cutoff active" in f.render(k))

print("== render flow line (v3.1) ==")
r = f.render(f.derive(10, 4))
check("flow line first",          r.startswith("FUNNEL") and "→ your approval →" in r.splitlines()[0])
check("retired terms absent",     all(t not in r for t in ("dormant", "engaged", "policy tier", "spot-check")))

print("== errors ==")
try: f.derive(10, 0); check("facets 0 raises", False)
except ValueError: check("facets 0 raises", True)
try: f.derive(10, 3, pages_captured=-1); check("neg captured raises", False)
except ValueError: check("neg captured raises", True)

print("== CLI ==")
r = subprocess.run([sys.executable, "funnel_knobs.py", "--max-pages", "40", "--facets", "5",
                    "--date-window", "--json"], capture_output=True, text=True,
                   cwd=__file__.rsplit("/", 1)[0])
j = json.loads(r.stdout)
check("cli json ok",              r.returncode == 0 and j["queries"] == 10 and j["date_checks"] == 12)
r = subprocess.run([sys.executable, "funnel_knobs.py", "--max-pages", "10", "--facets", "3"],
                   capture_output=True, text=True, cwd=__file__.rsplit("/", 1)[0])
check("cli text has FUNNEL",      r.returncode == 0 and r.stdout.startswith("FUNNEL"))
r = subprocess.run([sys.executable, "funnel_knobs.py", "--max-pages", "10", "--facets", "0"],
                   capture_output=True, text=True, cwd=__file__.rsplit("/", 1)[0])
check("cli facets 0 exits 2",     r.returncode == 2)
r = subprocess.run([sys.executable, "funnel_knobs.py", "--max-pages", "10", "--facets", "3",
                    "--ledger-id", "no-such-run-xyz"], capture_output=True, text=True,
                   cwd=__file__.rsplit("/", 1)[0])
check("cli ledger-miss declares", r.returncode == 0 and "DECLARE" in r.stderr)
import run_ledger as _rl, uuid as _uuid, os as _os
_rid = f"fk-{_uuid.uuid4().hex[:8]}"
_rl.init(_rid, 10)
_d = _rl.load(_rl.path_for(_rid))
_rl.raise_budget(_d, 26, "test raise flows to funnel")
_rl.save(_rl.path_for(_rid), _d)
r = subprocess.run([sys.executable, "funnel_knobs.py", "--max-pages", "10", "--facets", "3",
                    "--ledger-id", _rid, "--json"], capture_output=True, text=True,
                   cwd=__file__.rsplit("/", 1)[0])
_j = json.loads(r.stdout)
check("ledger budget overrides stale --max-pages", r.returncode == 0 and _j["budget"] == 26)
check("budget override declared on stderr", "overrides --max-pages" in r.stderr)
_os.remove(_rl.path_for(_rid))

print(f"\n{P} passed, {F} failed")
sys.exit(1 if F else 0)
