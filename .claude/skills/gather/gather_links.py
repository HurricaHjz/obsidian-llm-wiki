#!/usr/bin/env python3
"""gather_links.py — the deterministic "consistency engine" for the /gather skill.

Given fetched seed text (Markdown/HTML) + flags, it extracts links, classifies each as
expand / maybe / skip using FIXED heuristics (so every run behaves the same), applies the
page cap, and prints a capture PLAN that the agent previews before fetching anything.

Read-only. No network. Pure stdlib. Run:
    python3 gather_links.py <seed.md> --seed-url <url> [--max-pages N] [--same-domain] \
            [--include a,b] [--exclude c,d] [--json]
"""
import re, sys, argparse, json
from urllib.parse import urlparse

# --- heuristics (#3): what to expand (real content) vs skip (navigation/noise) ---------
EXPAND_HOST = re.compile(r'(arxiv\.org|github\.com|[\w.-]+\.github\.io|gitlab\.com|huggingface\.co|'
                         r'openreview\.net|doi\.org|aclanthology\.org|paperswithcode\.com|'
                         r'[\w.-]*readthedocs\.|^docs\.)', re.I)
EXPAND_PATH = re.compile(r'(/papers?\b|/docs?\b|/blog\b|/research\b|/abs/|\.pdf(\?|$)|/readme\b|'
                         r'/wiki/|/datasets?\b|/benchmarks?\b|/proceedings\b)', re.I)
SKIP_HOST   = re.compile(r'(twitter\.com|x\.com|facebook\.com|linkedin\.com|instagram\.com|t\.me|'
                         r'tiktok\.com|pinterest\.|weibo\.)', re.I)
SKIP_PATH   = re.compile(r'(/login|/sign[_-]?in|/sign[_-]?up|/register|/subscribe|/account|/cart|'
                         r'/checkout|/privacy|/terms|/cookie|/contact\b|/tags?/|/categor|/author/|'
                         r'/feed\b|/rss\b|/sitemap)', re.I)
SKIP_SCHEME = re.compile(r'^(mailto:|javascript:|tel:|#)', re.I)
ASSET_EXT   = re.compile(r'\.(png|jpe?g|gif|webp|svg|ico|css|js|woff2?|ttf)(\?|$)', re.I)
SHARE       = re.compile(r'(utm_[a-z]+=|/intent/|sharer|/share\b)', re.I)


def extract_links(text):
    """All http(s) links from Markdown `](url)` and bare URLs, de-duped, order-preserved."""
    urls = []
    for m in re.finditer(r'\]\((https?://[^)\s]+)\)', text):
        urls.append(m.group(1))
    for m in re.finditer(r'(?<![("\w<])(https?://[^\s)\]<>"]+)', text):
        urls.append(m.group(1))
    seen, out = set(), []
    for u in urls:
        u = u.rstrip('.,;)]')
        if u and u not in seen:
            seen.add(u); out.append(u)
    return out


def classify(url, seed_host=None, same_domain=False, include=None, exclude=None):
    """Return (verdict, reason) where verdict in {expand, maybe, skip}.
    Precedence: scheme < explicit exclude < explicit include < assets/share < nav/social
    < same-domain filter < content heuristics < default(maybe)."""
    include = include or []
    exclude = exclude or []
    if SKIP_SCHEME.search(url):
        return ("skip", "non-http link")
    if any(p and p in url for p in exclude):
        return ("skip", "--exclude match")
    if any(p and p in url for p in include):
        return ("expand", "--include match")
    if ASSET_EXT.search(url):
        return ("skip", "asset/static file")
    if SHARE.search(url):
        return ("skip", "share/tracking link")
    host = (urlparse(url).hostname or "").lower()
    if SKIP_HOST.search(host) or SKIP_PATH.search(url):
        return ("skip", "nav/social/boilerplate")
    if same_domain and seed_host and host and host != seed_host and not host.endswith("." + seed_host):
        return ("skip", "off-domain (--same-domain)")
    if EXPAND_HOST.search(host) or EXPAND_PATH.search(url):
        return ("expand", "content (doc/paper/repo)")
    return ("maybe", "unclassified — confirm with user")


def build_plan(text, seed_url="", max_pages=10, hard_cap=100, same_domain=False, include=None, exclude=None):
    seed_host = (urlparse(seed_url).hostname or "").lower() or None
    expand, maybe, skip = [], [], []
    for u in extract_links(text):
        v, r = classify(u, seed_host, same_domain, include, exclude)
        (expand if v == "expand" else maybe if v == "maybe" else skip).append((u, r))
    cap = max(0, min(max_pages, hard_cap))
    return {"seed": seed_url, "found": len(expand) + len(maybe) + len(skip), "cap": cap,
            "capped": len(expand) > cap, "expand": expand[:cap], "expand_all": expand,
            "maybe": maybe, "skip": skip}


def main():
    ap = argparse.ArgumentParser(description="Produce a /gather capture plan (read-only, no network).")
    ap.add_argument("file", nargs="?", help="seed markdown/text file (default: stdin)")
    ap.add_argument("--seed-url", default="")
    ap.add_argument("--max-pages", type=int, default=10)
    ap.add_argument("--hard-cap", type=int, default=100, help="non-overridable ceiling")
    ap.add_argument("--same-domain", action="store_true")
    ap.add_argument("--include", default="")
    ap.add_argument("--exclude", default="")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    text = open(a.file, encoding="utf-8-sig").read() if a.file else sys.stdin.read()
    plan = build_plan(text, a.seed_url, a.max_pages, a.hard_cap, a.same_domain,
                      [x for x in a.include.split(",") if x], [x for x in a.exclude.split(",") if x])
    if a.json:
        print(json.dumps(plan, indent=2, ensure_ascii=False)); return
    print(f"CAPTURE PLAN — seed: {plan['seed'] or '(stdin)'}")
    print(f"found {plan['found']} links | will fetch {len(plan['expand'])} (cap {plan['cap']}) | "
          f"ask {len(plan['maybe'])} | skip {len(plan['skip'])}")
    print("\nWILL FETCH:");  [print(f"  + {u}   [{r}]") for u, r in plan["expand"]]
    if plan["capped"]:
        print(f"  ... +{len(plan['expand_all']) - plan['cap']} more above the cap (raise --max-pages to include)")
    print("\nASK FIRST:");   [print(f"  ? {u}   [{r}]") for u, r in plan["maybe"][:25]]
    print("\nSKIPPED:");     [print(f"  - {u}   [{r}]") for u, r in plan["skip"][:25]]


if __name__ == "__main__":
    main()
