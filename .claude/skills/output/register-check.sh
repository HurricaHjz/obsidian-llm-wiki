#!/usr/bin/env bash
# register-check.sh — measure a deliverable's prose against this vault's human-academic baseline.
#
# Usage:  bash .claude/skills/output/register-check.sh output/<file>.md [more files...]
#         bash .claude/skills/output/register-check.sh --baseline        # re-measure raw/2-papers/
#
# Counts three marks per 1,000 words of PROSE (frontmatter, code, tables, headings and URLs excluded,
# because a dash in a heading or table cell is structure, not register). Bands come from the pooled
# raw/2-papers/ corpus. A HIGH reading means a mark is doing work a human writer would have done with
# sentence structure; a LOW em-dash reading means the mark has been driven to zero, which is equally
# unnatural. Fix either by rewriting sentences, never by swapping one mark for another.
set -u
[ $# -ge 1 ] || { echo "usage: register-check.sh <file.md> [...] | --baseline"; exit 2; }

python3 - "$@" <<'PY'
import re, sys, glob, os

BANDS = {"em-dash": (0.3, 1.6), "amp-colon": (0.8, 3.5), "semicolon": (1.8, 6.0)}

def prose(t):
    t = re.sub(r'(?s)\A---\n.*?\n---\n', '', t)      # frontmatter
    t = re.sub(r'(?s)```.*?```', '', t)              # fenced code
    t = re.sub(r'`[^`\n]*`', '', t)                  # inline code
    keep = []
    for ln in t.split('\n'):
        s = ln.strip()
        if not s or s.startswith('#') or s.startswith('|') or s.startswith('---'):
            continue                                  # headings, tables, rules
        keep.append(re.sub(r'https?://\S+', '', ln))
    return '\n'.join(keep)

def measure(text):
    c = prose(text)
    w = len(re.findall(r"[A-Za-z][A-Za-z'-]*", c))
    if w == 0:
        return None
    k = w / 1000
    return {"words": w,
            "em-dash":   len(re.findall(r'—', c)) / k,
            "amp-colon": len(re.findall(r'(?<![0-9]):\s+[a-z]', c)) / k,
            "semicolon": c.count(';') / k}

def verdict(name, v):
    lo, hi = BANDS[name]
    if v > hi: return "HIGH"
    if v < lo: return "LOW " if name == "em-dash" else "ok  "   # only the em-dash floor is enforced
    return "ok  "

if sys.argv[1] == '--baseline':
    tot = {"words": 0, "em-dash": 0.0, "amp-colon": 0.0, "semicolon": 0.0}
    n = 0
    for f in glob.glob('raw/2-papers/*.md'):
        m = measure(open(f, encoding='utf-8', errors='replace').read())
        if not m or m["words"] < 200: continue
        n += 1; tot["words"] += m["words"]
        for k in BANDS: tot[k] += m[k] * m["words"] / 1000
    k = tot["words"] / 1000
    print(f"baseline over {n} papers, {tot['words']:,} words of prose")
    for m in BANDS: print(f"  {m:<10} {tot[m]/k:5.2f} per 1,000 words")
    sys.exit(0)

bad = 0
for f in sys.argv[1:]:
    try:
        m = measure(open(f, encoding='utf-8', errors='replace').read())
    except OSError as e:
        print(f"{f}: cannot read ({e})"); bad += 1; continue
    if not m:
        print(f"{f}: no prose to measure"); continue
    note = "  (under 800 words: rates are noisy, use judgement)" if m["words"] < 800 else ""
    print(f"{os.path.basename(f)} — {m['words']:,} words of prose{note}")
    for name in ("em-dash", "amp-colon", "semicolon"):
        lo, hi = BANDS[name]
        v = verdict(name, m[name])
        if v.strip() in ("HIGH", "LOW"): bad += 1
        print(f"  {name:<10} {m[name]:5.2f}   band {lo}-{hi}   {v}")
sys.exit(1 if bad else 0)
PY
