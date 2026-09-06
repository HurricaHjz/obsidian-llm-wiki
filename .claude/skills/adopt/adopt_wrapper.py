#!/usr/bin/env python3
"""adopt_wrapper.py — create the carrier of a use level under the user-level skills root.

    adopt_wrapper.py --name N --upstream DIR --level auto|propose-first|by-name
                     [--description TEXT] [--limits FILE] [--skills-root DIR] [--force] [--write]

Dry-run by default: prints the plan and, for a wrapper level, the full SKILL.md it would write.
With --write it creates:
  * auto           -> <skills-root>/<N>            a symlink to DIR (the add-on's own description lists it)
  * propose-first  -> <skills-root>/<N>/SKILL.md   a visible wrapper carrying the gate paragraph from
                                                   templates/wrapper-propose-first.md, plus
                      <skills-root>/<N>/upstream   a symlink to DIR
  * by-name        -> the same wrapper from templates/wrapper-by-name.md with
                      `disable-model-invocation: true` in the frontmatter (hidden from every listing;
                      `/N` still invokes it)

The skills root defaults to ~/.claude/skills, derived from the running user's home at run time.
An existing entry is never overwritten without --force; a second identical --write is a no-op
(reported as `unchanged`). --force replaces only a wrapper-shaped entry (SKILL.md + upstream) or a
symlink; a directory holding anything else is refused, since this script never deletes a user's files.
Writes are atomic: the text is encoded first, written to a temporary file in the target directory
and moved into place with os.replace.

Exit: 0 done or unchanged (or dry-run) · 1 exists and differs (no --force) · 2 PROBE FAILED (bad
name, upstream without SKILL.md, template missing its sentinel, unsafe replacement).
"""
import argparse
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
TEMPLATES = os.path.join(HERE, "templates")
LEVELS = ("auto", "propose-first", "by-name")
# The gate sentinels: the phrases every wrapper of a level must carry. adopt_acceptance.py checks the
# same strings, so a template edit that drops one is refused here at write time rather than found
# later as an acceptance failure. The propose-first pair is the wording the live wrappers share.
GATE_SENTINELS = {
    "propose-first": ("Use level `propose-first`", "wait for the owner's yes"),
    "by-name": ("Use level `by-name`", "disable-model-invocation: true"),
}
HIDDEN_FIELD = "disable-model-invocation: true"
DEFAULT_LIMITS = ("In-vault limits: CLAUDE.md §2 permissions bind; outputs go to `output/`, never to "
                  "`raw/`, `wiki/`, `attic/` or `.claude/`.")
NAME_OK = "abcdefghijklmnopqrstuvwxyz0123456789-"


def fail(msg):
    print("PROBE FAILED: " + msg)
    sys.exit(2)


def default_skills_root():
    return os.path.join(os.path.expanduser("~"), ".claude", "skills")


def tilde(path):
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if path.startswith(home + os.sep) else path


