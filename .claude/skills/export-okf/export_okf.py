#!/usr/bin/env python3
"""export-okf — build a conformant Open Knowledge Format (OKF v0.1) bundle from wiki/.

Deterministic and read-only with respect to the vault: it NEVER mutates wiki/.
It reads wiki/<type>/*.md, derives the OKF-recommended frontmatter, converts
[[wikilinks]] to bundle-relative markdown links, copies referenced media, and
generates per-directory index.md (§6) + a root log.md (§7), then validates (§9).

Usage:
  export_okf.py [--wiki WIKI] [--assets ASSETS] [--out OUT] [--quiet]
Defaults are derived from the script location (vault root = 3 levels up).
"""
import os, re, sys, glob, shutil, argparse

WIKILINK = re.compile(r'(?<!\!)\[\[([^\]]+)\]\]')
EMBED = re.compile(r'!\[\[([^\]]+)\]\]')
IMG_RE = re.compile(r'\.(png|jpe?g|gif|webp|svg)$', re.I)
RESERVED = {"index", "log"}  # reserved basenames (regenerated, not copied as concepts)


# ---------- frontmatter helpers (dependency-free; preserve original block) ----------
def split_frontmatter(text):
    """Return (frontmatter_str_or_None, body)."""
    if text.startswith("---\n") or text.startswith("---\r\n"):
        m = re.search(r'\n---\s*\n', text)
        if m:
            start = text.index("\n") + 1
            return text[start:m.start()], text[m.end():]
    return None, text


def fm_get(fm, key):
    if not fm:
        return None
    m = re.search(r'(?m)^%s:[ \t]*(.*)$' % re.escape(key), fm)
    return m.group(1).strip() if m else None


def fm_has(fm, key):
    return bool(fm) and re.search(r'(?m)^%s:[ \t]*' % re.escape(key), fm) is not None


def unquote(v):
    return v.strip().strip('"').strip("'").strip() if v else v


def clean_desc(s):
    """One-line, plain-text description: strip wikilinks/markdown/quotes/newlines."""
    s = re.sub(r'\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]', lambda m: m.group(2) or m.group(1), s)
    s = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', s)        # md links -> text
    s = s.replace("`", "").replace('"', "'")
    s = re.sub(r'\s+', ' ', s).strip()
    return s


# ---------- load ----------
def load_pages(wiki):
    pages = {}
    for ab in sorted(glob.glob(os.path.join(wiki, "**", "*.md"), recursive=True)):
        rel = "/" + os.path.relpath(ab, wiki).replace(os.sep, "/")
        base = os.path.splitext(os.path.basename(ab))[0]
        text = open(ab, encoding="utf-8", errors="replace").read()
        fm, body = split_frontmatter(text)
        reserved = base in RESERVED and rel.count("/") == 1  # /index.md or /log.md at root
        pages[base] = dict(ab=ab, rel=rel, base=base, reserved=reserved,
                           type=fm_get(fm, "type"), title=unquote(fm_get(fm, "title")) or base,
                           fm=fm, body=body)
    return pages


def load_index_desc(wiki):
    desc = {}
    p = os.path.join(wiki, "index.md")
    if not os.path.exists(p):
        return desc
    for line in open(p, encoding="utf-8", errors="replace"):
        m = re.match(r'^\s*-\s*\[\[([^\]|#]+)(?:\|[^\]]*)?\]\]\s*(.*)$', line)
        if not m:
            continue
        rest = m.group(2)
        rest = re.sub(r'^\s*[—-]\s*', '', rest)
        rest = re.sub(r'^\s*[📄📝]\s*\*[a-z]+\*\s*[—-]\s*', '', rest)
        desc[m.group(1).strip()] = clean_desc(rest)
    return desc


def derive_description(page, index_desc):
    d = index_desc.get(page["base"])
    if d:
        return d
    for raw in page["body"].splitlines():
        line = raw.strip()
        if not line or line[0] in "#>|!*-" or line.startswith("---"):
            continue
        sent = re.split(r'(?<=[.!?])\s', clean_desc(line))[0]
        if sent:
            return sent
    return page["title"]


