#!/usr/bin/env python3
"""Unit tests for gather_links.py — run: python3 test_gather_links.py"""
import sys, gather_links as g

P = F = 0
def check(name, cond):
    global P, F
    if cond: P += 1; print(f"  PASS  {name}")
    else:    F += 1; print(f"  FAIL  {name}")

print("== extract_links ==")
links = g.extract_links(
    "see [paper](https://arxiv.org/abs/1234) and https://github.com/a/b "
    "plus https://github.com/a/b again, mail x@y.com")
check("finds markdown link", "https://arxiv.org/abs/1234" in links)
check("finds bare link", "https://github.com/a/b" in links)
check("de-dupes", links.count("https://github.com/a/b") == 1)
check("ignores non-url email", not any("x@y.com" in u for u in links))

print("== classify: expand ==")
check("arxiv -> expand",       g.classify("https://arxiv.org/abs/1")[0] == "expand")
check("github -> expand",      g.classify("https://github.com/x/y")[0] == "expand")
check("github.io -> expand",   g.classify("https://foo.github.io/proj")[0] == "expand")
check("/docs -> expand",       g.classify("https://site.com/docs")[0] == "expand")
check(".pdf -> expand",        g.classify("https://site.com/a/paper.pdf")[0] == "expand")

print("== classify: skip ==")
check("twitter -> skip",       g.classify("https://twitter.com/foo")[0] == "skip")
check("linkedin -> skip",      g.classify("https://www.linkedin.com/in/x")[0] == "skip")
check("/login -> skip",        g.classify("https://site.com/login")[0] == "skip")
check("mailto -> skip",        g.classify("mailto:a@b.com")[0] == "skip")
check("anchor -> skip",        g.classify("#section")[0] == "skip")
check("image asset -> skip",   g.classify("https://site.com/logo.png")[0] == "skip")
check("share/utm -> skip",     g.classify("https://site.com/x?utm_source=tw")[0] == "skip")

print("== classify: maybe / overrides ==")
check("unknown -> maybe",      g.classify("https://randomblog.example/post/123")[0] == "maybe")
check("--include forces expand", g.classify("https://randomblog.example/x", include=["randomblog"])[0] == "expand")
check("--exclude forces skip",   g.classify("https://arxiv.org/abs/1", exclude=["arxiv"])[0] == "skip")
check("exclude beats include",   g.classify("https://arxiv.org/x", include=["arxiv"], exclude=["arxiv"])[0] == "skip")

print("== classify: --same-domain ==")
check("off-domain -> skip",    g.classify("https://other.com/docs", seed_host="seed.com", same_domain=True)[0] == "skip")
check("same host -> expand",   g.classify("https://seed.com/docs", seed_host="seed.com", same_domain=True)[0] == "expand")
check("subdomain allowed",     g.classify("https://docs.seed.com/x", seed_host="seed.com", same_domain=True)[0] != "skip")

print("== build_plan: caps ==")
txt = "\n".join(f"[p](https://arxiv.org/abs/{i})" for i in range(20))
plan = g.build_plan(txt, max_pages=5)
check("cap limits expand to 5", len(plan["expand"]) == 5)
check("capped flag set",        plan["capped"] is True)
check("expand_all keeps all 20", len(plan["expand_all"]) == 20)
plan2 = g.build_plan(txt, max_pages=999, hard_cap=10)
check("hard-cap ceiling = 10",  plan2["cap"] == 10 and len(plan2["expand"]) == 10)
plan3 = g.build_plan(txt, max_pages=50)
check("under cap -> not capped", plan3["capped"] is False and len(plan3["expand"]) == 20)

print(f"\nRESULT: {P} passed, {F} failed -> {'ALL PASS' if F == 0 else 'FAILURES'}")
sys.exit(0 if F == 0 else 1)
