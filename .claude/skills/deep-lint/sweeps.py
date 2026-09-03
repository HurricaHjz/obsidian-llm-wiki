#!/usr/bin/env python3
"""Rendering and narrative sweeps for deep-lint Step 1 (read-only).

Report-only by construction: this script prints to stdout and stderr and writes nothing.

Three sweeps over wiki pages, each with its own positive control on the same run:
  1. hard-wrap suspects — a prose line ending in a lowercase letter or a comma while the next
     line begins lowercase. Obsidian renders every newline as a hard break, so prose is one
     line per paragraph (CLAUDE.md line discipline). Non-rendered and non-prose lines are
     excluded: frontmatter, fenced code blocks, table rows, HTML-comment interiors, headings
     and list items (a heading renders, but it is not wrapped prose, so pairing it with the
     line beneath it manufactures suspects).
  2. raw `<tag>` tokens in rendered prose outside backticks and comments — Obsidian parses a
     bare angle-bracket token as HTML and hijacks or silently strips it. Headings and list
     items DO count here: they render, so a raw tag in one is a live defect.
  3. correction-narrative phrases in wiki/developments/ — those docs read forward-facing
     (CLAUDE.md 12), so a phrase that argues with earlier wording is a finding.

wiki/log.md is skipped throughout: it is append-only history, not maintained prose.

The controls are a synthetic page put through the SAME scan path as a real page, so they
prove the whole pipeline — line classification included — not just a regex: the control page
carries one genuine wrapped pair, one raw tag beside a backticked one, one fenced tag, one
heading trap and one list trap, and the run fails its premise unless exactly the genuine
cases come back. The narrative control is scanned SEPARATELY, on its own one-line page: a
user-supplied phrase carrying an angle-bracket token or a line break would otherwise land in
the shared control page and make the raw-tag or hard-wrap control fail a healthy run.

Usage (from the vault root):
  python3 .claude/skills/deep-lint/sweeps.py
  python3 .claude/skills/deep-lint/sweeps.py --vault <root> --format json
  python3 .claude/skills/deep-lint/sweeps.py --phrases "no longer,was removed"

Exit codes: 0 = the sweeps ran (findings or none); 2 = a probe premise failed.
A vault with no pages, no rendered line, an unreadable page or a control that does not fire is a
premise failure; an empty wiki/developments/ and zero findings are legitimate and say so.
"""

import argparse
import json
import os
import re
import sys

# The default correction-narrative phrases named in the deep-lint runbook, Step 1.
DEFAULT_PHRASES = ("owner revision", "no longer", "earlier wording", "was removed")
# Excerpt width for a narrative hit: enough to judge the sentence without dumping the page.
# Set by judgement, unmeasured.
EXCERPT = 110
# Fragment width shown either side of a suspected hard wrap. Set by judgement, unmeasured.
FRAGMENT = 40

FM_RE = re.compile(r"\A---\r?\n.*?\r?\n---\r?\n?", re.S)
TAG_RE = re.compile(r"<[A-Za-z][A-Za-z0-9-]*(?:\s[^>]*)?/?>")
LIST_RE = re.compile(r"^\s*([-*+]|\d+\.)\s")
HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s")
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
# A byte-order mark, written as an escape so the character never sits invisibly in shipped source.
BOM = "\ufeff"
# The one log file that is append-only history rather than maintained prose, addressed by PATH:
# skipping every file merely NAMED log.md would also skip a wiki page that happens to be called it.
LOG_REL = "wiki/log.md"

CONTROL_PAGE = """---
title: control page
---

## a heading that ends in lowercase
continues in lowercase prose beneath the heading.

- a list item ending in lowercase and
continuing beneath the item.

a sentence wrapped at a fixed column and
continues here in lowercase.

a safe `<code>` span beside a raw <tag> in prose.

```
<div>a fenced tag is not rendered prose</div>
```
"""


