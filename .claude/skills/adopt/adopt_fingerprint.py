#!/usr/bin/env python3
"""adopt_fingerprint.py — bounded, read-only fingerprint of a third-party skill or tool repository.

    adopt_fingerprint.py <repo-dir> [--json]

Reports (stdout only; never writes, never fetches):
  * README(s), LICENSE (licence family by its own text), manifests (package.json, pyproject.toml,
    .claude-plugin/plugin.json, .claude-plugin/marketplace.json), every hooks.json (events x commands),
    every SKILL.md frontmatter (name, description bytes, disable-model-invocation), file and directory
    counts, size, `git rev-parse HEAD`, `git tag --points-at HEAD` and the origin URL when a repository.
  * A tree grep for exec and network primitives, per file class, with a control on the same run: the
    same scan function is applied to an embedded text that plants every pattern, and the run reports
    PROBE FAILED (exit 2) if any planted pattern is missed. A zero is never bare: it carries the number
    of files scanned and the control result.
  * Mechanical signals for the assessment (a floor the head can only raise, never lower): a hook or a
    network primitive in code -> at least propose-first; exec primitives -> runs code; a non-commercial
    licence -> reference in place; an upstream `disable-model-invocation: true` -> upstream intends
    by-name; the repository's shape (single skill, skill collection, plugin, package, documents only).

Bounds (safety caps with headroom, not thresholds that decide anything): MAX_FILES 20,000 walked (the
largest skill repository seen so far holds ~1,500 files); MAX_FILE_BYTES 2 MiB per scanned file (a
text file above that is data, not code; it is counted, not read); MAX_TOTAL_BYTES 200 MiB scanned in
all (beyond it the scan stops and reports itself truncated). Directories never walked: .git,
node_modules, virtual environments, caches and build output.

Exit: 0 fingerprint printed · 2 PROBE FAILED (not a directory, nothing scanned, control missed).
"""
import argparse
import json
import os
import re
import subprocess
import sys

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".mypy_cache", ".pytest_cache",
             ".tox", ".eggs", "dist", "build", ".next", ".cache"}
MAX_FILES = 20000
MAX_FILE_BYTES = 2 * 1024 * 1024
MAX_TOTAL_BYTES = 200 * 1024 * 1024
# The primitives the design names (capability-register-design D3 step 0), as fixed strings.
PRIMITIVES = ["subprocess", "os.system", "requests.", "urllib", "fetch(", "curl ", "wget ",
              "http.client", "socket."]
EXEC_PRIMITIVES = {"subprocess", "os.system"}
NETWORK_PRIMITIVES = {"requests.", "urllib", "fetch(", "curl ", "wget ", "http.client", "socket."}
CODE_CLASSES = {"py", "js/ts", "sh", "other-code"}
# The control text plants every pattern once; the scan must count each (CLAUDE.md §11: a zero-findings
# scan is a claim until the probe is shown to hit a known positive).
CONTROL_TEXT = ("import subprocess\nsubprocess.run(['x'])\nos.system('x')\nrequests.get(u)\n"
                "import urllib\nfetch(u)\ncurl -sL u\nwget u\nhttp.client.HTTPConnection\n"
                "socket.socket()\n").encode("utf-8")