# ---------- transforms ----------
def transform_frontmatter(page, description, warn):
    fm = page["fm"] or ""
    lines = fm.splitlines()
    if not fm_has(fm, "type"):
        lines.insert(0, "type: note")
        warn.append("notype:" + page["base"])
    if not fm_has(fm, "description"):
        lines.append('description: "%s"' % description)
    if not fm_has(fm, "resource"):
        res = fm_get(fm, "source_url")
        if not res:
            src = fm_get(fm, "sources")
            if src:
                mm = re.search(r'[^"\[\],\s][^"\[\],]*', src)
                res = mm.group(0) if mm else None
        if res:
            lines.append("resource: %s" % unquote(res))
    if not fm_has(fm, "timestamp"):
        ts = unquote(fm_get(fm, "updated")) or unquote(fm_get(fm, "created"))
        if ts and re.match(r'^\d{4}-\d{2}-\d{2}$', ts):
            lines.append("timestamp: %sT00:00:00Z" % ts)
    return "\n".join(lines)


def convert_links(body, pages, assets_ref, warn):
    def repl_embed(m):
        target = m.group(1).split("|")[0].strip()
        fname = os.path.basename(target)
        if IMG_RE.search(fname):
            assets_ref.add(fname)
            return "![](/assets/%s)" % fname
        b = os.path.splitext(fname)[0]
        if b in pages:
            return "[%s](%s)" % (pages[b]["title"], pages[b]["rel"])
        warn.append("embed:" + target)
        return fname

    def repl_link(m):
        inner = m.group(1)
        namepart, alias = (inner.split("|", 1) + [None])[:2]
        anchor = None
        if "#" in namepart:
            namepart, anchor = namepart.split("#", 1)
        base = os.path.splitext(namepart.strip())[0]
        disp = (alias.strip() if alias else namepart.strip())
        if base in pages:
            url = pages[base]["rel"]
            if anchor:
                url += "#" + re.sub(r'[^a-z0-9]+', '-', anchor.strip().lower()).strip('-')
            return "[%s](%s)" % (disp, url)
        warn.append("link:" + inner)
        return disp

    # protect code (fenced + inline) so example wikilinks inside code are not rewritten
    stash = []
    def _stash(m):
        stash.append(m.group(0))
        return "\x00%d\x00" % (len(stash) - 1)
    protected = re.sub(r'```.*?```', _stash, body, flags=re.S)
    protected = re.sub(r'`[^`\n]*`', _stash, protected)
    converted = WIKILINK.sub(repl_link, EMBED.sub(repl_embed, protected))
    return re.sub(r'\x00(\d+)\x00', lambda m: stash[int(m.group(1))], converted)


# ---------- index (§6) & log (§7) ----------
def write_indexes(out, pages):
    by_dir = {}
    for p in pages.values():
        if p["reserved"]:
            continue
        d = os.path.dirname(p["rel"])  # "/concepts"
        by_dir.setdefault(d, []).append(p)
    # per-directory index.md
    for d, items in by_dir.items():
        if d in ("", "/"):
            continue
        heading = d.strip("/").split("/")[-1]
        lines = ["# %s\n" % heading]
        for p in sorted(items, key=lambda x: x["title"].lower()):
            lines.append("* [%s](%s) - %s" % (p["title"], p["rel"], p["_desc"]))
        _write(os.path.join(out, d.strip("/"), "index.md"), "\n".join(lines) + "\n")
    # root index.md (progressive disclosure: list sub-bundles)
    root = ["# Knowledge Bundle\n"]
    for d in sorted(by_dir):
        if d in ("", "/"):
            continue
        name = d.strip("/").split("/")[-1]
        root.append("* [%s](%s/index.md) - %d concepts" % (name, d, len(by_dir[d])))
    _write(os.path.join(out, "index.md"), "\n".join(root) + "\n")
    return by_dir


