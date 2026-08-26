#!/usr/bin/env python3
"""capture_write.py — the sole write path for /gather captures (gather v3.1).

Mechanises the five write-time rules that were behavioural in v3: budget/ceiling
enforcement (via the run ledger), raw immutability (refuses any existing path),
sanitisation (ingest Step-0 rules, tested), complete provenance frontmatter, and
a capture QUALITY GATE — engines can "succeed" while emitting non-content (an
error stub served as a page, an HTML-dominant body from a crashed converter, a
near-empty fetch), so the write path refuses those bodies; retry with the next
engine, and a body you deliberately accept needs --allow-degraded '<why>' (the
acceptance is stamped into the frontmatter and ledger, and declared in the run
report). PLATFORM LANE (tier-3 CLIs; agent-reach-adoption-design runbook step
5): platform output (JSON/YAML/subtitles) is wrapped VERBATIM in closed fenced
blocks at capture — the gate and sanitiser honour that convention (fence-aware),
and bare unfenced whole-body JSON is refused so the convention is mechanical. Fetching stays with the engines (defuddle/curl/markitdown/Jina); this
script only turns fetched Markdown into a raw/ file. If this script is missing
or broken the run STOPS and asks — never hand-write captures around it. Verbs:
    write --url U --engine E --ledger-id ID [--title T] [--slug S] [--vault-root .]
          [--allow-degraded REASON]
        reads Markdown on stdin; writes raw/<slug>.md; appends to the ledger
    check
        reads Markdown on stdin; runs the quality gate only (no write, no
        ledger): prints PASS (exit 0) or REJECT + reason (exit 3)
    dedup --urls a,b,c | --urls a b c  --control URL [--vault-root .] [--allow-no-control]
        greps candidate URLs against source_url/converted_from in raw/ + wiki/;
        the --control URL MUST hit (proof the scan ran — CLAUDE.md §11)
"""
import argparse, datetime, json, os, re, sys
import run_ledger

CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
BARE_LINK = re.compile(r"\[([^\]\n]+)\]\(([^)\s]+)\)")
HTML_TAG = re.compile(r"<[A-Za-z][^>\n]*>")
# A CLOSED fenced block: column-0 opener, same-string closer alone on its line.
# Deliberate bounds: an unclosed opener never matches (no fence privilege on a
# broken premise); a longer/indented closer is not honoured — the platform
# capture path writes exact column-0 pairs, and anything else stays prose.
FENCED_BLOCK = re.compile(r"(?ms)^(?P<fence>`{3,}|~{3,})[^\n]*\n(?P<body>.*?)^(?P=fence)[ \t]*$\n?")


def sanitise(text):
    """Ingest Step-0 cleanup: strip control bytes; defang stray link syntax.

    Fence-aware (platform captures wrap CLI output verbatim in fenced blocks):
    content inside a CLOSED fence is kept byte-exact apart from the control-byte
    strip — Obsidian renders fences verbatim, so defanging there is needless and
    would corrupt platform JSON (nested arrays read as [[ wiki-link openers).
    An unclosed fence gets no privilege: its text is defanged as prose.
    """
    text = CONTROL_CHARS.sub("", text)  # first: no \x00 survives, so the fence
    stash = []                          # placeholders below cannot collide

    def _stash(m):
        stash.append(m.group(0))
        return f"\x00{len(stash) - 1}\x00"
    text = FENCED_BLOCK.sub(_stash, text)
    text = text.replace("[[", r"\[\[")  # stray wiki-link syntax from math/citations

    def _defang(m):
        target = m.group(2)
        if "://" in target or target.startswith(("#", "/", ".")) or "." in target:
            return m.group(0)  # real link — keep
        return f"{m.group(1)} ({target})"  # [text](bareword) — defang
    text = BARE_LINK.sub(_defang, text)
    for i, block in enumerate(stash):
        text = text.replace(f"\x00{i}\x00", block, 1)
    return text


def slug_from(url, title=None):
    base = title or re.sub(r"^[a-z]+://", "", url)
    s = re.sub(r"[^A-Za-z0-9]+", "-", base).strip("-").lower()[:80].strip("-")
    return s or "capture"


