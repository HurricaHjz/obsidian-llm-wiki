#!/usr/bin/env python3
"""capture_write.py — the sole write path for /gather captures (gather v3.1).

Mechanises the four write-time rules that were behavioural in v3: budget/ceiling
enforcement (via the run ledger), raw immutability (refuses any existing path),
sanitisation (ingest Step-0 rules, tested), and complete provenance frontmatter.
Fetching stays with the engines (defuddle/curl/markitdown/Jina); this script only
turns fetched Markdown into a raw/ file. If this script is missing or broken the
run STOPS and asks — never silently revert to hand-written captures. Verbs:
    write --url U --engine E --ledger-id ID [--title T] [--slug S] [--vault-root .]
        reads Markdown on stdin; writes raw/<slug>.md; appends to the ledger
    dedup --urls a,b,c --control URL [--vault-root .] [--allow-no-control]
        greps candidate URLs against source_url/converted_from in raw/ + wiki/;
        the --control URL MUST hit (proof the scan ran — CLAUDE.md §11)
"""
import argparse, datetime, os, re, sys
import run_ledger

CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
BARE_LINK = re.compile(r"\[([^\]\n]+)\]\(([^)\s]+)\)")


def sanitise(text):
    """Ingest Step-0 cleanup: strip control bytes; defang stray link syntax."""
    text = CONTROL_CHARS.sub("", text)
    text = text.replace("[[", r"\[\[")  # stray wiki-link syntax from math/citations

    def _defang(m):
        target = m.group(2)
        if "://" in target or target.startswith(("#", "/", ".")) or "." in target:
            return m.group(0)  # real link — keep
        return f"{m.group(1)} ({target})"  # [text](bareword) — defang
    return BARE_LINK.sub(_defang, text)


def slug_from(url, title=None):
    base = title or re.sub(r"^[a-z]+://", "", url)
    s = re.sub(r"[^A-Za-z0-9]+", "-", base).strip("-").lower()[:80].strip("-")
    return s or "capture"


def write(a):
    body = sys.stdin.read()
    if not body.strip():
        raise ValueError("empty stdin — nothing fetched, nothing written")
    ledger_path = run_ledger.path_for(a.ledger_id)
    data = run_ledger.load(ledger_path)              # missing → FileNotFoundError (exit 2)
    captured = len(data["captures"])
    if captured >= min(data["budget"], run_ledger.HARD_CEILING):
        raise ValueError(f"budget spent ({captured}/{data['budget']}) — refusing to write; "
                         "raise the budget explicitly or stop")
    slug = a.slug or slug_from(a.url, a.title)
    dest = os.path.join(a.vault_root, "raw", f"{slug}.md")
    if os.path.exists(dest):
        raise ValueError(f"{dest} exists — raw files are immutable; pick another --slug")
    title = (a.title or slug).replace('"', "'")
    front = ("---\n"
             f'title: "{title}"\n'
             f"source_url: {a.url}\n"
             f"converted_from: {a.url}\n"
             f"converted_by: {a.engine}\n"
             f"converted_on: {datetime.date.today().isoformat()}\n"
             "---\n\n")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(front + sanitise(body))
    data["captures"].append({"url": a.url, "slug": slug,
                             "ts": datetime.datetime.now().isoformat(timespec="seconds")})
    run_ledger.save(ledger_path, data)
    print(f"wrote raw/{slug}.md · ledger {len(data['captures'])}/{data['budget']}")


def dedup(a):
    urls = [u.strip() for u in (a.urls or "").split(",") if u.strip()]
    if not urls:
        raise ValueError("dedup needs --urls a,b,c")
    if not a.control and not a.allow_no_control:
        raise ValueError("dedup needs --control <known-present URL> (proof the scan runs); "
                         "--allow-no-control only for a provably fresh vault, and say so")
    targets = urls + ([a.control] if a.control else [])
    hits = {u: [] for u in targets}
    key = re.compile(r"^(source_url|converted_from):", re.I)
    for root in ("raw", "wiki"):
        top = os.path.join(a.vault_root, root)
        for dirpath, _dirs, files in os.walk(top):
            for name in files:
                if not name.endswith(".md"):
                    continue
                fp = os.path.join(dirpath, name)
                try:
                    with open(fp, encoding="utf-8") as fh:
                        head = fh.read(4096)
                except OSError:
                    continue
                for line in head.splitlines():
                    if key.match(line):
                        for u in targets:
                            if u and u in line:
                                hits[u].append(os.path.relpath(fp, a.vault_root))
    if a.control and not hits[a.control]:
        raise ValueError(f"control URL {a.control} not found — the scan cannot be trusted; "
                         "fix the control or the scan before claiming clean")
    for u in urls:
        state = "ALREADY IN VAULT: " + "; ".join(sorted(set(hits[u]))) if hits[u] else "new"
        print(f"{u} -> {state}")


def main():
    ap = argparse.ArgumentParser(description="Sole write path for /gather captures (v3.1).")
    ap.add_argument("verb", choices=["write", "dedup"])
    ap.add_argument("--url"), ap.add_argument("--title"), ap.add_argument("--slug")
    ap.add_argument("--engine", default="unknown")
    ap.add_argument("--ledger-id", dest="ledger_id")
    ap.add_argument("--urls"), ap.add_argument("--control")
    ap.add_argument("--allow-no-control", action="store_true")
    ap.add_argument("--vault-root", default=".")
    a = ap.parse_args()
    try:
        if a.verb == "write":
            if not (a.url and a.ledger_id):
                raise ValueError("write needs --url and --ledger-id")
            write(a)
        else:
            dedup(a)
    except FileNotFoundError as e:
        print(f"capture_write: ledger missing ({e}) — STOP and ask the owner; "
              "never hand-write a capture around this script", file=sys.stderr)
        sys.exit(2)
    except ValueError as e:
        print(f"capture_write: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
