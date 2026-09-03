#!/usr/bin/env python3
"""repo_pack — pinned repo evidence for the raw layer (design: wiki/developments/repo-pack-design.md).

Verbs:
  clone          --url U [--sha S] [--sparse a,b]          → ~/.llm-wiki/repos/<owner>-<repo>/ (shallow, blob-filtered, sha-pinned)
  pack-and-write --repo <slug> --paths p1,p2,… [--globs g1,g2,…] [--tree-depth N] --ledger-id ID
                 [--slice NAME] [--allow-large '<why>'] [--allow-degraded '<why>'] [--capture-write PATH]
                 Emits the pack to a temp file, self-checks it (footer marker · header count == section count),
                 then invokes capture_write.py IN-PROCESS on exit-0, propagating failure. Never a pipe.
  clean          --repo <slug>                              → removes the clone; refuses any path outside the store.

Caps (derivations in the design): --max-files 40 · per-file truncate 65536 B (judgement-set, marker emitted)
· soft-warn 122880 B (≈30k tokens: the ≈100k lane anchor minus the ≈65–70k inherited prefix)
· hard refuse 307200 B without --allow-large (2.5× the warn, stated headroom).
Skips, each noted in the header: binaries (NUL sniff) · git-LFS pointers · control-byte-bearing files (packed, noted).
Fence rule: per-file fence length = longest interior backtick run + 1, minimum 3 (capture_write exact-closer semantics).
"""
import argparse, datetime, os, re, subprocess, sys, tempfile