def classify(text):
    """Split a page into rendered lines and prose lines.

    Returns two equal-length lists plus the frontmatter's line count, so a reported line number
    is the one an editor jumps to. An entry is None where that line is not in the class.
    `rendered` drops frontmatter, fenced code, table rows and HTML-comment interiors.
    `prose` drops headings and list items on top of that.

    The state tests run innermost-first — comment, then fence — because a ``` line INSIDE an HTML
    comment must not toggle the fence. Testing the fence first desynchronises the rest of the page:
    every line after such a comment reads as fenced, and the sweeps then report a confident zero
    over prose they never looked at.
    """
    match = FM_RE.match(text)
    body = text[match.end():] if match else text
    offset = text[:match.end()].count("\n") if match else 0
    rendered, prose = [], []
    in_fence = False
    in_comment = False
    for line in body.split("\n"):
        stripped = line.strip()
        if in_comment:
            if "-->" in stripped:
                in_comment = False
            rendered.append(None)
            prose.append(None)
            continue
        if stripped.startswith("```"):
            in_fence = not in_fence
            rendered.append(None)
            prose.append(None)
            continue
        if in_fence:
            rendered.append(None)
            prose.append(None)
            continue
        if "<!--" in stripped and "-->" not in stripped:
            in_comment = True
            rendered.append(None)
            prose.append(None)
            continue
        if stripped.startswith("|"):                      # table row
            rendered.append(None)
            prose.append(None)
            continue
        visible = re.sub(r"<!--.*?-->", "", line)         # one-line comments
        rendered.append(visible)
        prose.append(None if (HEADING_RE.match(visible) or LIST_RE.match(visible)) else visible)
    return rendered, prose, offset


def hard_wraps(prose, offset=0):
    """Suspected mid-sentence hard wraps, plus the number of adjacent prose pairs examined."""
    hits, pairs = [], 0
    for i in range(len(prose) - 1):
        first, second = prose[i], prose[i + 1]
        if first is None or second is None:
            continue
        if not first.strip() or not second.strip():
            continue
        pairs += 1
        if re.search(r"[a-z,]$", first.rstrip()) and re.match(r"^[a-z]", second.lstrip()):
            hits.append({"line": offset + i + 1,
                         "first": first.rstrip()[-FRAGMENT:],
                         "second": second.lstrip()[:FRAGMENT]})
    return hits, pairs


def scan_text(text, is_dev, phrases):
    """Run all three sweeps over one page's text. Real pages and controls share this path."""
    rendered, prose, offset = classify(text)
    wraps, pairs = hard_wraps(prose, offset)
    tags, narrative = [], []
    for i, line in enumerate(rendered):
        if line is None:
            continue
        bare = INLINE_CODE_RE.sub(" ", line)
        for found in TAG_RE.finditer(bare):
            tags.append({"line": offset + i + 1, "tag": found.group(0)[:40]})
        if is_dev:
            low = bare.lower()
            for phrase in phrases:
                if phrase in low:
                    narrative.append({"line": offset + i + 1, "phrase": phrase,
                                      "excerpt": bare.strip()[:EXCERPT]})
    return {
        "wraps": wraps,
        "pairs": pairs,
        "rendered": sum(1 for line in rendered if line is not None),
        "tags": tags,
        "narrative": narrative,
    }


def run_controls(phrases):
    """Put the synthetic control pages through scan_text and check exactly the planted cases.

    Two pages, not one. The hard-wrap and raw-tag controls run over the FIXED control page, so a
    caller-supplied phrase can never change their expected counts; the narrative control runs over
    its own one-line page. Sharing one page made `--phrases "<retired>"` plant a second raw tag and
    fail the tag control on a run that was working perfectly.
    """
    fixed = scan_text(CONTROL_PAGE, False, phrases)
    narrative_page = f"a clause in a development doc that says {phrases[0]} in prose.\n"
    narrated = scan_text(narrative_page, True, phrases)
    return {
        "hardwrap": len(fixed["wraps"]) == 1,
        "raw_tag": len(fixed["tags"]) == 1,
        "narrative": len(narrated["narrative"]) >= 1,
        "pairs": fixed["pairs"],
        "detail": {"wraps": len(fixed["wraps"]), "tags": len(fixed["tags"]),
                   "narrative": len(narrated["narrative"])},
    }