CLASS_BY_EXT = {
    ".py": "py",
    ".js": "js/ts", ".mjs": "js/ts", ".cjs": "js/ts", ".ts": "js/ts", ".tsx": "js/ts", ".jsx": "js/ts",
    ".sh": "sh", ".bash": "sh", ".zsh": "sh",
    ".md": "md", ".markdown": "md", ".mdx": "md", ".txt": "md", ".rst": "md",
    ".json": "json/yaml", ".yaml": "json/yaml", ".yml": "json/yaml", ".toml": "json/yaml",
    ".rb": "other-code", ".go": "other-code", ".rs": "other-code", ".java": "other-code",
    ".c": "other-code", ".cc": "other-code", ".cpp": "other-code", ".h": "other-code",
    ".pl": "other-code", ".php": "other-code", ".swift": "other-code", ".kt": "other-code",
}
LICENCE_PATTERNS = [
    (r"Creative Commons Attribution-NonCommercial-ShareAlike", "CC-BY-NC-SA"),
    (r"Creative Commons Attribution-NonCommercial", "CC-BY-NC"),
    (r"Creative Commons Attribution-ShareAlike", "CC-BY-SA"),
    (r"Creative Commons Attribution", "CC-BY"),
    (r"CC0 1\.0|Creative Commons Zero", "CC0"),
    (r"PolyForm Noncommercial", "PolyForm-NC"),
    (r"Apache License", "Apache"),
    (r"GNU AFFERO GENERAL PUBLIC LICENSE", "AGPL"),
    (r"GNU LESSER GENERAL PUBLIC LICENSE", "LGPL"),
    (r"GNU GENERAL PUBLIC LICENSE", "GPL"),
    (r"Mozilla Public License", "MPL"),
    (r"Permission is hereby granted, free of charge|MIT License", "MIT"),
    (r"Redistribution and use in source and binary forms", "BSD"),
    (r"ISC License", "ISC"),
    (r"This is free and unencumbered software|The Unlicense", "Unlicense"),
    (r"Business Source License", "BSL"),
    (r"Server Side Public License", "SSPL"),
]
NON_COMMERCIAL = {"CC-BY-NC", "CC-BY-NC-SA", "PolyForm-NC"}


def fail(msg):
    print("PROBE FAILED: " + msg)
    sys.exit(2)


# ---------------------------------------------------------------- frontmatter (YAML subset) ----
def parse_frontmatter(text):
    """Return (mapping, body). Handles the shapes SKILL.md files use in practice: `k: v` plain
    scalars (with indented continuation lines), double- and single-quoted scalars (multi-line),
    `>`/`|` block scalars, and one level of nested mapping (kept as a dict). Anything stranger
    is kept as its raw text; nothing here needs a YAML library."""
    if not text.startswith("---"):
        return {}, text
    lines = text.split("\n")
    if lines[0].strip() != "---":
        return {}, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, text
    fm_lines, body = lines[1:end], "\n".join(lines[end + 1:])
    fm = {}
    i = 0
    key_re = re.compile(r"^([A-Za-z0-9_-]+):\s*(.*)$")
    while i < len(fm_lines):
        line = fm_lines[i]
        m = key_re.match(line)
        if not m or line[:1] in (" ", "\t"):
            i += 1
            continue
        key, val = m.group(1), m.group(2).rstrip()
        if val and val[0] in ">|" and re.fullmatch(r"[>|][+-]?", val):
            block = []
            i += 1
            while i < len(fm_lines) and (fm_lines[i][:1] in (" ", "\t") or fm_lines[i].strip() == ""):
                block.append(fm_lines[i].strip())
                i += 1
            while block and block[-1] == "":
                block.pop()
            fm[key] = (" ".join(b for b in block if b) if val[0] == ">" else "\n".join(block))
            continue
        if val[:1] == '"':
            buf = val[1:]
            while True:
                m2 = re.search(r'(?<!\\)"', buf)
                if m2:
                    fm[key] = buf[:m2.start()].replace('\\"', '"').replace("\\\\", "\\")
                    break
                i += 1
                if i >= len(fm_lines):
                    fm[key] = buf
                    break
                buf += " " + fm_lines[i].strip()
            i += 1
            continue
        if val[:1] == "'":
            buf = val[1:]
            while True:
                m2 = re.search(r"'(?!')", buf)
                if m2:
                    fm[key] = buf[:m2.start()].replace("''", "'")
                    break
                i += 1
                if i >= len(fm_lines):
                    fm[key] = buf
                    break
                buf += " " + fm_lines[i].strip()
            i += 1
            continue
        if val == "":
            sub = {}
            raw = []
            i += 1
            while i < len(fm_lines) and (fm_lines[i][:1] in (" ", "\t") or fm_lines[i].strip() == ""):
                raw.append(fm_lines[i])
                m3 = key_re.match(fm_lines[i].strip())
                if m3:
                    sub[m3.group(1)] = m3.group(2).strip().strip('"').strip("'")
                i += 1
            fm[key] = sub if sub else "\n".join(raw).strip()
            continue
        buf = val
        i += 1
        while i < len(fm_lines) and fm_lines[i][:1] in (" ", "\t") and fm_lines[i].strip():
            buf += " " + fm_lines[i].strip()
            i += 1
        fm[key] = buf.strip()
    return fm, body


