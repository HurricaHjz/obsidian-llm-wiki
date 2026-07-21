#!/usr/bin/env python3
"""Deterministic wikilink + embed checker for the wiki/ layer.

Shared by `lint` (routine scan) and `deep-lint` (structural pass) so every run applies
identical rules instead of re-deriving an ad-hoc scanner. Rules encoded here:
  - scans wiki/**/*.md; wiki/log.md is EXCLUDED as a link source (append-only history);
  - fenced code blocks, inline code spans and HTML comments are stripped before extraction
    (documentation examples like `[[wikilink]]` are not links);
  - page links resolve against: wiki page stems -> frontmatter aliases -> vault-relative
    paths (with or without .md), so [[Claude Model Family|Claude]], [[CLAUDE#h]] and
    [[assets/x.md]] all resolve correctly;
  - media embeds ![[name.ext]] resolve against assets/ (the attachment folder) and are
    reported separately as dead embeds when missing — they are checked, not skipped;
  - prints scan totals as its own positive control (a zero-findings run with zero links
    scanned is a broken probe, per CLAUDE.md §11).

Usage (from the vault root):
  python3 .claude/skills/lint/check-links.py [vault-root]   # exit 0 clean, 1 findings
"""
import os
import re
import sys
import glob

root = sys.argv[1] if len(sys.argv) > 1 else "."
wiki = os.path.join(root, "wiki")

MEDIA_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf", ".mp3", ".wav", ".mp4", ".mov"}

files = sorted(glob.glob(os.path.join(wiki, "**", "*.md"), recursive=True))
stems = {os.path.splitext(os.path.basename(p))[0] for p in files}

aliases = {}
for p in files:
    head = open(p, encoding="utf-8").read(2500)
    fm = re.match(r"\A---\n(.*?)\n---", head, re.S)
    if not fm:
        continue
    block = fm.group(1)
    m = re.search(r"^aliases:\s*\[([^\]]*)\]", block, re.M)
    vals = []
    if m:
        vals = m.group(1).split(",")
    else:
        m2 = re.search(r"^aliases:\s*\n((?:\s*-\s*.+\n?)+)", block, re.M)
        if m2:
            vals = re.findall(r"-\s*(.+)", m2.group(1))
    for a in vals:
        a = a.strip().strip("\"'")
        if a:
            aliases[a] = p


def strip_noise(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)      # fenced code blocks
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)     # HTML comments
    text = re.sub(r"`[^`\n]*`", " ", text)                   # inline code spans
    return text


def resolves(target):
    t = target.strip()
    if not t or t.startswith("#"):
        return True                                          # self-heading link
    t = t.split("#", 1)[0].strip()                           # drop heading part
    if t in stems or t in aliases:
        return True
    if "/" in t or t.endswith(".md"):                        # vault-relative path form
        for cand in (t, t + ".md"):
            if os.path.exists(os.path.join(root, cand)):
                return True
    if os.path.exists(os.path.join(root, t + ".md")):        # root doc, e.g. [[CLAUDE]]
        return True
    return False


dead_links, dead_embeds = [], []
links_checked = embeds_checked = 0
for p in files:
    if os.path.basename(p) == "log.md":
        continue
    body = strip_noise(open(p, encoding="utf-8").read())
    for is_embed, target in re.findall(r"(!?)\[\[([^\]|]+?)(?:\|[^\]]*)?\]\]", body):
        target = target.strip().rstrip("\\")   # [[page\|alias]] table-escaped pipes leave a trailing backslash
        ext = os.path.splitext(target.split("#", 1)[0])[1].lower()
        rel = os.path.relpath(p, root)
        if is_embed and ext in MEDIA_EXT:
            embeds_checked += 1
            cands = [os.path.join(root, "assets", target), os.path.join(root, target)]
            if not any(os.path.exists(c) for c in cands):
                dead_embeds.append(f"{rel} -> ![[{target}]]")
        else:
            links_checked += 1
            if not resolves(target):
                dead_links.append(f"{rel} -> [[{target}]]")

print(f"SCANNED: {len(files)} pages | {links_checked} page links | {embeds_checked} media embeds "
      f"| {len(stems)} stems | {len(aliases)} aliases   (nonzero totals = probe ran)")
print(f"DEAD LINKS: {len(dead_links)}")
for d in dead_links:
    print("  " + d)
print(f"DEAD EMBEDS: {len(dead_embeds)}")
for d in dead_embeds:
    print("  " + d)
sys.exit(1 if (dead_links or dead_embeds) else 0)