QUALITY_MIN_BYTES = 600
QUALITY_TAG_COUNT = 100     # both tag thresholds must trip before a body is
QUALITY_TAG_RATIO = 0.4     # called HTML-dominant (READMEs with badge HTML pass)
# Platform lane: a fence is inspected as the capture's own payload only when it
# DOMINATES the body — a minority fence is quoted material (a tutorial showing
# an API error example must not be refused). Both judgement-set, unmeasured:
# share 0.5 (a platform capture is a small header + the payload; a quoted
# example is a fraction of its article), tags 30 (hello-world HTML ~10 tags,
# a real served login/error page carries dozens).
QUALITY_FENCE_SHARE = 0.5
QUALITY_FENCE_TAGS = 30
HTML_PAGE_SIG = re.compile(r"(?i)<!DOCTYPE\s+html|<html[\s>]")
# Top-level JSON fields that never carry requested content — error envelopes
# plus response metadata; judgement-set, extend as the platforms teach us.
NONDATA_KEYS = {"error", "errors", "message", "msg", "code", "status", "name",
                "detail", "details", "title", "reason", "success",
                "meta", "metadata", "request_id", "timestamp"}


def _json_payload_reject(payload):
    """Inspect one JSON payload (a dominant fenced platform capture). Returns a
    reason or None. Top-level only — a nested null inside real data is the live
    probes' job, not the gate's; non-JSON (YAML/subtitles) passes through here
    (stdlib has no YAML) and is carried by the size floor + HTML-page signature.
    """
    try:
        obj = json.loads(payload)
    except ValueError:
        return None
    if isinstance(obj, list) and not obj:
        return "empty platform result (JSON [])"
    if isinstance(obj, dict):
        nonempty = {k.lower() for k, v in obj.items() if v not in (None, "", [], {})}
        if nonempty <= NONDATA_KEYS:  # includes the all-empty dict
            named = ", ".join(sorted(nonempty)) or "none"
            return f"platform payload carries no content (non-empty fields: {named})"
    return None


def quality_check(body):
    """Return a rejection reason, or None if the body looks like real content.

    Each check behaves sensibly when its own premise fails: an empty or
    whitespace body is caught by the size floor, a newline-free body gets
    lines >= 1 so the ratio cannot divide by zero, an unclosed fence is simply
    prose, and no pattern here can raise on arbitrary text. False positives
    (a legitimately tiny page, a tutorial dense with literal HTML) go through
    --allow-degraded, declared.

    Platform lane (fenced verbatim CLI output — JSON/YAML/subtitles): closed
    fenced payloads are excluded from the HTML-dominance scan (subtitle markup
    is data, not a crashed converter), and a DOMINANT fence is inspected
    directly — a JSON error/empty payload or a served HTML page (a login wall
    handed to the CLI) is refused.
    """
    text = body.strip()
    if len(text) < QUALITY_MIN_BYTES:
        return f"body too small ({len(text)} bytes < {QUALITY_MIN_BYTES}) — likely a failed fetch"
    head = text[:800]
    if re.search(r"Warning: Target URL returned error \d+", head):
        return "engine error stub ('Target URL returned error') — the page was not captured"
    if re.search(r"^Title: Page Not Found$", head, re.M):
        return "engine returned a Page Not Found shell, not the page"
    if text.startswith(("{", "[")):
        # An all-JSON body is either an engine's API error response served as
        # the page (2026-08-25: a Jina 403 AbuseAlleviationError stub, 620 B,
        # cleared the size floor) or platform output missing its fence wrap.
        # Markdown that merely opens with "{"/"[" fails json.loads and passes.
        try:
            json.loads(text)
            return ("body is a bare JSON document, not Markdown — an engine API "
                    "error stub, or unfenced platform output (platform captures "
                    "are fenced; adoption-design runbook step 5)")
        except ValueError:
            pass
    for m in FENCED_BLOCK.finditer(text):
        payload = m.group("body")
        if len(payload) / len(text) < QUALITY_FENCE_SHARE:
            continue  # minority fence — quoted material, not the payload
        reason = _json_payload_reject(payload)
        if reason:
            return reason + " — in the capture's fenced platform payload"
        fence_tags = len(HTML_TAG.findall(payload))
        if HTML_PAGE_SIG.search(payload) and fence_tags >= QUALITY_FENCE_TAGS:
            return (f"fenced payload is an HTML page ({fence_tags} tags, "
                    f"{len(payload) * 100 // len(text)}% of the body) — the "
                    "platform served a page (login wall / error), not data")
    prose = FENCED_BLOCK.sub("", text)
    tags = len(HTML_TAG.findall(prose))
    lines = max(1, prose.count("\n"))
    if tags >= QUALITY_TAG_COUNT and tags / lines >= QUALITY_TAG_RATIO:
        return (f"HTML-dominant body ({tags} tags over {lines} lines) — "
                "the converter emitted markup, not Markdown")
    return None