def truthy(v):
    return isinstance(v, str) and v.strip().lower() in ("true", "yes", "on")


# ---------------------------------------------------------------- walk and scan -----------------
def file_class(relpath, head):
    ext = os.path.splitext(relpath)[1].lower()
    if ext in CLASS_BY_EXT:
        return CLASS_BY_EXT[ext]
    if head.startswith(b"#!"):
        first = head.split(b"\n", 1)[0]
        if b"python" in first:
            return "py"
        if b"node" in first:
            return "js/ts"
        if b"sh" in first:
            return "sh"
    return "other"


def scan_bytes(data):
    """Count every primitive in one byte string. The control runs through this same function."""
    return {p: data.count(p.encode("utf-8")) for p in PRIMITIVES}


def walk(repo):
    files, dirs = [], 0
    truncated = False
    for root, dnames, fnames in os.walk(repo):
        dnames[:] = sorted(d for d in dnames if d not in SKIP_DIRS)
        dirs += len(dnames)
        for f in sorted(fnames):
            p = os.path.join(root, f)
            if os.path.islink(p) and not os.path.isfile(p):
                continue
            try:
                size = os.path.getsize(p)
            except OSError:
                continue
            files.append((os.path.relpath(p, repo), size))
            if len(files) >= MAX_FILES:
                truncated = True
                break
        if truncated:
            break
    return files, dirs, truncated


def scan_tree(repo, files):
    per_class = {}      # class -> {pattern: count}
    files_by_class = {}
    hit_files = []
    scanned = skipped_big = skipped_binary = 0
    total = 0
    truncated = False
    for rel, size in files:
        if total > MAX_TOTAL_BYTES:
            truncated = True
            break
        if size > MAX_FILE_BYTES:
            skipped_big += 1
            continue
        try:
            with open(os.path.join(repo, rel), "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        head = data[:8192]
        if b"\x00" in head:
            skipped_binary += 1
            continue
        cls = file_class(rel, head)
        files_by_class[cls] = files_by_class.get(cls, 0) + 1
        scanned += 1
        total += len(data)
        counts = scan_bytes(data)
        n = sum(counts.values())
        if n:
            hit_files.append((rel, cls, n, {k: v for k, v in counts.items() if v}))
            slot = per_class.setdefault(cls, {p: 0 for p in PRIMITIVES})
            for p, c in counts.items():
                slot[p] += c
    return {"per_class": per_class, "files_by_class": files_by_class, "hit_files": hit_files,
            "scanned": scanned, "skipped_big": skipped_big, "skipped_binary": skipped_binary,
            "bytes_scanned": total, "truncated": truncated}


def run_control():
    counts = scan_bytes(CONTROL_TEXT)
    missed = [p for p in PRIMITIVES if counts[p] < 1]
    return {"planted": len(PRIMITIVES), "hit": len(PRIMITIVES) - len(missed), "missed": missed,
            "ok": not missed}


# ---------------------------------------------------------------- readers -----------------------
def read_text(path, limit=None):
    try:
        with open(path, "rb") as fh:
            data = fh.read(limit) if limit else fh.read()
    except OSError:
        return None
    return data.decode("utf-8", errors="replace")


def find_named(repo, files, names, anywhere=False):
    out = []
    lower = {n.lower() for n in names}
    for rel, size in files:
        base = os.path.basename(rel)
        if base.lower() in lower and (anywhere or os.sep not in rel):
            out.append((rel, size))
    return out


def readmes(repo, files):
    out = []
    for rel, size in files:
        base = os.path.basename(rel).lower()
        if os.sep in rel or not base.startswith("readme"):
            continue
        text = read_text(os.path.join(repo, rel), 4096) or ""
        title = ""
        for line in text.splitlines():
            if line.startswith("#"):
                title = line.lstrip("#").strip()
                break
        out.append({"path": rel, "bytes": size, "title": title})
    return out


def licence(repo, files):
    cands = find_named(repo, files, ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "LICENCE.md",
                                     "COPYING", "COPYING.md", "LICENSE.rst"])
    if not cands:
        return {"file": None, "family": "none found", "bytes": 0}
    rel, size = cands[0]
    text = read_text(os.path.join(repo, rel), 8192) or ""
    family = "unrecognised"
    for pat, fam in LICENCE_PATTERNS:
        if re.search(pat, text):
            family = fam
            break
    ver = re.search(r"\b(\d\.\d)\b", text[:600]) if family != "unrecognised" else None
    if ver and family in ("CC-BY-NC", "CC-BY-NC-SA", "CC-BY", "CC-BY-SA", "Apache", "GPL", "LGPL",
                          "AGPL", "MPL", "CC0"):
        family = family + "-" + ver.group(1)
    return {"file": rel, "family": family, "bytes": size,
            "first_line": (text.splitlines() or [""])[0].strip()[:80]}