def main():
    parser = argparse.ArgumentParser(
        description="Deep-lint rendering and narrative sweeps (read-only; prints, never writes).")
    parser.add_argument("--vault", default=".", help="vault root (default: the current directory)")
    parser.add_argument("--phrases", default=None,
                        help="comma-separated correction-narrative phrases (overrides the defaults)")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args()

    # A file name that is not valid UTF-8 arrives here as a surrogate; without this the first print
    # touching it aborts the whole report. Mangled beats missing, and it changes nothing otherwise.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")

    root = os.path.abspath(args.vault)
    wiki_dir = os.path.join(root, "wiki")
    if not os.path.isdir(wiki_dir):
        print(f"PROBE FAILED: no wiki directory under {root}", file=sys.stderr)
        return 2

    phrases = [p.strip().lower() for p in args.phrases.split(",") if p.strip()] if args.phrases \
        else list(DEFAULT_PHRASES)
    if not phrases:
        print("PROBE FAILED: --phrases resolved to an empty list", file=sys.stderr)
        return 2

    failures = []
    wrap_pages, tag_hits, narrative_hits = [], [], []
    pairs_total = lines_total = pages_scanned = dev_pages = 0

    for dirpath, dirnames, filenames in os.walk(wiki_dir):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            if rel == LOG_REL:
                continue
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except OSError as exc:
                # A page the sweep could not open is a hole in every count below, never a silent skip.
                failures.append(f"{rel} could not be read ({exc.__class__.__name__})")
                continue
            if text.startswith(BOM):
                text = text[1:]      # a mark in front of `---` would leave the frontmatter in scope
            is_dev = rel.startswith("wiki/developments/")
            found = scan_text(text, is_dev, phrases)
            pages_scanned += 1
            dev_pages += 1 if is_dev else 0
            pairs_total += found["pairs"]
            lines_total += found["rendered"]
            if found["wraps"]:
                wrap_pages.append({"path": rel, "count": len(found["wraps"]), "hits": found["wraps"]})
            for hit in found["tags"]:
                tag_hits.append({"path": rel, **hit})
            for hit in found["narrative"]:
                narrative_hits.append({"path": rel, **hit})

    controls = run_controls(phrases)
    if not controls["hardwrap"]:
        failures.append("the hard-wrap control did not return exactly its one planted suspect")
    if not controls["raw_tag"]:
        failures.append("the raw-tag control did not return exactly its one planted tag")
    if not controls["narrative"]:
        failures.append("the narrative-phrase control did not fire")
    if pages_scanned == 0:
        failures.append("no wiki page was scanned")
    if lines_total == 0:
        failures.append("no rendered line was examined — the sweep scanned nothing")

    result = {
        "vault": root,
        "pages_scanned": pages_scanned,
        "developments_pages": dev_pages,
        "rendered_lines": lines_total,
        "prose_pairs": pairs_total,
        "phrases": phrases,
        "hardwrap": {"pages": wrap_pages, "hits": sum(p["count"] for p in wrap_pages)},
        "raw_tags": {"hits": tag_hits},
        "narrative": {"hits": narrative_hits},
        "controls": controls,
        "probe_failures": failures,
    }

    if args.format == "json":
        json.dump(result, sys.stdout, indent=1, sort_keys=True)
        sys.stdout.write("\n")
        for note in failures:
            print(f"PROBE FAILED: {note}", file=sys.stderr)
        return 2 if failures else 0

    print(f"sweeps: vault={root} pages={pages_scanned} (log.md skipped) "
          f"rendered lines={lines_total} phrases={len(phrases)} format=text   "
          f"(nonzero counts = probe ran)")

    print("--- HARD WRAP ---")
    print(f"hardwrap: {sum(p['count'] for p in wrap_pages)} suspects on {len(wrap_pages)} pages · "
          f"{pairs_total} adjacent prose pairs scanned")
    for page in wrap_pages:
        print(f"  {page['path']} ({page['count']})")
        for hit in page["hits"]:
            print(f"    L{hit['line']}: ...{hit['first']}  ||  {hit['second']}...")
    print(f"hardwrap-control: {'fired' if controls['hardwrap'] else 'DID NOT FIRE'} "
          f"(synthetic page: 1 wrapped pair caught, heading and list traps not)")
    if pairs_total == 0:
        print("note: no adjacent prose pair exists in this vault, so the sweep had nothing to "
              "judge — the control above is what proves the probe works")

    print("--- RAW TAGS ---")
    print(f"raw tags in rendered prose: {len(tag_hits)}")
    for hit in tag_hits:
        print(f"  {hit['path']}:{hit['line']} {hit['tag']}")
    print(f"tag-control: {'fired' if controls['raw_tag'] else 'DID NOT FIRE'} "
          f"(synthetic page: raw tag caught, backticked and fenced tags not)")

    print("--- CORRECTION NARRATIVE (wiki/developments/) ---")
    print(f"narrative phrases: {len(narrative_hits)} hits over {dev_pages} development pages "
          f"(phrases: {', '.join(phrases)})")
    for hit in narrative_hits:
        print(f"  {hit['path']}:{hit['line']} [{hit['phrase']}] {hit['excerpt']}")
    print(f"narrative-control: {'fired' if controls['narrative'] else 'DID NOT FIRE'}")
    if dev_pages == 0:
        print("note: this vault holds no wiki/developments/ page, so the narrative sweep had "
              "nothing to scan — the control above is what proves the probe works")

    for note in failures:
        print(f"PROBE FAILED: {note}")
    return 2 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