def write(a):
    body = sys.stdin.read()
    if not body.strip():
        raise ValueError("empty stdin — nothing fetched, nothing written")
    reason = quality_check(body)
    if reason and not a.allow_degraded:
        raise ValueError(f"quality gate: {reason}; retry with the next engine in the chain — "
                         "a body you deliberately accept needs --allow-degraded '<why>', "
                         "declared in the run report")
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
    front_lines = ["---",
                   f'title: "{title}"',
                   f"source_url: {a.url}",
                   f"converted_from: {a.url}",
                   f"converted_by: {a.engine}",
                   f"converted_on: {datetime.date.today().isoformat()}"]
    if reason:  # only reachable with --allow-degraded — stamp the acceptance
        note = a.allow_degraded.replace('"', "'")
        front_lines.append(f'capture_quality: "degraded — {reason}; accepted: {note}"')
    front = "\n".join(front_lines) + "\n---\n\n"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(front + sanitise(body))
    entry = {"url": a.url, "slug": slug,
             "ts": datetime.datetime.now().isoformat(timespec="seconds")}
    if reason:
        entry["degraded"] = reason
    data["captures"].append(entry)
    run_ledger.save(ledger_path, data)
    tag = " · DEGRADED (accepted)" if reason else ""
    print(f"wrote raw/{slug}.md · ledger {len(data['captures'])}/{data['budget']}{tag}")


def check_verb(_a):
    body = sys.stdin.read()
    reason = quality_check(body)
    if reason:
        print(f"REJECT: {reason}")
        sys.exit(3)
    print("PASS: body looks like real content")


def dedup(a):
    # accept comma-joined, space-separated (nargs), or mixed — the 2026-08-18 doc/arg
    # mismatch showed a single accepted form fails as soon as its restatement drifts
    urls = [u.strip() for tok in (a.urls or []) for u in re.split(r"[,\s]+", tok) if u.strip()]
    if not urls:
        raise ValueError("dedup needs --urls a,b,c (or --urls a b c)")
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
                        # The de-dup keys live in frontmatter. If the opening --- is not closed
                        # inside the fast window, extend once (64 KB hard stop) rather than
                        # silently scanning a truncated head (§12: bounds need stated headroom).
                        if head.startswith("---") and "\n---" not in head[3:]:
                            head += fh.read(61440)
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
    ap.add_argument("verb", choices=["write", "dedup", "check"])
    ap.add_argument("--url"), ap.add_argument("--title"), ap.add_argument("--slug")
    ap.add_argument("--engine", default="unknown")
    ap.add_argument("--ledger-id", dest="ledger_id")
    ap.add_argument("--urls", nargs="+"), ap.add_argument("--control")
    ap.add_argument("--allow-no-control", action="store_true")
    ap.add_argument("--allow-degraded", dest="allow_degraded", metavar="REASON",
                    help="write despite a quality-gate rejection; REASON is stamped into "
                         "frontmatter + ledger and must be declared in the run report")
    ap.add_argument("--vault-root", default=".")
    a = ap.parse_args()
    try:
        if a.verb == "write":
            if not (a.url and a.ledger_id):
                raise ValueError("write needs --url and --ledger-id")
            if a.allow_degraded is not None and not a.allow_degraded.strip():
                raise ValueError("--allow-degraded needs a non-empty reason")
            write(a)
        elif a.verb == "check":
            check_verb(a)
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