def load_json(path):
    text = read_text(path)
    if text is None:
        return None
    try:
        return json.loads(text)
    except ValueError:
        return {"_unparseable": True}


def manifests(repo):
    out = {}
    p = os.path.join(repo, "package.json")
    if os.path.isfile(p):
        d = load_json(p) or {}
        out["package.json"] = {"name": d.get("name"), "version": d.get("version"),
                               "license": d.get("license"), "bin": bool(d.get("bin")),
                               "scripts": len(d.get("scripts") or {}),
                               "dependencies": len(d.get("dependencies") or {})}
    p = os.path.join(repo, "pyproject.toml")
    if os.path.isfile(p):
        text = read_text(p) or ""
        name = re.search(r'(?m)^name\s*=\s*"([^"]+)"', text)
        ver = re.search(r'(?m)^version\s*=\s*"([^"]+)"', text)
        lic = re.search(r'(?m)^license\s*=\s*(?:\{[^}]*?(?:text|file)\s*=\s*)?"([^"]+)"', text)
        out["pyproject.toml"] = {"name": name.group(1) if name else None,
                                 "version": ver.group(1) if ver else None,
                                 "license": lic.group(1) if lic else None,
                                 "scripts": bool(re.search(r"(?m)^\[project\.scripts\]", text))}
    p = os.path.join(repo, ".claude-plugin", "plugin.json")
    if os.path.isfile(p):
        d = load_json(p) or {}
        out[".claude-plugin/plugin.json"] = {"name": d.get("name"), "version": d.get("version"),
                                            "description_bytes": len((d.get("description") or "").encode("utf-8")),
                                            "hooks_key": "hooks" in d}
    p = os.path.join(repo, ".claude-plugin", "marketplace.json")
    if os.path.isfile(p):
        d = load_json(p) or {}
        out[".claude-plugin/marketplace.json"] = {"name": d.get("name"),
                                                 "plugins": len(d.get("plugins") or [])}
    return out


def hooks(repo, files):
    out = []
    for rel, size in find_named(repo, files, ["hooks.json"], anywhere=True):
        d = load_json(os.path.join(repo, rel)) or {}
        events = d.get("hooks", d) if isinstance(d, dict) else {}
        summary = {}
        if isinstance(events, dict):
            for ev, entries in events.items():
                n = 0
                matchers = []
                if isinstance(entries, list):
                    for e in entries:
                        if isinstance(e, dict):
                            matchers.append(str(e.get("matcher", "*")))
                            n += len(e.get("hooks") or [])
                summary[ev] = {"commands": n, "matchers": matchers}
        out.append({"path": rel, "bytes": size, "events": summary})
    # settings files that carry a hooks key are hook carriers too
    for rel, size in find_named(repo, files, ["settings.json", "settings.local.json"], anywhere=True):
        d = load_json(os.path.join(repo, rel)) or {}
        if isinstance(d, dict) and d.get("hooks"):
            out.append({"path": rel, "bytes": size,
                        "events": {ev: {"commands": len(v) if isinstance(v, list) else 1, "matchers": []}
                                   for ev, v in d["hooks"].items()}})
    return out


