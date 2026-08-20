#!/usr/bin/env python3
"""Unit tests for run_ledger.py — run: python3 test_run_ledger.py"""
import json, os, subprocess, sys, uuid
import run_ledger as rl

P = F = 0
def check(name, cond):
    global P, F
    if cond: P += 1; print(f"  PASS  {name}")
    else:    F += 1; print(f"  FAIL  {name}")

RID = f"test-{uuid.uuid4().hex[:8]}"
PATH = rl.path_for(RID)

print("== init ==")
rl.init(RID, 10)
check("file created",            os.path.exists(PATH))
check("budget stored",           rl.load(PATH)["budget"] == 10)
try: rl.init(RID, 10); check("re-init refused", False)
except FileExistsError: check("re-init refused", True)
rl.init(RID, 10, force=True)
check("force re-init works",     rl.load(PATH)["captures"] == [])
check("budget clamps to 100",    rl.load(rl.init(RID + "-b", 250))["budget"] == 100)
try: rl.init(RID + "-c", 0); check("budget 0 raises", False)
except ValueError: check("budget 0 raises", True)
check("id sanitised in path",    "/" not in os.path.basename(rl.path_for("a/b c")).replace(".json", "").replace("gather-run-", ""))

print("== state & summary ==")
d = rl.load(PATH)
d["captures"].append({"url": "https://x.test/1", "slug": "x-1", "ts": "t"})
d["drops"].append({"url": "https://x.test/2", "reason": "off-topic", "ts": "t"})
rl.save(PATH, d)
s = rl.summary(rl.load(PATH))
check("pages_captured counts",   s["pages_captured"] == 1)
check("remaining derived",       s["remaining"] == 9)
check("drops listed",            s["drops"] == ["https://x.test/2"])

print("== init --force state guard (№49 P7-D3) ==")
try: rl.init(RID, 10, force=True); check("force refused once state recorded", False)
except FileExistsError as e: check("force refused once state recorded", "raise-budget" in str(e))

print("== raise-budget (№49 P7-D3) ==")
d = rl.load(PATH)
rl.raise_budget(d, 26, "owner raised cap mid-run")
check("budget raised in place",  d["budget"] == 26)
check("raise audited in gates",  any("budget_change" in g and g["budget_change"] == "10->26" for g in d["gates"]))
rl.raise_budget(d, 250, "test clamp")
check("raise clamps to 100",     d["budget"] == 100 and any(g.get("clamped_from") == 250 for g in d["gates"]))
d["captures"].append({"url": "https://x.test/3", "slug": "x-3", "ts": "t"})
d["captures"].append({"url": "https://x.test/4", "slug": "x-4", "ts": "t"})
try: rl.raise_budget(d, 2, "below captured"); check("refuses budget < captured", False)
except ValueError: check("refuses budget < captured", True)
try: rl.raise_budget(d, 0, "zero"); check("refuses --to < 1", False)
except ValueError: check("refuses --to < 1", True)

print("== add-round / anti-repeat record (№49 P3) ==")
rl.add_round(d, 1, ["q one", "q two"], ["https://x.test/1", "https://x.test/9"])
rl.save(PATH, d)
d2 = rl.load(PATH)
check("round persisted",         len(d2["rounds"]) == 1 and d2["rounds"][0]["round"] == 1)
s2 = rl.summary(d2)
check("summary counts rounds",   s2["rounds"] == 1)
check("summary flattens queries", s2["queries_run"] == ["q one", "q two"])
check("shown rows persisted",    d2["rounds"][0]["shown"] == ["https://x.test/1", "https://x.test/9"])
legacy = {k: v for k, v in d2.items() if k != "rounds"}
rl.save(PATH, legacy)
check("pre-№49 ledger tolerated", rl.load(PATH)["rounds"] == [])
RID_R = f"test-{uuid.uuid4().hex[:8]}-r"
rl.init(RID_R, 10)
dr = rl.load(rl.path_for(RID_R))
rl.add_round(dr, 1, ["only a round"], [])
rl.save(rl.path_for(RID_R), dr)
try: rl.init(RID_R, 10, force=True); check("force refused on rounds-only state", False)
except FileExistsError: check("force refused on rounds-only state", True)

print("== malformed ledger ==")
with open(PATH, "w") as fh: json.dump({"run_id": RID}, fh)
try: rl.load(PATH); check("malformed raises", False)
except ValueError: check("malformed raises", True)
rl.init(RID, 10, force=True)
check("force allowed on unreadable file", rl.load(PATH)["captures"] == [])

print("== CLI ==")
cwd = __file__.rsplit("/", 1)[0]
rid2 = f"test-{uuid.uuid4().hex[:8]}"
r = subprocess.run([sys.executable, "run_ledger.py", "init", "--id", rid2, "--budget", "5"],
                   capture_output=True, text=True, cwd=cwd)
check("cli init ok",             r.returncode == 0 and "ledger:" in r.stdout)
r = subprocess.run([sys.executable, "run_ledger.py", "add-capture", "--id", rid2,
                    "--url", "https://y.test", "--slug", "y"], capture_output=True, text=True, cwd=cwd)
check("cli add-capture ok",      r.returncode == 0 and '"pages_captured": 1' in r.stdout)
r = subprocess.run([sys.executable, "run_ledger.py", "read", "--id", rid2],
                   capture_output=True, text=True, cwd=cwd)
check("cli read ok",             r.returncode == 0 and '"remaining": 4' in r.stdout)
r = subprocess.run([sys.executable, "run_ledger.py", "read", "--id", "missing-" + rid2],
                   capture_output=True, text=True, cwd=cwd)
check("cli missing exits 2",     r.returncode == 2 and "fall back to model memory" in r.stderr)
r = subprocess.run([sys.executable, "run_ledger.py", "raise-budget", "--id", rid2, "--to", "8"],
                   capture_output=True, text=True, cwd=cwd)
check("cli raise needs --reason", r.returncode == 2 and "--reason" in r.stderr)
r = subprocess.run([sys.executable, "run_ledger.py", "raise-budget", "--id", rid2, "--to", "8",
                    "--reason", "test"], capture_output=True, text=True, cwd=cwd)
check("cli raise-budget ok",     r.returncode == 0 and '"budget": 8' in r.stdout)
r = subprocess.run([sys.executable, "run_ledger.py", "add-round", "--id", rid2, "--round", "1",
                    "--queries", "alpha beta | gamma", "--shown", "https://y.test,https://z.test"],
                   capture_output=True, text=True, cwd=cwd)
check("cli add-round ok",        r.returncode == 0 and '"queries_run"' in r.stdout and "gamma" in r.stdout)
r = subprocess.run([sys.executable, "run_ledger.py", "read", "--id", rid2, "--full"],
                   capture_output=True, text=True, cwd=cwd)
check("cli read --full dumps rounds", r.returncode == 0 and '"rounds"' in r.stdout and "https://z.test" in r.stdout)
r = subprocess.run([sys.executable, "run_ledger.py", "init", "--id", rid2 + "-clamp",
                    "--budget", "250"], capture_output=True, text=True, cwd=cwd)
check("cli init reports clamp",  r.returncode == 0 and "clamped 250->100" in r.stdout)

for rid in (RID, RID + "-b", rid2, RID_R, rid2 + "-clamp"):
    p = rl.path_for(rid)
    if os.path.exists(p): os.remove(p)

print(f"\n{P} passed, {F} failed")
sys.exit(1 if F else 0)