def parse_frontmatter(text):
    """Minimal reader for the wrappers this script writes: returns (mapping, body) for a leading
    `---` block of `key: value` lines; a double-quoted value is unquoted."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}, text
    fm = {}
    for line in text[4:end].split("\n"):
        if ":" in line and not line.startswith((" ", "\t")):
            k, v = line.split(":", 1)
            v = v.strip()
            if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
                v = v[1:-1].replace('\\"', '"').replace("\\\\", "\\")
            fm[k.strip()] = v
    return fm, text[end + 5:]


def render(name, level, description, upstream, limits, templates=TEMPLATES):
    tpl_path = os.path.join(templates, f"wrapper-{level}.md")
    try:
        with open(tpl_path, "r", encoding="utf-8") as fh:
            body = fh.read()
    except OSError:
        fail(f"template missing: {tpl_path}")
    body = (body.replace("{{name}}", name).replace("{{upstream}}", tilde(upstream))
                .replace("{{limits}}", limits.strip()))
    for s in GATE_SENTINELS[level]:
        if s not in body and s != HIDDEN_FIELD:
            fail(f"template {os.path.basename(tpl_path)} lacks its gate sentinel: {s!r}")
    if "{{" in body:
        fail(f"template {os.path.basename(tpl_path)} left a placeholder unfilled")
    desc = description.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")
    fm = ["---", f"name: {name}", f'description: "{desc}"']
    if level == "by-name":
        fm.append(HIDDEN_FIELD)
    fm.append("---")
    return "\n".join(fm) + "\n" + body


def atomic_write(path, data):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".adopt-", suffix=".tmp", dir=d)
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


def read_bytes(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError:
        return None


def entry_state(entry):
    """What sits at <root>/<name> now: 'absent' · 'symlink' · 'wrapper' (SKILL.md + upstream only) ·
    'other' (a directory holding anything else, never touched)."""
    if os.path.islink(entry):
        return "symlink"
    if not os.path.lexists(entry):
        return "absent"
    if os.path.isdir(entry):
        names = set(os.listdir(entry)) - {".DS_Store"}
        if names <= {"SKILL.md", "upstream"} and "SKILL.md" in names:
            return "wrapper"
        return "other"
    return "other"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Create the carrier of a use level (dry-run unless --write).")
    ap.add_argument("--name", required=True)
    ap.add_argument("--upstream", required=True, help="the pinned clone's skill directory (holds SKILL.md)")
    ap.add_argument("--level", required=True, choices=LEVELS)
    ap.add_argument("--description", default="", help="the wrapper's short description (propose-first, by-name)")
    ap.add_argument("--limits", help="file whose text becomes the in-vault limits sentence(s)")
    ap.add_argument("--skills-root", help="defaults to ~/.claude/skills")
    ap.add_argument("--templates", default=TEMPLATES, help=argparse.SUPPRESS)
    ap.add_argument("--force", action="store_true", help="replace an existing entry that differs")
    ap.add_argument("--write", action="store_true", help="apply (default: dry-run)")
    a = ap.parse_args(argv)

    name = a.name.strip()
    if not name or any(ch not in NAME_OK for ch in name) or name[0] == "-":
        fail(f"name {name!r} must be lowercase letters, digits and hyphens (the register arm's `[a-z0-9-]+`)")
    upstream = os.path.realpath(os.path.expanduser(a.upstream))
    if not os.path.isdir(upstream):
        fail(f"upstream {upstream} is not a directory")
    if not os.path.isfile(os.path.join(upstream, "SKILL.md")):
        fail(f"upstream {upstream} has no SKILL.md (the harness and the wrapper both read one there)")
    root = os.path.realpath(os.path.expanduser(a.skills_root)) if a.skills_root else default_skills_root()
    if not os.path.isdir(root):
        fail(f"skills root {root} is not a directory (create it, or pass --skills-root)")
    entry = os.path.join(root, name)
    mode = "write" if a.write else "dry-run"
    print(f"adopt_wrapper {mode}: {name} · level {a.level} · root {tilde(root)}")

    if a.level == "auto":
        if a.description:
            print("note: --description is ignored for auto (the add-on's own description lists it)")
        state = entry_state(entry)
        if state == "symlink" and os.path.realpath(entry) == upstream:
            print(f"unchanged: {tilde(entry)} -> {tilde(upstream)}")
            return 0
        if state != "absent":
            what = {"symlink": f"a symlink to {tilde(os.path.realpath(entry))}", "wrapper": "a wrapper directory",
                    "other": "a directory with other content"}[state]
            if state == "other":
                fail(f"{tilde(entry)} exists and is {what}; this script never deletes user files — remove it by hand")
            if not a.force:
                print(f"exists and differs: {tilde(entry)} is {what}; pass --force to replace")
                return 1
        print(f"plan: link {tilde(entry)} -> {tilde(upstream)}" + (f" (replacing {state})" if state != "absent" else ""))
        if not a.write:
            print("dry-run: pass --write to apply")
            return 0
        if state == "symlink":
            os.unlink(entry)
        elif state == "wrapper":
            for f in ("SKILL.md", "upstream"):
                p = os.path.join(entry, f)
                if os.path.lexists(p):
                    os.unlink(p)
            os.rmdir(entry)
        os.symlink(upstream, entry)
        print(f"done: {tilde(entry)} -> {tilde(upstream)}")
        return 0

    # wrapper levels
    if not a.description.strip():
        fail("--description is required for propose-first and by-name (the short vault-written description)")
    limits = DEFAULT_LIMITS
    if a.limits:
        try:
            with open(a.limits, "r", encoding="utf-8") as fh:
                limits = fh.read().strip()
        except OSError:
            fail(f"--limits file unreadable: {a.limits}")
        if not limits:
            fail(f"--limits file is empty: {a.limits}")
    text = render(name, a.level, a.description.strip(), upstream, limits, a.templates)
    data = text.encode("utf-8")
    desc_bytes = len(a.description.strip().encode("utf-8"))
    print(f"description: {desc_bytes} B" + (" (the register design aims at about 250 B for a wrapper; the listing carries every byte per request)" if desc_bytes > 400 else ""))

    state = entry_state(entry)
    skill_path = os.path.join(entry, "SKILL.md")
    link_path = os.path.join(entry, "upstream")
    if state == "wrapper":
        same_text = read_bytes(skill_path) == data
        same_link = os.path.islink(link_path) and os.path.realpath(link_path) == upstream
        if same_text and same_link:
            print(f"unchanged: {tilde(skill_path)} ({len(data)} B) · upstream -> {tilde(upstream)}")
            return 0
        diff = []
        if not same_text:
            diff.append("SKILL.md differs")
        if not same_link:
            diff.append("upstream link differs or is missing")
        if not a.force:
            print(f"exists and differs: {tilde(entry)} ({'; '.join(diff)}); pass --force to replace")
            return 1
        print(f"plan: replace {tilde(entry)} ({'; '.join(diff)})")
    elif state == "symlink":
        if not a.force:
            print(f"exists and differs: {tilde(entry)} is a symlink to {tilde(os.path.realpath(entry))}; pass --force to replace")
            return 1
        print(f"plan: replace the symlink {tilde(entry)} with a wrapper directory")
    elif state == "other":
        fail(f"{tilde(entry)} exists and holds files other than SKILL.md and upstream; this script never deletes user files — remove it by hand")
    else:
        print(f"plan: create {tilde(skill_path)} ({len(data)} B) and link upstream -> {tilde(upstream)}")

    print("--- SKILL.md ---")
    sys.stdout.write(text)
    print("--- end ---")
    if not a.write:
        print("dry-run: pass --write to apply")
        return 0
    if state == "symlink":
        os.unlink(entry)
    os.makedirs(entry, exist_ok=True)
    atomic_write(skill_path, data)
    if os.path.lexists(link_path):
        os.unlink(link_path)
    os.symlink(upstream, link_path)
    # verify against disk before claiming done
    if read_bytes(skill_path) != data or os.path.realpath(link_path) != upstream:
        fail(f"post-write verification failed at {tilde(entry)}")
    print(f"done: {tilde(skill_path)} ({len(data)} B) · upstream -> {tilde(upstream)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