def skills(repo, files):
    out = []
    for rel, size in files:
        if os.path.basename(rel) != "SKILL.md":
            continue
        text = read_text(os.path.join(repo, rel)) or ""
        fm, _ = parse_frontmatter(text)
        desc = fm.get("description", "")
        if not isinstance(desc, str):
            desc = json.dumps(desc)
        dmi = fm.get("disable-model-invocation")
        meta = fm.get("metadata") if isinstance(fm.get("metadata"), dict) else {}
        out.append({"path": rel, "bytes": size, "name": fm.get("name"),
                    "description_bytes": len(desc.encode("utf-8")),
                    "disable_model_invocation": (True if truthy(dmi) else False if dmi is not None else None),
                    "user_invocable": fm.get("user-invocable"),
                    "frontmatter": bool(fm),
                    "metadata_license": meta.get("license"), "metadata_version": meta.get("version")})
    return out


def git_info(repo):
    if not os.path.exists(os.path.join(repo, ".git")):
        return {"repository": False}
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_OPTIONAL_LOCKS="0")

    def g(*args):
        try:
            r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True,
                               env=env, timeout=20)
        except (OSError, subprocess.SubprocessError) as e:
            return None, str(e)
        return (r.stdout.strip() if r.returncode == 0 else None), r.stderr.strip()
    head, err = g("rev-parse", "HEAD")
    if head is None:
        return {"repository": True, "head": None, "error": err or "git unavailable"}
    tags, _ = g("tag", "--points-at", "HEAD")
    remote, _ = g("remote", "get-url", "origin")
    shallow, _ = g("rev-parse", "--is-shallow-repository")
    publisher = None
    if remote:
        m = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$", remote)
        if m:
            publisher = m.group(1)
    return {"repository": True, "head": head, "short": head[:7], "tags": tags.split() if tags else [],
            "remote": remote, "publisher": publisher, "shallow": shallow == "true"}


# ---------------------------------------------------------------- signals -----------------------
def signals(fp):
    sig = []
    floor = "none"
    per = fp["primitives"]["per_class"]
    code_exec = sum(per.get(c, {}).get(p, 0) for c in CODE_CLASSES for p in EXEC_PRIMITIVES)
    code_net = sum(per.get(c, {}).get(p, 0) for c in CODE_CLASSES for p in NETWORK_PRIMITIVES)
    doc_net = sum(per.get(c, {}).get(p, 0) for c in per if c not in CODE_CLASSES for p in NETWORK_PRIMITIVES)
    if fp["hooks"]:
        sig.append("hooks present -> at least propose-first (a hook reaches every session)")
        floor = "propose-first"
    if code_net:
        sig.append(f"network primitives in code ({code_net}) -> a possible external effect: at least propose-first")
        floor = "propose-first"
    if code_exec:
        sig.append(f"exec primitives in code ({code_exec}) -> runs code: by-name or propose-first under the assignment rule")
    if doc_net and not code_net:
        sig.append(f"network primitives only in documents ({doc_net}) -> install or usage text, not a run-time effect; read them")
    fam = fp["licence"]["family"]
    if any(fam.startswith(nc) for nc in NON_COMMERCIAL):
        sig.append(f"non-commercial licence ({fam}) -> reference in place; never copy into the vault or the public framework repo")
    if fam in ("none found", "unrecognised"):
        sig.append(f"licence {fam} -> ask before installing; record the terms on the tool page")
    hidden = [s["name"] or s["path"] for s in fp["skills"] if s["disable_model_invocation"]]
    if hidden:
        sig.append("upstream SKILL.md carries disable-model-invocation: true (" + ", ".join(hidden) + ") -> upstream intends by-name")
    n_sk = len(fp["skills"])
    if ".claude-plugin/plugin.json" in fp["manifests"]:
        shape = "plugin (.claude-plugin/plugin.json)" + (f" with {n_sk} SKILL.md" if n_sk else "")
    elif n_sk == 1 and os.sep not in fp["skills"][0]["path"]:
        shape = "single skill (SKILL.md at the root)"
    elif n_sk > 1:
        shape = f"skill collection ({n_sk} SKILL.md) -> one row per picked skill, the parent pinned once"
    elif n_sk == 1:
        shape = "single skill (" + fp["skills"][0]["path"] + ")"
    elif "package.json" in fp["manifests"] and fp["manifests"]["package.json"].get("bin"):
        shape = "CLI package (package.json with bin)"
    elif "pyproject.toml" in fp["manifests"] and fp["manifests"]["pyproject.toml"].get("scripts"):
        shape = "CLI package (pyproject.toml with project.scripts)"
    elif fp["manifests"]:
        shape = "package (" + ", ".join(fp["manifests"]) + ")"
    else:
        shape = "documents only (no SKILL.md, no manifest)"
    if floor == "none":
        sig.append("no mechanical floor -> the level is the head's judgement under the assignment rule (auto only when it serves inside a vault workflow)")
    return {"floor": floor, "shape": shape, "notes": sig}


