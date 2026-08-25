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
from urllib.parse import urlparse, urljoin

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
DOCS_HOST   = re.compile(r'(^docs\.|\.readthedocs\.|[\w.-]+\.github\.io$)', re.I)  # genuinely
# documentation-shaped hosts only — NOT github.com/gitlab/hf, whose /login is a real auth wall
ASSET_EXT   = re.compile(r'\.(png|jpe?g|gif|webp|svg|ico|css|js|woff2?|ttf)(\?|$)', re.I)
SHARE       = re.compile(r'(utm_[a-z]+=|/intent/|sharer|/share\b)', re.I)
FORGE_REPO_ROOT = re.compile(r'/[^/]+/[^/]+/?')  # exactly /owner/repo — a forge repo-root path


def normalise_base(url):
    """Join-base normalisation for relative links (known-issues entry 2026-08-25).
    Bare urljoin against a slash-less base drops the base's last path segment, so a
    github.com/gitlab.com REPO-ROOT seed mis-joined README links into the owner
    namespace (./docs/x.md → github.com/owner/docs/x.md). Probed 2026-08-25: that
    bare joined path dead-ends (GitHub 404, GitLab 403) while <repo>/blob/HEAD/<path>
    resolves on both forges — so repo-root seeds join under <seed>/blob/HEAD/.
    Any other extensionless, slash-less tail joins as a directory (<seed>/, matching
    the server's own trailing-slash redirect); a file-like base (dot in the last
    segment) keeps standard urljoin semantics. Nested GitLab groups (3+ segments)
    fall to the directory rule — accepted residual, no probe evidence yet."""
    p = urlparse(url)
    if not url or p.query or p.fragment:
        return url
    host = (p.hostname or "").lower()
    if host in ("github.com", "gitlab.com") and FORGE_REPO_ROOT.fullmatch(p.path):
        return url.rstrip("/") + "/blob/HEAD/"
    last = p.path.rsplit("/", 1)[-1]
    if p.path and not p.path.endswith("/") and "." not in last:
        return url + "/"
    return url


def extract_links(text, base_url=""):
    """All http(s) links from Markdown `](url)` and bare URLs, de-duped, order-preserved.
    Relative Markdown targets (MkDocs-style docs sites) are resolved against base_url when
    one is given — the base first normalised via normalise_base(), so repo-root and
    extensionless seeds join correctly; anchors and non-http schemes are never resolved."""
    urls = []
    base = normalise_base(base_url) if base_url else ""
    for m in re.finditer(r'\]\(([^)\s]+)\)', text):
        u = m.group(1)
        if u.startswith(('http://', 'https://')):
            urls.append(u)
        elif base and not u.startswith('#') and not urlparse(u).scheme:
            urls.append(urljoin(base, u).split('#', 1)[0])
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
    < same-domain filter < content heuristics < default(maybe).
    №49 P7-D2: a SKIP_PATH hit on the seed's OWN documentation-shaped host (DOCS_HOST
    match) demotes to `maybe` instead of `skip` — a docs login GUIDE reaches the owner,
    a commercial login WALL stays skipped. Social hosts always skip."""
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
    if SKIP_HOST.search(host):
        return ("skip", "nav/social/boilerplate")
    if SKIP_PATH.search(url):
        if (seed_host and (host == seed_host or host.endswith("." + seed_host))
                and DOCS_HOST.search(host)):
            return ("maybe", "skip-path on own docs host — confirm with user")
        return ("skip", "nav/social/boilerplate")
    if same_domain and seed_host and host and host != seed_host and not host.endswith("." + seed_host):
        return ("skip", "off-domain (--same-domain)")
    if EXPAND_HOST.search(host) or EXPAND_PATH.search(url):
        return ("expand", "content (doc/paper/repo)")
    return ("maybe", "unclassified — confirm with user")


def build_plan(text, seed_url="", max_pages=10, hard_cap=100, same_domain=False, include=None, exclude=None):
    seed_host = (urlparse(seed_url).hostname or "").lower() or None
    hard_cap = min(hard_cap, 100)  # the ceiling is non-overridable at every layer
    expand, maybe, skip = [], [], []
    for u in extract_links(text, seed_url):
        v, r = classify(u, seed_host, same_domain, include, exclude)
        (expand if v == "expand" else maybe if v == "maybe" else skip).append((u, r))
    cap = max(0, min(max_pages, hard_cap))
    plan = {"seed": seed_url, "found": len(expand) + len(maybe) + len(skip), "cap": cap,
            "capped": len(expand) > cap, "expand": expand[:cap], "expand_all": expand,
            "maybe": maybe, "skip": skip}
    if plan["found"] == 0 and re.search(r'\]\([^)]+\)', text):
        plan["warning"] = ("0 links extracted yet the body contains Markdown link syntax — "
                           "likely relative targets with no --seed-url base; do not trust this "
                           "empty plan without checking")
    return plan


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
    if plan.get("warning"):
        print(f"WARNING: {plan['warning']}")
    print(f"found {plan['found']} links | will fetch {len(plan['expand'])} (cap {plan['cap']}) | "
          f"ask {len(plan['maybe'])} | skip {len(plan['skip'])}")
    print("\nWILL FETCH:");  [print(f"  + {u}   [{r}]") for u, r in plan["expand"]]
    if plan["capped"]:
        hint = ("raise --max-pages to include" if plan["cap"] < 100
                else "above the 100-page ceiling — cannot be raised")
        print(f"  ... +{len(plan['expand_all']) - plan['cap']} more above the cap ({hint})")
    print("\nASK FIRST:");   [print(f"  ? {u}   [{r}]") for u, r in plan["maybe"][:25]]
    print("\nSKIPPED:");     [print(f"  - {u}   [{r}]") for u, r in plan["skip"][:25]]


if __name__ == "__main__":
    main()
