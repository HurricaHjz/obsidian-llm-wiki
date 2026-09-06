#!/usr/bin/env python3
"""render-rubric.py — render the judge's rubric with the live style definition (the style re-run kit).

Fills the kit's rubric template (rubric.md beside this script, or --template) with the style's name
and its `Test:` clause, read from the vault's CUSTOMISATION-definitions.md and then CUSTOMISATION.md
(a style's block lives in one of the two), so the rubric never goes stale against the definition the
anchor injects. The Test is taken as the anchor takes it: the clause after `Test:` to the end of the
block, whitespace collapsed. Prints the rendered rubric to stdout; with --out DIR writes
<dir>/rubric.md and prints the one Test line it embedded instead. A missing template, definition or
Test, or a placeholder left unrendered, prints PROBE FAILED and exits 2.

  render-rubric.py [--style NAME] [--vault DIR] [--template FILE] [--out DIR]
"""
import argparse
import datetime
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def style_test(vault, style):
    """(Test clause, file it came from) or (None, None)."""
    for name in ("CUSTOMISATION-definitions.md", "CUSTOMISATION.md"):
        path = os.path.join(vault, name)
        try:
            txt = open(path, encoding="utf-8").read()
        except OSError:
            continue
        m = re.search(r"(?m)^###\s+%s\s*$" % re.escape(style), txt)
        if not m:
            continue
        rest = txt[m.end():]
        nxt = re.search(r"(?m)^(?:###|##)\s", rest)
        block = rest[:nxt.start()] if nxt else rest
        tm = re.search(r"(?is)\bTest:\s*(.+?)(?:\n\n|\Z)", block)
        if tm:
            return " ".join(tm.group(1).split()), name
        return None, name
    return None, None


def main(argv=None):
    p = argparse.ArgumentParser(description="render the rubric with the live style definition")
    p.add_argument("--style", default="shortest")
    p.add_argument("--vault", default=".")
    p.add_argument("--template", default=os.path.join(HERE, "rubric.md"))
    p.add_argument("--out")
    p.add_argument("--test-only", action="store_true", help="print only the rendered Test line and exit (the run stamp and deep-lint's skip test hash it)")
    a = p.parse_args(argv)
    try:
        template = open(a.template, encoding="utf-8").read()
    except OSError:
        print("PROBE FAILED: no rubric template at %s" % a.template)
        return 2
    test, source = style_test(a.vault, a.style)
    if source is None:
        print("PROBE FAILED: no `### %s` block in CUSTOMISATION-definitions.md or CUSTOMISATION.md under %s"
              % (a.style, a.vault))
        return 2
    if test is None:
        print("PROBE FAILED: the `### %s` block in %s has no `Test:` clause" % (a.style, source))
        return 2
    if a.test_only:   # the run stamp and deep-lint's skip test hash this one line
        print("Test: " + test)
        return 0
    rendered = (template.replace("{{STYLE}}", a.style)
                        .replace("{{STYLE_TEST}}", "Test: " + test)
                        .replace("{{RENDERED}}", "%s from %s" % (datetime.date.today().isoformat(), source)))
    left = re.findall(r"\{\{[A-Z_]+\}\}", rendered)
    if left:
        print("PROBE FAILED: placeholder(s) left unrendered: %s" % ", ".join(sorted(set(left))))
        return 2
    if a.out:
        os.makedirs(a.out, exist_ok=True)
        with open(os.path.join(a.out, "rubric.md"), "w", encoding="utf-8") as fh:
            fh.write(rendered)
        print("rubric: %s rendered for the %s style (%s); embedded: Test: %s" % (os.path.join(a.out, "rubric.md"), a.style, source, test))
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