# ---------------------------------------------------------------- main --------------------------
def human_size(n):
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unit == "GiB":
            return f"{n:,.0f} {unit}" if unit == "B" else f"{n:,.1f} {unit}"
        n /= 1024.0


def fingerprint(repo):
    files, dirs, truncated = walk(repo)
    if not files:
        fail(f"no files under {repo} (empty tree, nothing to fingerprint)")
    prim = scan_tree(repo, files)
    control = run_control()
    if not control["ok"]:
        fail("the primitive scan missed planted control patterns: " + ", ".join(control["missed"]))
    if prim["scanned"] == 0:
        fail(f"no text file scanned under {repo} (binary or oversized only: {prim['skipped_binary']} binary, {prim['skipped_big']} oversized)")
    fp = {
        "repo": os.path.abspath(repo),
        "git": git_info(repo),
        "counts": {"files": len(files), "dirs": dirs, "bytes": sum(s for _, s in files),
                   "walk_truncated": truncated},
        "readmes": readmes(repo, files),
        "licence": licence(repo, files),
        "manifests": manifests(repo),
        "hooks": hooks(repo, files),
        "skills": skills(repo, files),
        "primitives": prim,
        "control": control,
    }
    fp["signals"] = signals(fp)
    return fp


def render(fp):
    g = fp["git"]
    if g.get("repository") and g.get("head"):
        pin = f"{g['short']}" + (f" (tag {', '.join(g['tags'])})" if g["tags"] else " (no tag at HEAD)")
        if g.get("remote"):
            pin += f" · origin {g['remote']}" + (f" · publisher {g['publisher']}" if g.get("publisher") else "")
        if g.get("shallow"):
            pin += " · shallow"
    elif g.get("repository"):
        pin = "git repository, HEAD unreadable: " + (g.get("error") or "")
    else:
        pin = "not a git repository (no pin; record the source path or archive hash)"
    c = fp["counts"]
    rows = [
        ("repo", fp["repo"]),
        ("pin", pin),
        ("tree", f"{c['files']:,} files · {c['dirs']:,} dirs · {human_size(c['bytes'])}" + (" · WALK TRUNCATED at MAX_FILES" if c["walk_truncated"] else "")),
        ("readme", " · ".join(f"{r['path']} ({r['bytes']:,} B" + (f", \"{r['title']}\")" if r["title"] else ")") for r in fp["readmes"]) or "none at the root"),
        ("licence", (f"{fp['licence']['family']} ({fp['licence']['file']}, {fp['licence']['bytes']:,} B)" if fp["licence"]["file"] else "none found")),
    ]
    if fp["manifests"]:
        parts = []
        for k, v in fp["manifests"].items():
            inner = ", ".join(f"{a} {b}" for a, b in v.items() if b not in (None, False, 0, ""))
            parts.append(k + " (" + (inner or "present, nothing parsed") + ")")
        rows.append(("manifests", " · ".join(parts)))
    else:
        rows.append(("manifests", "none of package.json · pyproject.toml · .claude-plugin/plugin.json · .claude-plugin/marketplace.json"))
    if fp["hooks"]:
        parts = []
        for h in fp["hooks"]:
            ev = "; ".join(f"{e}×{d['commands']}" + (f" [{'|'.join(d['matchers'])}]" if d["matchers"] else "") for e, d in h["events"].items()) or "no events parsed"
            parts.append(f"{h['path']}: {ev}")
        rows.append(("hooks.json", f"{len(fp['hooks'])} — " + " · ".join(parts)))
    else:
        rows.append(("hooks.json", "0"))
    if fp["skills"]:
        for s in fp["skills"]:
            dmi = {True: "true", False: "false", None: "absent"}[s["disable_model_invocation"]]
            extra = ""
            if s["metadata_license"]:
                extra += f" · metadata.license {s['metadata_license']}"
            if s["metadata_version"]:
                extra += f" · metadata.version {s['metadata_version']}"
            rows.append(("SKILL.md", f"{s['path']}: name {s['name'] or '(none)'} · description {s['description_bytes']:,} B · disable-model-invocation {dmi}" + (" · NO FRONTMATTER" if not s["frontmatter"] else "") + extra))
    else:
        rows.append(("SKILL.md", "none"))
    out = ["| field | value |", "|---|---|"]
    out += [f"| {k} | {v} |" for k, v in rows]
    p = fp["primitives"]
    ctl = fp["control"]
    total = sum(sum(d.values()) for d in p["per_class"].values())
    cls_summary = " · ".join(f"{k} {v}" for k, v in sorted(p["files_by_class"].items()))
    out.append("")
    out.append(f"exec/network primitives: {total} hits in {len(p['hit_files'])} of {p['scanned']:,} files scanned ({cls_summary})"
               f"{' · ' + str(p['skipped_binary']) + ' binary skipped' if p['skipped_binary'] else ''}"
               f"{' · ' + str(p['skipped_big']) + ' oversized skipped' if p['skipped_big'] else ''}"
               f"{' · SCAN TRUNCATED at MAX_TOTAL_BYTES' if p['truncated'] else ''}"
               f" · control {'OK' if ctl['ok'] else 'FAILED'} ({ctl['hit']}/{ctl['planted']} planted primitives hit)")
    if total:
        classes = sorted(p["per_class"])
        out.append("| primitive | " + " | ".join(classes) + " |")
        out.append("|---|" + "---|" * len(classes))
        for prim in PRIMITIVES:
            vals = [p["per_class"][c].get(prim, 0) for c in classes]
            if any(vals):
                out.append(f"| `{prim}` | " + " | ".join(str(v) for v in vals) + " |")
        shown = sorted(p["hit_files"], key=lambda t: -t[2])[:20]
        out.append("hit files (top " + str(len(shown)) + "): " + " · ".join(f"{rel} [{cls}] {n}" for rel, cls, n, _ in shown))
    s = fp["signals"]
    out.append("")
    out.append(f"shape: {s['shape']}")
    out.append(f"floor: {s['floor']}")
    for n in s["notes"]:
        out.append("signal: " + n)
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Bounded, read-only fingerprint of a skill or tool repository.")
    ap.add_argument("repo")
    ap.add_argument("--json", action="store_true", help="machine form (one JSON object)")
    a = ap.parse_args(argv)
    repo = os.path.abspath(os.path.expanduser(a.repo))
    if not os.path.isdir(repo):
        fail(f"{repo} is not a directory")
    fp = fingerprint(repo)
    if a.json:
        print(json.dumps(fp, indent=1, sort_keys=True, ensure_ascii=False))
    else:
        print(render(fp))
    return 0


if __name__ == "__main__":
    sys.exit(main())
