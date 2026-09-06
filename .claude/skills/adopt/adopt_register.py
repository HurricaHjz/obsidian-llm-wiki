#!/usr/bin/env python3
"""adopt_register.py — add, retire or seed rows of the capability register's user-level table.

    adopt_register.py --register PATH --row 'name|level|carrier|pin_publisher|acceptance|bump|record' [--write]
    adopt_register.py --register PATH --retire NAME [--write]
    adopt_register.py --register PATH --seed [--write]
    (optional: --date YYYY-MM-DD, default today)

Dry-run by default: prints the resulting row (or the skeleton) and a unified diff. With --write the
register's `## User-level skills` table is patched by an anchored, atomic write: the whole new text is
encoded first, written to a temporary file in the register's directory and moved into place with
os.replace; the frontmatter's `updated:` is stamped in the same write.

Shape (lint's register arm greps it): one row per directory name, first cell `` `name` ``, seven
cells (Name · Level · Carrier · Pin · publisher · Acceptance · Bump · Record), between the
`## User-level skills` heading and the `## Plugins` heading. Exactly one live row per name is
asserted before and after every write. --row on a name that already has a live row updates it in
place (a level change: the row and the carrier change together). --retire keeps the row as history:
the first cell becomes ``~~`name`~~ retired DATE`` and the level cell `retired DATE (was LEVEL)`, so
the arm's `^| `name`` pattern no longer counts it against the directory listing.
--seed writes templates/register-skeleton.md only when the register is absent; an existing register
is left alone and reported.

Exit: 0 · 2 PROBE FAILED (register or table missing, malformed row, duplicate rows, unknown name).
"""
import argparse
import datetime
import difflib
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
SKELETON = os.path.join(HERE, "templates", "register-skeleton.md")
SECTION = "## User-level skills"
NEXT_SECTION = "## Plugins"
COLUMNS = ["name", "level", "carrier", "pin_publisher", "acceptance", "bump", "record"]
HEADER = "| Name | Level | Carrier | Pin · publisher | Acceptance | Bump | Record |"
SEPARATOR = "|---|---|---|---|---|---|---|"
LEVELS = ("auto", "propose-first", "by-name")
LIVE_ROW = re.compile(r"^\| `([a-z0-9-]+)` \|")
RETIRED_ROW = re.compile(r"^\| ~~`([a-z0-9-]+)`~~")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def fail(msg):
    print("PROBE FAILED: " + msg)
    sys.exit(2)


