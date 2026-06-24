#!/usr/bin/env python3
"""Complete unit test for export-okf. Builds its own fixture vault in a temp dir
(never touches the real wiki), runs the exporter, and asserts every feature."""
import os, sys, glob, tempfile, shutil, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_okf as E

FAILS, COUNT = [], [0]
def check(cond, msg):
    COUNT[0] += 1
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        FAILS.append(msg)

def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)

def read(p):
    return open(p, encoding="utf-8", errors="replace").read()

def snapshot(d):
    s = {}
    for ab in sorted(glob.glob(os.path.join(d, "**", "*"), recursive=True)):
        if os.path.isfile(ab):
            s[os.path.relpath(ab, d)] = read(ab)
    return s

def build_fixture(root):
    wiki, assets = os.path.join(root, "wiki"), os.path.join(root, "assets")
    w(os.path.join(wiki, "concepts", "Alpha.md"),
      '---\ntitle: "Alpha"\ntype: concept\ntags: [x]\nupdated: 2026-06-01\n---\n'
      '## Definition\nAlpha links to [[Beta]], [[Beta|the beta]] and [[Beta#Key Points]].\n'
      'It shows ![[pic.png]] plus a [[Ghost]] dangling link.\n'
      'Use the `[[Beta]]` wikilink syntax inline.\n')
    w(os.path.join(wiki, "concepts", "Beta.md"),
      '---\ntitle: "Beta"\ntype: concept\nupdated: 2026-06-02\n---\n'
      '## Definition\nBeta is the second letter. More text here.\n\n## Key Points\n- a point\n')
    w(os.path.join(wiki, "sources", "src-one.md"),
      '---\ntitle: "Source One"\ntype: source\nsource_url: "https://example.com/x"\nfoo: bar\nupdated: 2026-06-03\n---\n'
      '## Summary\nA summary referencing [[Alpha]].\n')
    w(os.path.join(wiki, "index.md"),
      '# Wiki Index\n## Concepts\n- [[Alpha]] — Alpha is first.\n'
      '## Sources\n- [[src-one]] — \U0001F4C4 *research* — A source.\n')
    w(os.path.join(wiki, "log.md"),
      '# log\n\n## [2026-06-01] sync | Earlier thing\n- detail\n\n'
      '## [2026-06-02] ingest | Did a thing\n- detail\n')
    w(os.path.join(assets, "pic.png"), "PNGDATA")
    return wiki, assets

def main():
    root = tempfile.mkdtemp(prefix="okftest_")
    try:
        wiki, assets = build_fixture(root)
        before = snapshot(wiki)
        out = os.path.join(root, "out")
        summary, issues, warn = E.export(wiki, assets, out, quiet=True)

        print("- structure")
        check(os.path.exists(os.path.join(out, "concepts", "Alpha.md")), "Alpha emitted")
        check(os.path.exists(os.path.join(out, "concepts", "Beta.md")), "Beta emitted")
        check(os.path.exists(os.path.join(out, "sources", "src-one.md")), "src-one emitted")
        alpha = read(os.path.join(out, "concepts", "Alpha.md"))
        beta = read(os.path.join(out, "concepts", "Beta.md"))
        src = read(os.path.join(out, "sources", "src-one.md"))

        print("- frontmatter / required type")
        for nm, t in [("Alpha", alpha), ("Beta", beta), ("src-one", src)]:
            fm, _ = E.split_frontmatter(t)
            check(fm is not None and bool(E.fm_get(fm, "type")), nm + " has non-empty type")

        print("- derived recommended fields")
        check('description: "Alpha is first."' in alpha, "Alpha description from index")
        check("timestamp: 2026-06-01T00:00:00Z" in alpha, "Alpha timestamp from updated (ISO 8601)")
        check('description: "Beta is the second letter."' in beta, "Beta description fallback = first prose sentence")
        check("resource: https://example.com/x" in src, "src resource from source_url")
        check('description: "A source."' in src, "src description with research/em-dash prefix stripped")
        check(re.search(r'(?m)^foo: bar$', src) is not None, "src extra key 'foo' carried through")

        print("- link conversion (§5)")
        check("[Beta](/concepts/Beta.md)" in alpha, "plain wikilink -> bundle-relative md link")
        check("[the beta](/concepts/Beta.md)" in alpha, "aliased wikilink -> md link")
        check("[Beta](/concepts/Beta.md#key-points)" in alpha, "anchored wikilink -> md link + slug")
        check("![](/assets/pic.png)" in alpha, "image embed -> md image")
        check("`[[Beta]]`" in alpha, "wikilink inside inline code preserved (code-aware)")
        check(alpha.count("[[") == 1, "all prose wikilinks converted; only the code-span one remains")
        check("Ghost" in alpha and "[Ghost]" not in alpha, "unresolved link rendered as plain text")

        print("- assets")
        check(os.path.exists(os.path.join(out, "assets", "pic.png")), "referenced asset copied")

        print("- index.md (§6)")
        cidx = read(os.path.join(out, "concepts", "index.md"))
        check(cidx.startswith("# concepts"), "concepts/index.md heading")
        check("* [Alpha](/concepts/Alpha.md) - Alpha is first." in cidx, "concepts index entry w/ description")
        check("* [Beta](/concepts/Beta.md) - Beta is the second letter." in cidx, "concepts index Beta entry")
        sidx = read(os.path.join(out, "sources", "index.md"))
        check("* [Source One](/sources/src-one.md) - A source." in sidx, "sources index uses title + desc")
        ridx = read(os.path.join(out, "index.md"))
        check(ridx.startswith("# "), "root index heading")
        check("(/concepts/index.md)" in ridx and "(/sources/index.md)" in ridx, "root index lists sub-bundles (progressive)")

        print("- log.md (§7)")
        log = read(os.path.join(out, "log.md"))
        check(log.startswith("# Update Log"), "log heading")
        check(bool(re.search(r'(?m)^## 2026-06-02$', log)) and bool(re.search(r'(?m)^## 2026-06-01$', log)), "log ISO date headings")
        check(log.index("## 2026-06-02") < log.index("## 2026-06-01"), "log newest-first")
        check("* **ingest**: Did a thing" in log, "log entry bullet format")

        print("- conformance (§9) + summary")
        check(issues == [], "validate(): no conformance issues (got %d)" % len(issues))
        check(summary["concepts"] == 3, "summary concepts == 3 (got %s)" % summary["concepts"])
        check(summary["assets_copied"] == 1, "summary assets_copied == 1")
        check(summary["log"] is True, "summary log == True")
        check(summary["broken_links"] >= 1, "summary broken_links >= 1 (Ghost)")
        check(summary["conformance_issues"] == 0, "summary conformance_issues == 0")

        print("- read-only + determinism")
        check(snapshot(wiki) == before, "wiki/ not mutated")
        check("[[Beta]]" in read(os.path.join(wiki, "concepts", "Alpha.md")), "input retains its wikilinks")
        out2 = os.path.join(root, "out2")
        E.export(wiki, assets, out2, quiet=True)
        check(snapshot(out) == snapshot(out2), "deterministic (two runs byte-identical)")

        print("\n%d checks, %d failures" % (COUNT[0], len(FAILS)))
        return 1 if FAILS else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)

if __name__ == "__main__":
    sys.exit(main())
