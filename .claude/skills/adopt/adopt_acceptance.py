#!/usr/bin/env python3
"""adopt_acceptance.py — the scripted acceptance legs of an adoption, read-only.

    adopt_acceptance.py --name N --register PATH [--repo DIR] [--exclude d1,d2]
                        [--raw FILE --upstream-readme FILE] [--skills-root DIR] [--baseline FILE]

Legs (each prints ok / FAIL / n-a with its evidence; exit 1 on any FAIL):
  (a) excluded-directory references — with --repo and --exclude: the kept tree is grepped for each
      excluded directory by its bare name in path form (`name/`, `../name/`, `` `name` ``), the shape
      that a `../name/`-only grep missed in the ARS adoption; the control runs the same pattern
      builder on a kept top-level directory name (or, when no kept directory is referenced anywhere,
      on an embedded text that plants `evals/gold`) and must hit.
  (b) register row — a live row for the name under `## User-level skills`, every one of the seven
      join fields non-empty and not a placeholder (`unrecorded`, `none recorded`, `tbd`, ...), the
      level one of auto · propose-first · by-name.
  (c) raw README — with --raw and --upstream-readme: byte-identical, or byte-identical after the
      raw file's provenance frontmatter (the ingest verbatim capture prepends one).
  (d) wrapper shape, keyed on the row's level: auto -> the entry is a symlink that resolves to a
      directory holding SKILL.md; propose-first -> a wrapper directory whose SKILL.md names N, carries
      the gate sentinels and no hidden field, with an `upstream` link that resolves; by-name -> the
      same with `disable-model-invocation: true` and the by-name sentinel.
  (e) baseline — the name is a whole line of the sanctioned baseline (<skills-root>/.sanctioned.txt
      by default); negative control: a known-absent name is not.

The head's headless probes (listing present or absent, `/name` answering from upstream) are not
here: a script never runs them.

Exit: 0 all legs ok or n/a · 1 any FAIL · 2 PROBE FAILED (register unreadable, skills root missing).
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True   # the sibling imports below must never leave a __pycache__ in a shipped skill
sys.path.insert(0, HERE)
import adopt_register  # noqa: E402  (the one register parser)
import adopt_wrapper   # noqa: E402  (the one wrapper frontmatter reader and the gate sentinels)

PLACEHOLDER = re.compile(r"^(unrecorded|none( recorded| yet)?|tbd|n/a|\?|-|—)\b", re.I)
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__"}
MAX_FILE_BYTES = 2 * 1024 * 1024   # bound with headroom, as in the fingerprint
CONTROL_TEXT = "see evals/gold and ../evals/ for the fixtures\n"
CONTROL_NAME = "evals"


def ref_pattern(name):
    """References to a directory by bare name: `name/` in any path position, or `` `name` ``."""
    n = re.escape(name)
    return re.compile(r"(?<![A-Za-z0-9_-])" + n + r"/|`" + n + r"`")


def walk_kept(repo, excluded):
    out = []
    for root, dnames, fnames in os.walk(repo):
        rel_root = os.path.relpath(root, repo)
        rel_root = "" if rel_root == "." else rel_root
        keep = []
        for d in sorted(dnames):
            rel = os.path.join(rel_root, d) if rel_root else d
            if d in SKIP_DIRS or rel in excluded or d in excluded:
                continue
            keep.append(d)
        dnames[:] = keep
        for f in sorted(fnames):
            p = os.path.join(root, f)
            if os.path.islink(p) and not os.path.isfile(p):
                continue
            try:
                if os.path.getsize(p) > MAX_FILE_BYTES:
                    continue
                with open(p, "rb") as fh:
                    data = fh.read()
            except OSError:
                continue
            if b"\x00" in data[:8192]:
                continue
            out.append((os.path.relpath(p, repo), data.decode("utf-8", errors="replace")))
    return out


def grep(files, pat):
    hits = []
    for rel, text in files:
        for ln, line in enumerate(text.split("\n"), 1):
            if pat.search(line):
                hits.append((rel, ln, line.strip()[:120]))
    return hits


class Legs:
    def __init__(self):
        self.rows = []
        self.failed = 0

    def ok(self, leg, msg):
        self.rows.append((leg, "ok", msg))

    def fail(self, leg, msg):
        self.failed += 1
        self.rows.append((leg, "FAIL", msg))

    def na(self, leg, msg):
        self.rows.append((leg, "n/a", msg))

    def render(self):
        out = ["| leg | result | evidence |", "|---|---|---|"]
        out += [f"| {l} | {r} | {m} |" for l, r, m in self.rows]
        n_ok = sum(1 for _, r, _ in self.rows if r == "ok")
        n_na = sum(1 for _, r, _ in self.rows if r == "n/a")
        out.append(f"acceptance: {len(self.rows)} legs · {n_ok} ok · {self.failed} FAIL · {n_na} n/a")
        return "\n".join(out)


def leg_a(L, repo, exclude):
    if not repo or not exclude:
        L.na("a excluded refs", "no --repo/--exclude given (nothing excluded from the pinned tree)")
        return
    repo = os.path.realpath(os.path.expanduser(repo))
    if not os.path.isdir(repo):
        L.fail("a excluded refs", f"--repo {repo} is not a directory")
        return
    excluded = {e.strip().strip("/") for e in exclude.split(",") if e.strip()}
    files = walk_kept(repo, excluded)
    if not files:
        L.fail("a excluded refs", f"no text files in the kept tree of {repo}")
        return
    # control: the same pattern builder on a kept top-level directory that is referenced somewhere
    kept_dirs = sorted(d for d in os.listdir(repo)
                       if os.path.isdir(os.path.join(repo, d)) and d not in SKIP_DIRS and d not in excluded)
    control = None
    for d in kept_dirs:
        n = len(grep(files, ref_pattern(d)))
        if n:
            control = f"control OK: `{d}/` (kept) referenced {n}× through the same pattern"
            break
    if control is None:
        n = len(grep([("<embedded>", CONTROL_TEXT)], ref_pattern(CONTROL_NAME)))
        if n < 1:
            L.fail("a excluded refs", "PROBE FAILED: the reference pattern missed the embedded control text")
            return
        control = f"control OK: no kept directory is referenced in the tree, so the embedded text hit {n}× for `{CONTROL_NAME}/`"
    bad = []
    for d in sorted(excluded):
        hits = grep(files, ref_pattern(d))
        if hits:
            sample = "; ".join(f"{r}:{ln}: {t}" for r, ln, t in hits[:5])
            bad.append(f"`{d}/` {len(hits)} hit(s) in {len({r for r, _, _ in hits})} file(s): {sample}")
    if bad:
        L.fail("a excluded refs", " · ".join(bad) + f" · {control}")
    else:
        L.ok("a excluded refs", f"0 references to {', '.join(sorted(excluded))} in {len(files)} kept files · {control}")


def leg_b(L, name, reg):
    rows = adopt_register.live_rows(reg, name)
    if not rows:
        retired = [r for r in reg["rows"] if r[1] == name and not r[2]]
        L.fail("b register row", f"no live row `{name}`" + (" (a retired row exists)" if retired else ""))
        return None
    if len(rows) > 1:
        L.fail("b register row", f"{len(rows)} live rows for `{name}` (exactly one expected)")
        return None
    cells = rows[0][3]
    if len(cells) != len(adopt_register.COLUMNS):
        L.fail("b register row", f"row has {len(cells)} cells, expected {len(adopt_register.COLUMNS)}")
        return None
    empty = [adopt_register.COLUMNS[i] for i, c in enumerate(cells) if not c or PLACEHOLDER.match(c)]
    level = cells[1]
    level_key = next((lv for lv in adopt_register.LEVELS if level.startswith(lv)), None)
    if level_key is None:
        empty.append(f"level ({level!r} is not auto · propose-first · by-name)")
    if empty:
        L.fail("b register row", "empty or placeholder join field(s): " + ", ".join(empty))
        return level_key
    L.ok("b register row", f"level {level_key} · pin {cells[3]} · record {cells[6]}")
    return level_key


def leg_c(L, raw, upstream):
    if not raw and not upstream:
        L.na("c raw README", "no --raw/--upstream-readme given")
        return
    if not (raw and upstream):
        L.fail("c raw README", "--raw and --upstream-readme must be given together")
        return
    try:
        with open(os.path.expanduser(raw), "rb") as fh:
            r = fh.read()
        with open(os.path.expanduser(upstream), "rb") as fh:
            u = fh.read()
    except OSError as e:
        L.fail("c raw README", f"unreadable: {e}")
        return
    if r == u:
        L.ok("c raw README", f"byte-identical ({len(u):,} B)")
        return
    if r.startswith(b"---\n"):
        j = r.find(b"\n---\n", 4)
        if j > 0 and r[j + 5:] == u:
            L.ok("c raw README", f"byte-identical after the provenance frontmatter ({j + 5} B of frontmatter, {len(u):,} B of body)")
            return
    k = next((i for i in range(min(len(r), len(u))) if r[i] != u[i]), min(len(r), len(u)))
    L.fail("c raw README", f"differs: raw {len(r):,} B vs upstream {len(u):,} B, first difference at byte {k}")


def leg_d(L, name, level, root):
    if level is None:
        L.fail("d wrapper shape", "not checked: the level comes from the register row, which is missing or invalid")
        return
    entry = os.path.join(root, name)
    if not os.path.lexists(entry):
        L.fail("d wrapper shape", f"{entry} is absent")
        return
    if level == "auto":
        if not os.path.islink(entry):
            L.fail("d wrapper shape", f"auto expects a symlink; {entry} is a {'directory' if os.path.isdir(entry) else 'file'}")
            return
        target = os.path.realpath(entry)
        if not os.path.isdir(target):
            L.fail("d wrapper shape", f"symlink does not resolve to a directory: {entry} -> {os.readlink(entry)}")
            return
        if not os.path.isfile(os.path.join(target, "SKILL.md")):
            L.fail("d wrapper shape", f"symlink target has no SKILL.md: {target}")
            return
        L.ok("d wrapper shape", f"auto: symlink -> {target} (SKILL.md present)")
        return
    if os.path.islink(entry) or not os.path.isdir(entry):
        L.fail("d wrapper shape", f"{level} expects a wrapper directory; {entry} is a {'symlink' if os.path.islink(entry) else 'file'}")
        return
    skill = os.path.join(entry, "SKILL.md")
    try:
        with open(skill, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        L.fail("d wrapper shape", f"no readable SKILL.md in {entry}")
        return
    fm, body = adopt_wrapper.parse_frontmatter(text)
    problems = []
    if fm.get("name") != name:
        problems.append(f"frontmatter name {fm.get('name')!r} != {name!r}")
    if not fm.get("description"):
        problems.append("description missing")
    hidden = adopt_wrapper.HIDDEN_FIELD in text.split("\n---\n", 1)[0]
    if level == "propose-first" and hidden:
        problems.append("hidden field present on a propose-first wrapper")
    if level == "by-name" and not hidden:
        problems.append("disable-model-invocation: true missing on a by-name wrapper")
    for s in adopt_wrapper.GATE_SENTINELS[level]:
        if s == adopt_wrapper.HIDDEN_FIELD:
            continue
        if s not in body:
            problems.append(f"gate text missing: {s!r}")
    link = os.path.join(entry, "upstream")
    if not os.path.islink(link):
        problems.append("no `upstream` symlink")
    elif not os.path.isfile(os.path.join(os.path.realpath(link), "SKILL.md")):
        problems.append(f"`upstream` does not resolve to a directory with SKILL.md ({os.readlink(link)})")
    if problems:
        L.fail("d wrapper shape", f"{level}: " + "; ".join(problems))
    else:
        L.ok("d wrapper shape", f"{level}: name ok · gate text present · hidden field {'present' if hidden else 'absent'} · upstream -> {os.path.realpath(link)}")


def leg_e(L, name, baseline):
    if not os.path.isfile(baseline):
        L.fail("e baseline", f"baseline absent: {baseline} (a fresh machine: seed it after the owner reviews)")
        return
    with open(baseline, "r", encoding="utf-8") as fh:
        names = [l.strip() for l in fh.read().split("\n") if l.strip() and not l.startswith("#")]
    if "zzz-ctrl" in names:
        L.fail("e baseline", "negative control failed: the known-absent name `zzz-ctrl` is in the baseline")
        return
    if name in names:
        L.ok("e baseline", f"`{name}` is a line of {baseline} ({len(names)} names; control: `zzz-ctrl` absent)")
    else:
        L.fail("e baseline", f"`{name}` is not in {baseline} ({len(names)} names; control: `zzz-ctrl` absent)")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Scripted acceptance legs of an adoption (read-only).")
    ap.add_argument("--name", required=True)
    ap.add_argument("--register", required=True)
    ap.add_argument("--repo")
    ap.add_argument("--exclude", help="comma-separated directories excluded from the pinned tree")
    ap.add_argument("--raw", help="the raw/ README capture")
    ap.add_argument("--upstream-readme", help="the pinned upstream README")
    ap.add_argument("--skills-root", help="defaults to ~/.claude/skills")
    ap.add_argument("--baseline", help="defaults to <skills-root>/.sanctioned.txt")
    a = ap.parse_args(argv)

    root = os.path.realpath(os.path.expanduser(a.skills_root)) if a.skills_root else adopt_wrapper.default_skills_root()
    if not os.path.isdir(root):
        print(f"PROBE FAILED: skills root {root} is not a directory")
        return 2
    reg_path = os.path.abspath(os.path.expanduser(a.register))
    try:
        with open(reg_path, "r", encoding="utf-8") as fh:
            reg = adopt_register.parse_register(fh.read())
    except (OSError, ValueError) as e:
        print(f"PROBE FAILED: register {reg_path}: {e}")
        return 2
    baseline = os.path.expanduser(a.baseline) if a.baseline else os.path.join(root, ".sanctioned.txt")

    L = Legs()
    print(f"adopt_acceptance: {a.name} · register {reg_path} · skills root {root}")
    leg_a(L, a.repo, a.exclude)
    level = leg_b(L, a.name, reg)
    leg_c(L, a.raw, a.upstream_readme)
    leg_d(L, a.name, level, root)
    leg_e(L, a.name, baseline)
    print(L.render())
    return 1 if L.failed else 0


if __name__ == "__main__":
    sys.exit(main())
