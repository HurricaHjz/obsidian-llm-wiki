#!/usr/bin/env python3
"""Unit tests for capture_write.py — run: python3 test_capture_write.py"""
import os, subprocess, sys, tempfile, uuid
import capture_write as cw
import run_ledger as rl

P = F = 0
def check(name, cond):
    global P, F
    if cond: P += 1; print(f"  PASS  {name}")
    else:    F += 1; print(f"  FAIL  {name}")

CWD = __file__.rsplit("/", 1)[0]
RID = f"cwtest-{uuid.uuid4().hex[:8]}"
VAULT = tempfile.mkdtemp(prefix="cwtest-vault-")
os.makedirs(os.path.join(VAULT, "raw"))
os.makedirs(os.path.join(VAULT, "wiki"))

def run(verb, *args, stdin=""):
    return subprocess.run([sys.executable, "capture_write.py", verb, "--vault-root", VAULT] + list(args),
                          input=stdin, capture_output=True, text=True, cwd=CWD)

# realistic bodies for the quality gate (>= QUALITY_MIN_BYTES of prose)
PAD = "lorem ipsum dolor sit amet, consectetur adipiscing elit sed do eiusmod. " * 20
GOOD = "# One\n\nbody [[stray]]\n\n" + PAD
STUB = ("Title: X\n\nURL Source: https://x.test/gone\n\n"
        "Warning: Target URL returned error 404: Not Found\n\n" + PAD)
SHELL = "Title: Page Not Found\n\nURL Source: https://x.test/gone\n\n" + PAD
SOUP = "\n".join(f'<span class="ltx_p" id="s{i}">text {i}</span>' for i in range(150))

print("== sanitise ==")
check("control bytes stripped",  cw.sanitise("a\x00b\x07c") == "abc")
check("newlines kept",           cw.sanitise("a\nb\tc") == "a\nb\tc")
check("wiki links defanged",     cw.sanitise("see [[page]]") == r"see \[\[page]]")
check("bareword link defanged",  cw.sanitise("[eq](x1)") == "eq (x1)")
check("real url link kept",      cw.sanitise("[a](https://x.test/p)") == "[a](https://x.test/p)")
check("anchor link kept",        cw.sanitise("[a](#sec)") == "[a](#sec)")
check("dotted target kept",      cw.sanitise("[a](file.md)") == "[a](file.md)")

print("== slug ==")
check("slug from url",           cw.slug_from("https://x.test/A/B?q=1") == "x-test-a-b-q-1")
check("slug from title wins",    cw.slug_from("https://x.test", "My Great Paper!") == "my-great-paper")
check("slug never empty",        cw.slug_from("///") == "capture")

print("== write path ==")
rl.init(RID, 3)
r = run("write", "--url", "https://x.test/one", "--ledger-id", RID,
        "--engine", "defuddle", "--title", "One", stdin=GOOD)
dest = os.path.join(VAULT, "raw", "one.md")
check("write ok",                r.returncode == 0 and os.path.exists(dest))
body = open(dest).read()
check("frontmatter complete",    all(s in body for s in
      ('title: "One"', "source_url: https://x.test/one", "converted_from:",
       "converted_by: defuddle", "converted_on:")))
check("body sanitised",          r"\[\[stray]]" in body)
check("clean write not stamped", "capture_quality" not in body)
check("ledger appended",         rl.summary(rl.load(rl.path_for(RID)))["pages_captured"] == 1)
r = run("write", "--url", "https://x.test/one", "--ledger-id", RID, "--title", "One", stdin=GOOD)
check("existing path refused",   r.returncode == 2 and "immutable" in r.stderr)
r = run("write", "--url", "https://x.test/two", "--ledger-id", RID, "--title", "Two", stdin=GOOD)
check("second write ok",         r.returncode == 0)
r = run("write", "--url", "https://x.test/four", "--ledger-id", "missing-" + RID, stdin=GOOD)
check("missing ledger stops",    r.returncode == 2 and "STOP" in r.stderr)
r = run("write", "--url", "https://x.test/five", "--ledger-id", RID, stdin="   ")
check("empty stdin refused",     r.returncode == 2)

print("== quality gate ==")
r = run("write", "--url", "https://x.test/stub", "--ledger-id", RID, "--title", "Stub", stdin=STUB)
check("error stub refused",      r.returncode == 2 and "quality gate" in r.stderr)
r = run("write", "--url", "https://x.test/shell", "--ledger-id", RID, "--title", "Shell", stdin=SHELL)
check("404 shell refused",       r.returncode == 2 and "Page Not Found" in r.stderr)
r = run("write", "--url", "https://x.test/soup", "--ledger-id", RID, "--title", "Soup", stdin=SOUP)
check("html soup refused",       r.returncode == 2 and "HTML-dominant" in r.stderr)
check("refusals spend no budget", rl.summary(rl.load(rl.path_for(RID)))["pages_captured"] == 2)
r = run("write", "--url", "https://x.test/soup", "--ledger-id", RID, "--title", "Soup",
        "--allow-degraded", "tutorial page, HTML is the content", stdin=SOUP)
soup_dest = os.path.join(VAULT, "raw", "soup.md")
check("allow-degraded writes",   r.returncode == 0 and "DEGRADED" in r.stdout and os.path.exists(soup_dest))
check("acceptance stamped",      "capture_quality" in open(soup_dest).read())
check("ledger records degraded", rl.load(rl.path_for(RID))["captures"][-1].get("degraded") is not None)
r = run("write", "--url", "https://x.test/six", "--ledger-id", RID, "--title", "Six", stdin=GOOD)
check("budget spent refused",    r.returncode == 2 and "budget spent" in r.stderr)
r = run("check", stdin=GOOD)
check("check passes good body",  r.returncode == 0 and "PASS" in r.stdout)
r = run("check", stdin=STUB)
check("check rejects stub",      r.returncode == 3 and "REJECT" in r.stdout)

print("== dedup ==")
r = run("dedup", "--urls", "https://x.test/one,https://x.test/new", "--control", "https://x.test/two")
r2 = run("dedup", "--urls", "https://x.test/one", "https://x.test/new", "--control", "https://x.test/two")
check("space form works",        r2.returncode == 0 and "ALREADY IN VAULT" in r2.stdout and "https://x.test/new -> new" in r2.stdout)
r2 = run("dedup", "--urls", "https://x.test/one,https://x.test/new", "https://x.test/extra", "--control", "https://x.test/two")
check("mixed form works",        r2.returncode == 0 and "https://x.test/extra -> new" in r2.stdout)
check("dedup finds present",     r.returncode == 0 and "ALREADY IN VAULT" in r.stdout)
check("dedup passes new",        "https://x.test/new -> new" in r.stdout)
r = run("dedup", "--urls", "https://x.test/new", "--control", "https://nowhere.test/none")
check("dead control fails scan", r.returncode == 2 and "cannot be trusted" in r.stderr)
r = run("dedup", "--urls", "https://x.test/new")
check("no control refused",      r.returncode == 2 and "control" in r.stderr)
r = run("dedup", "--urls", "https://x.test/new", "--allow-no-control")
check("explicit opt-out works",  r.returncode == 0)

os.remove(rl.path_for(RID))
import shutil; shutil.rmtree(VAULT)
print(f"\n{P} passed, {F} failed")
sys.exit(1 if F else 0)