STORE = os.path.expanduser("~/.llm-wiki/repos")
FOOTER = "<!-- repo-pack:end -->"
MAX_FILES = 40
TRUNCATE_AT = 65536          # bytes/file — set by judgement, unmeasured (design §Caps)
SOFT_WARN = 122880           # 120 KiB ≈ 30k tokens
HARD_CAP = 307200            # 300 KiB = 2.5× soft-warn
LFS_HEAD = b"version https://git-lfs"
CONTROL = re.compile(rb"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

def die(msg, code=2):
    print(f"repo_pack: {msg}", file=sys.stderr); sys.exit(code)

def run(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        die(f"command failed ({' '.join(cmd[:3])}…): {r.stderr.strip()[:300]}")
    return r.stdout.strip()

def slug_of(url):
    m = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$", url)
    if not m: die(f"cannot derive owner/repo slug from URL: {url}")
    return f"{m.group(1)}-{m.group(2)}", m.group(1), m.group(2)

def cmd_clone(a):
    os.makedirs(STORE, exist_ok=True)
    slug, _, _ = slug_of(a.url)
    dest = os.path.join(STORE, slug)
    if os.path.isdir(dest):
        have = run(["git", "rev-parse", "HEAD"], cwd=dest)
        if a.sha and have != a.sha and not a.force_refresh:
            die(f"{slug} exists at {have[:12]}, requested {a.sha[:12]} — pass --force-refresh to replace")
        print(f"reuse {dest} @ {have}"); return
    cmd = ["git", "clone", "--depth", "1", "--filter=blob:none"]
    if a.sparse: cmd += ["--sparse"]
    cmd += [a.url, dest]
    run(cmd)
    if a.sparse:
        run(["git", "sparse-checkout", "set"] + a.sparse.split(","), cwd=dest)
    if a.sha:
        run(["git", "fetch", "--depth", "1", "origin", a.sha], cwd=dest)
        run(["git", "checkout", a.sha], cwd=dest)
    sha = run(["git", "rev-parse", "HEAD"], cwd=dest)
    print(f"cloned {dest} @ {sha}")

def fence_for(text):
    runs = re.findall(r"`{3,}", text)
    return "`" * max([3] + [len(r) + 1 for r in runs])

def build_pack(repo_dir, rel_paths, url, sha, slice_name, tree_depth, rationale):
    owner_repo = re.sub(r"^.*[:/]([^/:]+/[^/]+?)(?:\.git)?$", r"\1", url.rstrip("/"))
    lines, skipped, noted, sections = [], [], [], 0
    date = datetime.date.today().isoformat()
    tree = run(["find", ".", "-maxdepth", str(tree_depth), "-not", "-path", "./.git*", "-print"], cwd=repo_dir)
    bodies = []
    for rel in rel_paths:
        p = os.path.join(repo_dir, rel)
        if not os.path.isfile(p):
            die(f"selected path missing in clone: {rel}")
        raw = open(p, "rb").read()
        if raw.startswith(LFS_HEAD):
            skipped.append(f"{rel} (git-LFS pointer)"); continue
        if b"\x00" in raw[:8192]:
            skipped.append(f"{rel} (binary)"); continue
        if CONTROL.search(raw):
            noted.append(f"{rel} (control bytes present — sanitiser strip applies)")
        trunc = ""
        if len(raw) > TRUNCATE_AT:
            raw = raw[:TRUNCATE_AT]; trunc = f"\n[TRUNCATED at {TRUNCATE_AT} bytes]"
        text = raw.decode("utf-8", errors="replace")
        f = fence_for(text)
        bodies.append(f"## {rel}\n\n{f}\n{text}{trunc}\n{f}\n")
        sections += 1
    if sections == 0:
        die("empty selection after skips — a pack of nothing is refused (§11)")
    slice_part = f"/{slice_name}" if slice_name else ""
    header = (f"# Repo pack: {owner_repo} @ {sha[:12]}{slice_part}\n\n"
              f"- repo: {url}\n- sha: {sha}\n- date: {date}\n- files: {sections}\n"
              f"- selection: {rationale}\n"
              + (f"- skipped: {'; '.join(skipped)}\n" if skipped else "")
              + (f"- noted: {'; '.join(noted)}\n" if noted else ""))
    tf = fence_for(tree)
    body = header + f"\n## Tree (depth-capped)\n\n{tf}\n{tree}\n{tf}\n\n" + "\n".join(bodies) + f"\n{FOOTER}\n"
    return body, sections

FENCED = re.compile(r"^(?P<f>`{3,})[^\n]*\n.*?^(?P=f)[ \t]*$", re.M | re.S)

def self_check(text):
    if not text.rstrip().endswith(FOOTER):
        return "footer marker missing (truncated emission?)"
    m = re.search(r"^- files: (\d+)$", text, re.M)
    prose = FENCED.sub("", text)   # packed file bodies live inside fences; count sections outside them only
    n = len(re.findall(r"^## (?!Tree)", prose, re.M))
    if not m or int(m.group(1)) != n:
        return f"header file-count {m.group(1) if m else '?'} != emitted sections {n}"
    return None

def cmd_pack(a):
    repo_dir = os.path.join(STORE, a.repo)
    if not os.path.isdir(repo_dir): die(f"no clone at {repo_dir} — run clone first")
    url = run(["git", "remote", "get-url", "origin"], cwd=repo_dir)
    sha = run(["git", "rev-parse", "HEAD"], cwd=repo_dir)
    rels = [p for p in (a.paths.split(",") if a.paths else []) if p]
    if a.globs:
        import glob as g
        for pat in a.globs.split(","):
            rels += [os.path.relpath(x, repo_dir) for x in g.glob(os.path.join(repo_dir, pat), recursive=True) if os.path.isfile(x)]
    rels = sorted(dict.fromkeys(rels))
    if not rels: die("empty selection — name --paths or --globs")
    if len(rels) > a.max_files: die(f"{len(rels)} files exceeds --max-files {a.max_files}")
    rationale = a.rationale or f"{len(rels)} paths named after in-clone study"
    body, n = build_pack(repo_dir, rels, url, sha, a.slice, a.tree_depth, rationale)
    size = len(body.encode())
    if size > HARD_CAP and not a.allow_large:
        die(f"pack {size} B exceeds hard cap {HARD_CAP} — split the slice or pass --allow-large '<why>'")
    if size > SOFT_WARN:
        print(f"repo_pack: WARN pack {size} B exceeds soft-warn {SOFT_WARN} (lane-budget derivation in the design)", file=sys.stderr)
    err = self_check(body)
    if err: die(f"self-check failed: {err}")
    fd, tmp = tempfile.mkstemp(suffix=".md", prefix="repo-pack-")
    with os.fdopen(fd, "w") as fh: fh.write(body)
    print(f"pack ok: {n} files · {size} B · sha {sha[:12]} · tmp {tmp}")
    if a.no_write:
        return
    gh = "github.com" in url
    prov = (f"{url.rstrip('/').removesuffix('.git')}/tree/{sha}" + (f"/{a.slice}" if a.slice and gh else (f"#{a.slice}" if a.slice else ""))) if gh \
           else f"{url}#{a.slice or 'pack'}"
    cw = a.capture_write or os.path.join(os.path.dirname(os.path.abspath(__file__)), "capture_write.py")
    if not os.path.isfile(cw): die("capture_write.py not found — sole-write rule, STOP")
    cmd = [sys.executable, cw, "write", "--url", prov, "--engine", "repo-pack", "--ledger-id", a.ledger_id]
    if a.title: cmd += ["--title", a.title]
    if a.allow_degraded: cmd += ["--allow-degraded", a.allow_degraded]
    r = subprocess.run(cmd, stdin=open(tmp), )
    sys.exit(r.returncode)

def cmd_clean(a):
    target = os.path.realpath(os.path.join(STORE, a.repo))
    store = os.path.realpath(STORE)
    if not (target.startswith(store + os.sep) and len(target) > len(store) + 1):
        die(f"refusing to clean outside the store: {target}")
    if not os.path.isdir(target): die(f"no clone at {target}")
    subprocess.run(["rm", "-rf", target], check=True)
    print(f"cleaned {target}")

def main():
    ap = argparse.ArgumentParser(prog="repo_pack")
    sub = ap.add_subparsers(dest="verb", required=True)
    c = sub.add_parser("clone"); c.add_argument("--url", required=True); c.add_argument("--sha"); c.add_argument("--sparse"); c.add_argument("--force-refresh", action="store_true")
    p = sub.add_parser("pack-and-write")
    p.add_argument("--repo", required=True); p.add_argument("--paths"); p.add_argument("--globs")
    p.add_argument("--tree-depth", type=int, default=3); p.add_argument("--ledger-id", required=True)
    p.add_argument("--slice"); p.add_argument("--title"); p.add_argument("--rationale")
    p.add_argument("--max-files", type=int, default=MAX_FILES)
    p.add_argument("--allow-large"); p.add_argument("--allow-degraded")
    p.add_argument("--capture-write"); p.add_argument("--no-write", action="store_true")
    x = sub.add_parser("clean"); x.add_argument("--repo", required=True)
    a = ap.parse_args()
    {"clone": cmd_clone, "pack-and-write": cmd_pack, "clean": cmd_clean}[a.verb](a)

if __name__ == "__main__":
    main()