def write_log(out, wiki):
    src = os.path.join(wiki, "log.md")
    if not os.path.exists(src):
        return False
    entries = []  # (date, action, title)
    for line in open(src, encoding="utf-8", errors="replace"):
        m = re.match(r'^##\s*\[(\d{4}-\d{2}-\d{2})\]\s*([^|]+?)\s*\|\s*(.+?)\s*$', line)
        if m:
            entries.append((m.group(1), m.group(2).strip(), m.group(3).strip()))
    if not entries:
        return False
    from collections import OrderedDict
    bydate = OrderedDict()
    for date, action, title in entries:
        bydate.setdefault(date, []).append((action, title))
    out_lines = ["# Update Log\n"]
    for date in sorted(bydate, reverse=True):  # newest first
        out_lines.append("## %s" % date)
        for action, title in bydate[date]:
            out_lines.append("* **%s**: %s" % (action, clean_desc(title)))
        out_lines.append("")
    _write(os.path.join(out, "log.md"), "\n".join(out_lines).rstrip() + "\n")
    return True


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)


# ---------- validation (§9) ----------
def validate(out):
    issues = []
    for ab in glob.glob(os.path.join(out, "**", "*.md"), recursive=True):
        rel = os.path.relpath(ab, out)
        base = os.path.splitext(os.path.basename(ab))[0]
        text = open(ab, encoding="utf-8", errors="replace").read()
        if base == "index" :
            if not re.search(r'(?m)^#\s', text):
                issues.append("index missing heading: " + rel)
            continue
        if base == "log":
            for ln in text.splitlines():
                if ln.startswith("## ") and not re.match(r'^##\s+\d{4}-\d{2}-\d{2}\s*$', ln):
                    issues.append("log non-ISO date heading in %s: %r" % (rel, ln))
            continue
        fm, _ = split_frontmatter(text)
        if fm is None:
            issues.append("no frontmatter: " + rel)
        elif not fm_get(fm, "type"):
            issues.append("missing/empty type: " + rel)
    return issues


# ---------- main ----------
def export(wiki, assets, out, quiet=False):
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out, exist_ok=True)
    pages = load_pages(wiki)
    index_desc = load_index_desc(wiki)
    warn, assets_ref = [], set()
    n_concepts = 0
    for p in pages.values():
        if p["reserved"]:
            continue
        p["_desc"] = derive_description(p, index_desc)
        new_fm = transform_frontmatter(p, p["_desc"], warn)
        new_body = convert_links(p["body"], pages, assets_ref, warn)
        _write(os.path.join(out, p["rel"].lstrip("/")),
               "---\n" + new_fm.rstrip("\n") + "\n---\n" + new_body)
        n_concepts += 1
    by_dir = write_indexes(out, pages)
    has_log = write_log(out, wiki)
    # copy referenced media
    n_assets = 0
    if assets and os.path.isdir(assets):
        for fn in sorted(assets_ref):
            srcf = os.path.join(assets, fn)
            if os.path.exists(srcf):
                _write_copy(srcf, os.path.join(out, "assets", fn)); n_assets += 1
            else:
                warn.append("asset-missing:" + fn)
    issues = validate(out)
    links = sum(1 for w in warn if w.startswith("link:") or w.startswith("embed:"))
    summary = dict(concepts=n_concepts, dirs=len([d for d in by_dir if d not in ("", "/")]),
                   assets_copied=n_assets, log=has_log,
                   broken_links=links, warnings=len(warn), conformance_issues=len(issues))
    if not quiet:
        print("OKF export → %s" % out)
        for k, v in summary.items():
            print("  %-20s %s" % (k, v))
        if issues:
            print("  CONFORMANCE ISSUES:")
            for i in issues[:20]:
                print("    -", i)
        print("  RESULT:", "CONFORMANT ✓" if not issues else "NON-CONFORMANT ✗")
    return summary, issues, warn


def _write_copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def _defaults():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", "..", ".."))
    return os.path.join(root, "wiki"), os.path.join(root, "assets"), os.path.join(root, "okf-export")


def main():
    dw, da, do = _defaults()
    ap = argparse.ArgumentParser()
    ap.add_argument("--wiki", default=dw)
    ap.add_argument("--assets", default=da)
    ap.add_argument("--out", default=do)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    _, issues, _ = export(a.wiki, a.assets, a.out, a.quiet)
    sys.exit(1 if issues else 0)


if __name__ == "__main__":
    main()
