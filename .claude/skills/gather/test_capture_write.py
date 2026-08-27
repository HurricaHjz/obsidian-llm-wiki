#!/usr/bin/env python3
"""Unit tests for capture_write.py — run: python3 test_capture_write.py"""
import json, os, subprocess, sys, tempfile, uuid
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
check("closed fence verbatim",   cw.sanitise("```json\n[[0, 10]] [eq](x1)\n```\n") == "```json\n[[0, 10]] [eq](x1)\n```\n")
check("unclosed fence defanged", cw.sanitise("```\n[[x]]") == "```\n" + r"\[\[x]]")
check("prose around fence defanged", cw.sanitise("see [[p]]\n```\n[[keep]]\n```\n[[q]]") == r"see \[\[p]]" + "\n```\n[[keep]]\n```\n" + r"\[\[q]]")

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
JSONSTUB = '{"data":null,"code":403,"name":"AbuseAlleviationError","message":"' + "blocked. " * 90 + '"}'
r = run("check", stdin=JSONSTUB)
check("json error stub refused", r.returncode == 3 and "JSON document" in r.stdout)
BRACED = "{ this page opens with a brace but is prose, not JSON }\n\n" + PAD
r = run("check", stdin=BRACED)
check("brace-opening prose passes", r.returncode == 0 and "PASS" in r.stdout)

print("== platform lane (tier-3 fenced captures) ==")
RID2 = f"cwtest2-{uuid.uuid4().hex[:8]}"
rl.init(RID2, 2)
TWEET_PAYLOAD = json.dumps([
    {"id": str(i), "text": f"[eq](x1) tweet {i} " + "lorem ipsum dolor sit amet " * 8,
     "entities": {"indices": [[0, 10]]}} for i in range(3)], indent=1)
TWEETS = "# X search: test query (2026-08-26)\n\nsee [[page]]\n\n```json\n" + TWEET_PAYLOAD + "\n```\n"
r = run("write", "--url", "https://x.test/search-q", "--ledger-id", RID2,
        "--engine", "twitter-cli 0.8.5 via agent-reach", "--title", "Tweets", stdin=TWEETS)
tw_dest = os.path.join(VAULT, "raw", "tweets.md")
check("fenced platform data writes", r.returncode == 0 and os.path.exists(tw_dest))
tw_body = open(tw_dest).read()
check("fenced payload byte-exact",   TWEET_PAYLOAD in tw_body)
check("prose outside still defanged", r"\[\[page]]" in tw_body)
AUTHFAIL = ("# X search: test query\n\n```json\n"
            + json.dumps({"errors": [{"message": "Could not authenticate you. " + "blocked. " * 80,
                                      "code": 32}]}) + "\n```\n")
r = run("check", stdin=AUTHFAIL)
check("fenced auth-error refused",   r.returncode == 3 and "carries no content" in r.stdout)
EMPTYMETA = ("# X search: test query\n\n```json\n"
             + json.dumps({"data": None, "includes": None,
                           "meta": {"result_count": 0, "next_token": "x" * 600}}) + "\n```\n")
r = run("check", stdin=EMPTYMETA)
check("fenced empty result refused", r.returncode == 3 and "carries no content" in r.stdout)
EMPTYARR = "# Reddit read\n\n" + "context line. " * 20 + "\n\n```json\n" + "[]".ljust(400) + "\n```\n"
r = run("check", stdin=EMPTYARR)
check("fenced empty array refused",  r.returncode == 3 and "empty platform result" in r.stdout)
PARTIAL = ("# X search\n\n```json\n"
           + json.dumps({"data": [{"id": "1", "text": "real tweet " * 60}],
                         "errors": [{"message": "partial failure on one expansion"}]}) + "\n```\n")
r = run("check", stdin=PARTIAL)
check("partial data + errors passes", r.returncode == 0 and "PASS" in r.stdout)
SUBS = ("# YouTube subtitles\n\n```\nWEBVTT\n\n"
        + "\n".join(f"00:0{i%10}:01.000 --> 00:0{i%10}:02.000\n<i>spoken line {i}</i>\n"
                    for i in range(60)) + "\n```\n")
r = run("check", stdin=SUBS)
check("fenced subtitle markup passes", r.returncode == 0 and "PASS" in r.stdout)
LOGINWALL = ("# Reddit read\n\n```\n<!DOCTYPE html>\n<html>\n<head><title>Log in</title></head>\n<body>\n"
             + "\n".join(f'<div class="login-prompt-{i}">please sign in</div>' for i in range(40))
             + "\n</body>\n</html>\n```\n")
r = run("check", stdin=LOGINWALL)
check("fenced login wall refused",   r.returncode == 3 and "HTML page" in r.stdout)
QUOTED = ("# Article about the X API\n\n" + PAD + "\n\nAn auth failure returns:\n\n```json\n"
          + json.dumps({"errors": [{"message": "Could not authenticate you", "code": 32}]}) + "\n```\n\n" + PAD)
r = run("check", stdin=QUOTED)
check("quoted error example passes", r.returncode == 0 and "PASS" in r.stdout)
BAREARRAY = json.dumps([{"id": "1", "text": "unfenced platform output " * 40}])
r = run("check", stdin=BAREARRAY)
check("bare JSON array refused",     r.returncode == 3 and "bare JSON document" in r.stdout)

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

long_fm = os.path.join(VAULT, "raw", "longfm.md")
open(long_fm, "w").write("---\ntitle: t\nnote_field: " + "x" * 5000 + "\nsource_url: https://x.test/longfm\n---\nbody\n")
r = run("dedup", "--urls", "https://x.test/longfm", "--control", "https://x.test/two")
check("key past 4096 B found (extend-on-miss)", "ALREADY IN VAULT" in r.stdout and "longfm" in r.stdout)

print("== vault-root guard (2026-08-26 defect) ==")
SCRIPT = os.path.join(CWD, "capture_write.py")
r = subprocess.run([sys.executable, SCRIPT, "dedup", "--urls", "https://nowhere.test/a",
                    "--allow-no-control"], capture_output=True, text=True, cwd=tempfile.gettempdir())
check("foreign cwd defaults to the script's vault", r.returncode == 0 and "-> new" in r.stdout)
BOGUS = tempfile.mkdtemp(prefix="cwtest-notavault-")
r = subprocess.run([sys.executable, SCRIPT, "dedup", "--urls", "x", "--allow-no-control",
                    "--vault-root", BOGUS], capture_output=True, text=True, cwd=CWD)
check("dedup refuses a non-vault root", r.returncode == 2 and "not a vault root" in r.stderr)
r = subprocess.run([sys.executable, SCRIPT, "write", "--url", "https://x.test/x", "--ledger-id", RID,
                    "--vault-root", BOGUS], input=GOOD, capture_output=True, text=True, cwd=CWD)
check("write refuses a non-vault root", r.returncode == 2 and "not a vault root" in r.stderr)

os.remove(rl.path_for(RID))
os.remove(rl.path_for(RID2))
import shutil; shutil.rmtree(VAULT); shutil.rmtree(BOGUS)
print(f"\n{P} passed, {F} failed")
sys.exit(1 if F else 0)