def split_cells(line):
    """Cells of one table row (the outer pipes dropped). Cells never contain a pipe in this table."""
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def parse_register(text):
    """Locate the user-level table. Returns a dict: lines · section (heading index) · header · sep ·
    rows [(index, name, live, cells)] · insert (index after the last row) · end (next heading)."""
    lines = text.split("\n")
    section = next((i for i, l in enumerate(lines) if l.startswith(SECTION)), None)
    if section is None:
        raise ValueError(f"no `{SECTION}` heading")
    end = next((i for i in range(section + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    header = next((i for i in range(section + 1, end) if lines[i].startswith("| Name |")), None)
    if header is None:
        raise ValueError(f"no `| Name |` header row under `{SECTION}`")
    sep = header + 1
    if sep >= end or not re.match(r"^\|(\s*:?-+:?\s*\|)+\s*$", lines[sep]):
        raise ValueError("no separator row after the header")
    rows = []
    i = sep + 1
    while i < end and lines[i].startswith("|"):
        m = LIVE_ROW.match(lines[i])
        r = RETIRED_ROW.match(lines[i])
        if m:
            rows.append((i, m.group(1), True, split_cells(lines[i])))
        elif r:
            rows.append((i, r.group(1), False, split_cells(lines[i])))
        else:
            rows.append((i, None, False, split_cells(lines[i])))
        i += 1
    return {"lines": lines, "section": section, "header": header, "sep": sep, "rows": rows,
            "insert": i, "end": end}


def live_rows(reg, name):
    return [r for r in reg["rows"] if r[2] and r[1] == name]


def stamp_updated(lines, date):
    if lines and lines[0] == "---":
        for i in range(1, min(len(lines), 60)):
            if lines[i] == "---":
                break
            if lines[i].startswith("updated:"):
                lines[i] = f"updated: {date}"
                break
    return lines


def atomic_write(path, data):
    d = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp = tempfile.mkstemp(prefix=".adopt-register-", suffix=".tmp", dir=d)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def show_diff(old, new, path):
    diff = list(difflib.unified_diff(old.split("\n"), new.split("\n"), fromfile=path, tofile=path + " (new)", lineterm="", n=1))
    if diff:
        print("\n".join(diff[:80]))
        if len(diff) > 80:
            print(f"... ({len(diff) - 80} more diff lines)")


def build_row(spec):
    cells = [c.strip() for c in spec.split("|")]
    if len(cells) != len(COLUMNS):
        fail(f"--row needs exactly {len(COLUMNS)} pipe-separated fields ({'|'.join(COLUMNS)}); got {len(cells)}")
    empty = [COLUMNS[i] for i, c in enumerate(cells) if not c]
    if empty:
        fail("--row has empty field(s): " + ", ".join(empty))
    name = cells[0].strip("`")
    if not NAME_RE.match(name):
        fail(f"name {name!r} must match [a-z0-9][a-z0-9-]* (the register arm greps that shape)")
    if not any(cells[1].startswith(lv) for lv in LEVELS):
        fail(f"level {cells[1]!r} must start with one of {', '.join(LEVELS)}")
    cells[0] = f"`{name}`"
    return name, "| " + " | ".join(cells) + " |"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Patch the capability register's user-level table (dry-run unless --write).")
    ap.add_argument("--register", required=True)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--row", help="'name|level|carrier|pin_publisher|acceptance|bump|record'")
    g.add_argument("--retire", metavar="NAME")
    g.add_argument("--seed", action="store_true")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--skeleton", default=SKELETON, help=argparse.SUPPRESS)
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args(argv)
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", a.date):
        fail(f"--date {a.date!r} is not YYYY-MM-DD")
    path = os.path.abspath(os.path.expanduser(a.register))
    mode = "write" if a.write else "dry-run"

    if a.seed:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    reg = parse_register(fh.read())
                n = sum(1 for r in reg["rows"] if r[2])
                print(f"register present: {path} ({n} live rows); nothing to seed")
            except (OSError, ValueError) as e:
                print(f"register present: {path}; nothing to seed (table not parsed: {e})")
            return 0
        if not os.path.isdir(os.path.dirname(path)):
            fail(f"parent directory missing for {path} (not a vault?)")
        try:
            with open(a.skeleton, "r", encoding="utf-8") as fh:
                text = fh.read().replace("{{DATE}}", a.date)
        except OSError:
            fail(f"skeleton missing: {a.skeleton}")
        if "{{" in text:
            fail("skeleton left a placeholder unfilled")
        parse_register(text)  # the skeleton must itself carry the table shape
        print(f"adopt_register {mode}: seed {path} from {os.path.basename(a.skeleton)} ({len(text.encode('utf-8'))} B)")
        if not a.write:
            print("--- skeleton ---")
            sys.stdout.write(text)
            print("--- end ---")
            print("dry-run: pass --write to apply")
            return 0
        atomic_write(path, text.encode("utf-8"))
        with open(path, "r", encoding="utf-8") as fh:
            parse_register(fh.read())
        print(f"done: seeded {path}")
        return 0

    try:
        with open(path, "r", encoding="utf-8") as fh:
            old = fh.read()
    except OSError:
        fail(f"register missing or unreadable: {path} (run --seed first)")
    try:
        reg = parse_register(old)
    except ValueError as e:
        fail(f"register {path}: {e}")
    lines = list(reg["lines"])

    if a.row:
        name, row = build_row(a.row)
        existing = live_rows(reg, name)
        if len(existing) > 1:
            fail(f"register malformed: {len(existing)} live rows for `{name}` (fix by hand first)")
        if existing:
            idx = existing[0][0]
            action = "UPDATE (in place)"
            lines[idx] = row
        else:
            idx = reg["insert"]
            action = "ADD"
            lines.insert(idx, row)
        print(f"adopt_register {mode}: {action} row `{name}` in {path}")
        print(row)
    else:
        name = a.retire.strip()
        existing = live_rows(reg, name)
        if not existing:
            retired = [r for r in reg["rows"] if r[1] == name and not r[2]]
            fail(f"no live row `{name}` in {path}" + (" (already retired)" if retired else ""))
        if len(existing) > 1:
            fail(f"register malformed: {len(existing)} live rows for `{name}` (fix by hand first)")
        idx, _, _, cells = existing[0]
        cells = list(cells)
        cells[0] = f"~~`{name}`~~ retired {a.date}"
        cells[1] = f"retired {a.date} (was {cells[1]})"
        lines[idx] = "| " + " | ".join(cells) + " |"
        print(f"adopt_register {mode}: RETIRE row `{name}` in {path}")
        print(lines[idx])

    lines = stamp_updated(lines, a.date)
    new = "\n".join(lines)
    check = parse_register(new)
    live_after = live_rows(check, name)
    if a.row and len(live_after) != 1:
        fail(f"post-condition failed: {len(live_after)} live rows for `{name}` after the edit")
    if a.retire and live_after:
        fail(f"post-condition failed: a live row for `{name}` survived the retire")
    show_diff(old, new, path)
    if not a.write:
        print("dry-run: pass --write to apply")
        return 0
    atomic_write(path, new.encode("utf-8"))
    with open(path, "r", encoding="utf-8") as fh:
        back = fh.read()
    if back != new:
        fail(f"post-write verification failed: {path} differs from the encoded text")
    print(f"done: {path} updated ({len(new.encode('utf-8'))} B)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
