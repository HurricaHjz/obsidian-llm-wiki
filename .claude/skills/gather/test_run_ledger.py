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

print("== malformed ledger ==")
with open(PATH, "w") as fh: json.dump({"run_id": RID}, fh)
try: rl.load(PATH); check("malformed raises", False)
except ValueError: check("malformed raises", True)

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

for rid in (RID, RID + "-b", rid2):
    p = rl.path_for(rid)
    if os.path.exists(p): os.remove(p)

print(f"\n{P} passed, {F} failed")
sys.exit(1 if F else 0)
