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

print("== extract_links: relative resolution ==")
rel_txt = ("go to [setup](../tutorials/setup/) and [login](../guides/login/#ssh), "
           "see [anchor](#section), [mail](mailto:a@b.com), [abs](https://arxiv.org/abs/9)")
rel = g.extract_links(rel_txt, base_url="https://docs.example.ac.uk/user-documentation/getting_started/")
check("resolves ../ against base", "https://docs.example.ac.uk/user-documentation/tutorials/setup/" in rel)
check("strips fragment on relative", "https://docs.example.ac.uk/user-documentation/guides/login/" in rel
      and not any("#ssh" in u for u in rel))
check("never resolves pure anchor", not any(u.endswith("#section") or "getting_started/#" in u for u in rel))
check("never resolves mailto", not any("a@b.com" in u for u in rel))
check("absolute still found alongside", "https://arxiv.org/abs/9" in rel)
check("no base -> relatives ignored", g.extract_links(rel_txt) == ["https://arxiv.org/abs/9"])

print("== extract_links: forge repo-root base (known-issues 2026-08-25) ==")
gh = g.extract_links("[c](./docs/contributing.md) and [i](docs/install.md)",
                     base_url="https://github.com/openai/codex")
check("github repo-root ./link keeps repo segment",
      "https://github.com/openai/codex/blob/HEAD/docs/contributing.md" in gh)
check("github repo-root bare relative keeps repo segment",
      "https://github.com/openai/codex/blob/HEAD/docs/install.md" in gh)
gl = g.extract_links("[d](doc/api/index.md)", base_url="https://gitlab.com/gitlab-org/gitlab/")
check("gitlab repo-root (trailing slash) joins under blob/HEAD",
      "https://gitlab.com/gitlab-org/gitlab/blob/HEAD/doc/api/index.md" in gl)
blob = g.extract_links("[b](./other.md)", base_url="https://github.com/o/r/blob/main/docs/a.md")
check("blob file base keeps sibling-join semantics",
      "https://github.com/o/r/blob/main/docs/other.md" in blob)
ext = g.extract_links("[n](library/re.html)", base_url="https://docs.python.org/3")
check("extensionless non-forge base joins as directory",
      "https://docs.python.org/3/library/re.html" in ext)
fil = g.extract_links("[n](./other.html)", base_url="https://ex.com/guide/page.html")
check("file-like base keeps standard urljoin semantics",
      "https://ex.com/guide/other.html" in fil)
plan_gh = g.build_plan("[c](./docs/contributing.md)", seed_url="https://github.com/openai/codex")
check("plan-level: repo-root seed resolves and expands correctly",
      plan_gh["found"] == 1 and plan_gh["expand"]
      and plan_gh["expand"][0][0] == "https://github.com/openai/codex/blob/HEAD/docs/contributing.md")

print("== build_plan: zero-links guard ==")
plan_w = g.build_plan("only [relative](../x/) links here")          # links present, no base
check("warning fires on 0-found with links", "warning" in plan_w and plan_w["found"] == 0)
plan_ok = g.build_plan("[p](https://arxiv.org/abs/1)")
check("no warning when links extracted", "warning" not in plan_ok)
plan_empty = g.build_plan("plain prose, no links at all")
check("no warning on genuinely linkless text", "warning" not in plan_empty)
plan_rel = g.build_plan("[setup](../tutorials/setup/)", seed_url="https://docs.example.ac.uk/a/b/")
check("relative resolved via seed_url in plan", plan_rel["found"] == 1 and "warning" not in plan_rel)

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

print("== classify: docs-host skip-path demotion (№49 P7-D2) ==")
check("commercial /login stays skip",
      g.classify("https://site.com/login", seed_host="site.com")[0] == "skip")
check("own docs-host login guide -> maybe",
      g.classify("https://docs.site.com/guides/login/", seed_host="docs.site.com")[0] == "maybe")
check("docs subdomain of seed -> maybe",
      g.classify("https://docs.seed.io/terms/", seed_host="seed.io")[0] == "maybe")
check("foreign docs host /login stays skip",
      g.classify("https://docs.other.com/login", seed_host="docs.site.com")[0] == "skip")
check("no seed context -> /login stays skip",
      g.classify("https://docs.site.com/guides/login/")[0] == "skip")
check("social host never demoted",
      g.classify("https://twitter.com/login", seed_host="twitter.com")[0] == "skip")
check("github.com own /login stays skip (auth wall, not docs)",
      g.classify("https://github.com/login", seed_host="github.com")[0] == "skip")
check("readthedocs own skip-path -> maybe",
      g.classify("https://proj.readthedocs.io/en/latest/tags/", seed_host="proj.readthedocs.io")[0] == "maybe")

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
plan4 = g.build_plan(txt, max_pages=500, hard_cap=500)
check("hard-cap cannot be raised past 100", plan4["cap"] == 100)

print(f"\nRESULT: {P} passed, {F} failed -> {'ALL PASS' if F == 0 else 'FAILURES'}")
sys.exit(0 if F == 0 else 1)
