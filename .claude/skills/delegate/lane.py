#!/usr/bin/env python3
"""lane.py — spawn a thin headless lane from a lane home, with its context, tools, model and
effort set per call, and its spawn record written before the process starts.

An in-session lane inherits the whole contract, the whole tool set and the skills listing. A
thin lane is a headless session started from a LANE HOME — a directory outside the vault
holding the lane-side settings, the fence hook and the contract slices, and no CLAUDE.md —
whose context is its brief plus exactly the directories the head grants. Design records:
wiki/developments/thin-lanes-design.md (phase 2) and wiki/developments/hands-off-mode-design.md
(the hands-off additions: file grants, controls, the watchdog, watch, resume, detach, limit).

    lane.py init   [--home DIR]                    build or refresh the base lane home
    lane.py spawn  --run ID --lane ID --class CLASS --brief FILE [options]
    lane.py watch  --run ID --lane ID [--silence-s N] [--max-wait-s N]
    lane.py resume --run ID --lane ID --brief FILE

The commands and what they guarantee
------------------------------------
`init` is idempotent. It writes the lane home's settings (one PreToolUse hook on Bash running
the fence, no other hooks, no MCP servers), a copy of the fence, and the contract slices the
thin classes read by path instead of inheriting: `contract/schema-s4.md` (the schema section
of the vault contract) and `contract/confidence-rubric.md` (the confidence design page, body
only). Each is written to a temporary file and renamed into place, and regenerated only when
its source's hash changes, so two concurrent spawns can never read a half-written slice. It
also materialises the skill slices found under the delegate skill's `lane-home-src/` and
symlinks the memory-hunter's memory directory to the vault's, and prints what it created,
kept or regenerated.

A row's literal grants name the live vault, so a fixture-bound lane takes `--grants-only`:
the literals are dropped (and recorded), the row's per-call slots are still filled from the
call, and `--grant`/`--write` become the lane's whole scope — plus the lane home, /tmp and
/dev, which the fence sanctions for every lane.

`spawn` resolves the class row from `routing.json` (schema 2) under the active throttle,
builds the class's THIN definition from the vault's `.claude/agents/<class>.md` — the same
body, frontmatter rewritten to the row's tools and skills, with no `effort:` field, since the
definition's effort is ignored on the headless path (probe 2026-09-04) and `--effort` is what
applies — and passes it INLINE with `--agents`, so parallel spawns never share a definition
file. It writes the `lane-open` record line BEFORE starting the process, a `lane-spawned`
line carrying the session id once it has started (the meter matches headless lanes by that
id), and a `lane-closed` line carrying the metered figures at the end.

The `lane-open` line's `mode` is the run's delegation regime, `single` or `multi`, with its
source in `mode_src` (`owner`: the Settings line, or the owner's word for this run; `head`:
the head's per-run resolution under delegation `auto`) and where it came from in
`mode_from`. `--delegation` with `--delegation-src` sets them; without the flags the Settings
line `- **delegation**:` (the pre-rename `- **mode**:` line as a fallback) supplies a
`single`/`multi` word with source `owner`, and `auto`, an absent line or any other value is
a premise failure: the head resolves the run first (`role-style-anchor.py set-delegation`)
and passes the resolution, so a record never carries a regime nobody chose (design record:
wiki/developments/delegation-mode-auto-design.md, the critic's F5 fold).

Grants (hands-off D17, D18)
---------------------------
`--grant` and `--write` accept a FILE as well as a directory. The fence sees the path itself
(`LLM_WIKI_LANE_GRANTS` / `LLM_WIKI_LANE_WRITES`, real paths), while the file tools, which
`--add-dir` can only widen by directory, get the file's parent. Every `--add-dir` value is
passed in both spellings when the path as given and its real path differ (a symlinked store,
a symlinked fixture), since the harness compares the spelling a tool call uses. Each spawn
gets its own input directory `<store>/<run>-in-<lane>/`, created by the wrapper with the brief
copied into it, granted read; the store itself is granted only when a call names it, so a
blind lane never sees sibling reports or the record. `--grant-vault-root` grants the vault
root itself (a lane may then read root files such as MANUAL.md without a copy). A per-spawn
settings file `<store>/<run>-settings-<lane>.json` carries the home's hooks plus
`permissions.allow` rules `Edit(//path)` / `Write(//path)` for every write grant; whether
that list beats the harness's sensitive-path guard under `.claude/` is recorded beside
`settings_for` below.

Controls (D19): a brief line `CONTROL+: <phrase> in <file>` is a positive control the wrapper
checks before the spawn — the phrase as a fixed string in that file (a relative file resolves
against the vault). A zero match, a missing file or a malformed line refuses the spawn (exit 2,
no record written); the matches are recorded as `controls_checked`.

The watchdog (D20)
------------------
While it waits, the wrapper checks every `--poll-s` seconds (default 30) the NEWER of the lane
transcript's mtime and the lane's progress file's mtime (`/tmp/<run>-<lane>.progress`, which a
lane appends to inside long calls; the path also reaches the lane as
`LLM_WIKI_LANE_PROGRESS`). Silence past `--silence-s` is a stall, never reasoning: the
threshold is per call, because the transcript is silent for the whole of any tool call, so a
brief that runs a long suite passes a larger value; `--silence-s 0` disables the watch. No
transcript within `--no-transcript-s` (default 120) of the spawn is a stall of reason `no
transcript`. Action: SIGTERM to the process group, the kill grace, SIGKILL; a `stall` event;
`exit_class` `stall`; exit 5.

`watch` attaches the same loop to a lane already running (pid, wrapper pid and session id
from the record). It never kills a live wrapper's lane for silence unless `--silence-s` was
passed to `watch` itself. When the recorded wrapper is gone and no `lane-closed` exists, it
waits for the lane process (bounded by the recorded deadline) and then closes the lane from
its transcript: `exit_class: watch-closed`, `cost_src: transcript-estimate`, `denials:
unknown`. It returns `still-running` (exit 8) after `--max-wait-s` so a head can re-issue it
as a bounded blocking call.

`--detach` is a double fork: a worker process (its own session, so it survives the caller's
exit) runs the lane and writes every record line, and the foreground stays as the watch over
it, exiting with the worker's exit code once `lane-closed` appears; `--detach --no-wait`
prints `detached pid N session S` and exits 0 at once. `lane-spawned` carries `wrapper_pid`,
the process that will write the close.

`resume` (D25) re-enters a finished lane's session (`--resume <session id>`, the follow-up
brief on standard input) with the model, effort, tools, grants and settings its `lane-open`
recorded, refusing when the lane's last call (`lane-closed.ts`) is older than the resume
window, since the cache has lapsed by then and a fresh spawn costs less. It records
`lane-resumed` and a new `lane-closed`.
D29: after a `limit` close the window is WAIVED — one cold re-read is the accepted token loss —
and `lane-resumed` carries `after_limit` and `age_s`; a lane whose transcript cannot be found is
re-spawned, never resumed (exit 2).

The report cut (D8): stdout carries at most `--report-words` words of the report (default 800)
plus `(N of M words shown; full text: <path>)`; the full text is persisted; `lane-closed`
records `report_words` and `report_cut`.

Exit codes: 0 the lane completed; 2 a premise failed before the spawn (no record written), or
`watch` names a lane that is unknown or already closed; 3 the lane ended in error, refusal,
budget stop, max-turns or deadline; 5 a stall; 6 an account or usage limit (`exit_class`
`limit`: the transcript's last assistant record carries a synthetic model with zero usage —
the shape a limit stop leaves, as the watermark hook documents — or the result names a usage
limit); 8 `watch` returned `still-running`. Permission denials are NOT an error: they are
reported on the summary line, and the head reads them as a re-brief signal.

Numbers that decide, each with its derivation
---------------------------------------------
  - deadline, default 3600 s: the longest lane in the run store ran 1,750 s wall
    (2026-09-04), so the default is a shade over twice the longest observed lane. A bound
    with headroom, not a budget; `--deadline-s` sets it per call.
  - budget cap, default from the `breadth` knob (light $2 · standard $5 · max $15): the
    delegate skill's section 2a table, itself anchored to metered gate lanes at $0.35–0.96
    and compile lanes at $1–3. `--budget-usd` sets it per call.
  - kill grace, 5 s between SIGTERM and SIGKILL to the process group: set by judgement,
    unmeasured — long enough for the CLI to flush its transcript, short enough that a hung
    lane does not hold the head.
  - silence threshold, default 900 s: the longest healthy silence observed in run
    run-20260905-handsoff was 12.3 min inside one fable·max call (lane B1, 04:24–04:36 BST,
    2026-09-05, process alive, then resumed), so the earlier 480 s by judgement would have
    killed a healthy lane; 900 s sits over it with headroom. `--baseline-lane` raises it to
    1.5 × the predecessor's runtime when that is larger (the factor set by judgement,
    unmeasured).
  - no-transcript bound, 120 s: the harness writes the transcript file on the first user
    message, seconds after the spawn; 120 s is generous headroom, set by judgement.
  - resume window, 55 min: the 1-hour cache tier minus 5 min headroom (D25).
  - report cut, 800 words: the delegate skill's report cap.
  - limit text guard, 60 words: a limit stop is a sentence, a report is hundreds of words, so
    a successful result mentioning "limit" and "usage" counts only under that length or on an
    error; set by judgement, unmeasured.
  - watch bound, 570 s: the shell tool's 600 s cap less 30 s so the wrapper returns before
    the tool kills it; set by judgement.
  - core injection shape: measured, see below.

Core injection: measured, not assumed
-------------------------------------
The lane core (conduct, controls, shell pitfalls, the gap-report format) can reach a lane as
a skill preloaded through the definition's `skills:` or as `--append-system-prompt-file`.
Three live sonnet spawns on the brief "reply ok", first-call context read from the
transcript (input + cache creation + cache read of the first assistant record), 2026-09-04:

      A  bare thin lane, no core                      8,395 tokens · marker NONE
      B  core preloaded as `skills: [lane-core]`       8,395 tokens · marker NONE
      C  core as `--append-system-prompt-file`         9,877 tokens · marker quoted back

    A 4,644-byte stand-in core carrying a marker line; the brief asked the lane to quote the
    marker or say NONE. Shape B cost nothing and delivered nothing: the `skills` key of the
    inline `--agents` JSON is silently ignored — identical context to bare, marker absent —
    and a control run WITHOUT `--restricted` behaved the same way, so the cause is the inline
    definition, not the restricted mode. Shape C is therefore the only one of the three that
    puts the core in front of the lane, at +1,482 tokens (+18%) over bare. The core comes
    from `--append-core FILE`, else the lane home's own copy, else the shipped
    `templates/lane-core.md`; `--no-core` drops the core and keeps the slices. Every spawn
    records what it carried: `appended: [lane-core, compile-core]` with `appended_bytes`.

    The same measurement settles the skill route, and the answer is negative: a restricted
    headless lane asked to list its skills named only the user-level ones, with a lane-home
    skill installed at `<home>/.claude/skills/<name>/SKILL.md` — as a symlinked directory, as
    a real directory, and with `--setting-sources project` — absent from the list every time
    (three probes, 2026-09-04). The inline definition therefore carries NO `skills:` key: it
    was measured never to load (2026-09-04), and a field that does nothing is worse than no
    field, since it reads like a guarantee.

    So the appended file is the single carrier. Per spawn the wrapper concatenates the lane
    core, then every slice the class row's `skills.default` names, then any `--skill` extra it
    can resolve, each introduced by a one-line heading naming the slice and its source path,
    strips each source's YAML frontmatter (metadata for a loader that is not running here),
    writes the result to the run store as `<RUN>-appended-<LANE>.md` beside the definition
    copy — so the audit shows exactly what the lane carried — and passes that one file with
    `--append-system-prompt-file`. `lane-core` in a row's slice list IS the core, so it is
    never concatenated twice; `--no-core` drops the core and keeps the slices; a class whose
    DEFAULT slice cannot be resolved is a premise failure. `init`'s `skills/` links stay: they
    are the source listing the wrapper reads, not a load path.

Reading the transcript
----------------------
The lane's transcript is `<projects-root>/<home path with every non-alphanumeric character
turned into a dash>/<session-id>.jsonl`, with a glob on the session id as the fallback, so a
change in the harness's directory naming degrades to a slower search rather than to silence.
The projects root is `<CLAUDE_CONFIG_DIR>/projects` under `--config-dir` (or that variable in
the head's own environment), else `~/.claude/projects`. From the transcript the wrapper reads
the effort actually applied, the cache write tier, the peak call context, the fence's denials
(a tool result carrying a `lane-fence:` reason), a refusal (`stop_reason`), the last
assistant text when the result field came back empty, and the limit-stop shape.
"""

import argparse
import datetime
import glob as globmod
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
import uuid

SCHEMA = 2                      # routing.json schema this wrapper speaks
CORE_NAME = "lane-core.md"      # the core's filename in templates/ and the home
CORE_SLICE = "lane-core"        # its name in a class row's skills.default
KILL_GRACE_S = 5                # SIGTERM -> SIGKILL, see the derivation above
DEFAULT_DEADLINE_S = 3600       # see the derivation above
BREADTH_BUDGET = {"light": 2.0, "standard": 5.0, "max": 15.0}   # delegate skill section 2a
DEFAULT_BREADTH = "standard"
THROTTLES = ("top", "default", "cheap", "fast", "cheap-fast")
REGIMES = ("single", "multi")   # what a run actually runs under; `auto` is resolved to one per run
DEFAULT_SILENCE_S = 900         # longest healthy silence observed 12.3 min (see the derivation above)
BASELINE_FACTOR = 1.5           # --baseline-lane multiplier, set by judgement, unmeasured
POLL_S = 30                     # the watchdog's tick (design D20)
NO_TRANSCRIPT_S = 120           # see the derivation above
REPORT_WORDS = 800              # the delegate skill's report cap (design D8)
RESUME_WINDOW_S = 55 * 60       # the 1-hour cache tier less 5 min headroom (design D25)
LIMIT_TEXT_WORDS = 60           # see the derivation above
WATCH_MAX_WAIT_S = 570          # see the derivation above
WATCH_APPEAR_S = 5              # a detached worker records within ~1 s; headroom set by judgement, unmeasured
EXIT_CODES = {"completed": 0, "stall": 5, "limit": 6}    # every other class exits 3
EXIT_STILL_RUNNING = 8
STALL_ACTION = "SIGTERM process group, %d s, SIGKILL" % KILL_GRACE_S


# ----------------------------------------------------------------- premise and paths -------

def die(reason):
    """A premise failure: say what broke, write nothing, exit 2."""
    sys.stderr.write("lane.py: PROBE FAILED: %s\n" % reason)
    sys.exit(2)


def vault_root():
    """The vault is three levels above this script (.claude/skills/delegate/lane.py); an
    explicit CLAUDE_PROJECT_DIR wins, so a copy of the script can be pointed at a vault."""
    return os.path.realpath(vault_given())


def vault_given():
    """The vault root as spelled by the caller (symlinks unresolved), for the second spelling."""
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return os.path.abspath(os.path.expanduser(env))
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        os.pardir, os.pardir, os.pardir))


def store_root():
    """The machine-local run store (hand-off documents, spawn records, parity fixtures)."""
    given = os.environ.get("LLM_WIKI_STORE") or os.path.join(os.path.expanduser("~"), ".llm-wiki")
    return os.path.realpath(os.path.expanduser(given))   # real paths in every record (D17)


def default_home():
    return os.environ.get("LLM_WIKI_LANE_HOME") or os.path.join(store_root(), "lane-home")


def store_paths(run, lane, record_override=None):
    """Every per-lane artefact path in the run store, keyed by name."""
    store = os.path.join(store_root(), "spawn-records")
    return {"store": store,
            "record": record_override or os.path.join(store, "%s.jsonl" % run),
            "definition_copy": os.path.join(store, "%s-definition-%s.md" % (run, lane)),
            "appended": os.path.join(store, "%s-appended-%s.md" % (run, lane)),
            "report": os.path.join(store, "%s-report-%s.md" % (run, lane)),
            "settings": os.path.join(store, "%s-settings-%s.json" % (run, lane)),
            "input_dir": os.path.join(store, "%s-in-%s" % (run, lane)),
            "detach_log": os.path.join(store, "%s-detached-%s.log" % (run, lane))}


def progress_path(run, lane):
    """The lane's liveness file: /tmp by design (the fence sanctions it for every lane); the
    directory is overridable so a suite can keep its fixtures inside one temporary root."""
    return os.path.join(os.environ.get("LLM_WIKI_PROGRESS_DIR") or "/tmp",
                        "%s-%s.progress" % (run, lane))


def config_home(config_dir):
    """The harness configuration directory a lane runs under, or None for the default."""
    return config_dir or os.environ.get("CLAUDE_CONFIG_DIR") or None


def projects_root_for(override, config_dir):
    if override:
        return override
    base = config_home(config_dir) or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(base, "projects")


def sha(text):
    if isinstance(text, str):
        text = text.encode("utf-8")
    return hashlib.sha256(text).hexdigest()


def read_text(path, what):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()
    except OSError as exc:
        die("cannot read %s (%s): %s" % (what, path, exc))


def write_atomic(path, text):
    """Temp file in the same directory, then rename: a concurrent reader sees the old file or
    the new one, never a half-written one."""
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    temp = os.path.join(directory, ".%s.%d.tmp" % (os.path.basename(path), os.getpid()))
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, path)


def dashed(path):
    """The harness's project-directory encoding: every non-alphanumeric character becomes a
    dash (checked against the live projects root, 2026-09-04)."""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(path))


def strip_frontmatter(text):
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[end + 4:].lstrip("\n")
    return text


def parse_frontmatter(text):
    """The small subset the agent definitions use: `key: value` lines between --- fences."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fields = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith((" ", "\t", "#")):
            key, _, value = line.partition(":")
            fields[key.strip()] = value.strip()
    return fields, text[end + 4:].lstrip("\n")


def customisation_value(field_name, fallback):
    """Read a `- **field**: value — comment` line out of the preference layer."""
    path = os.path.join(vault_root(), "CUSTOMISATION.md")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                match = re.match(r"^-\s+\*\*%s\*\*:\s*([^\s—]+)" % re.escape(field_name), line)
                if match:
                    return match.group(1).strip()
    except OSError:
        return fallback
    return fallback


def resolve_delegation(args):
    """The run's delegation regime for the record: (regime, source, where it came from).
    `--delegation` with `--delegation-src` wins; else the Settings line's `single`/`multi`
    word, source `owner`; `auto`, an absent line or any other value is a premise failure,
    since a record must never carry a regime nobody chose."""
    if bool(args.delegation) != bool(args.delegation_src):
        die("--delegation and --delegation-src go together: --delegation single|multi "
            "--delegation-src head|owner")
    if args.delegation:
        return args.delegation, args.delegation_src, "--delegation"
    word = customisation_value("delegation", None)
    line = "delegation"
    if word is None:
        word = customisation_value("mode", None)
        line = "mode (the pre-rename line)"
    if word in REGIMES:
        return word, "owner", "the Settings `%s` line" % line
    reads = "absent" if word is None else "`%s`" % word
    die("delegation regime unresolved: the Settings line is %s — resolve this run first "
        "(role-style-anchor.py set-delegation) and pass --delegation single|multi "
        "--delegation-src head|owner" % reads)


# --------------------------------------------------------------------------- init ----------

def slice_sources(vault):
    """One directory per slice, each holding a SKILL.md; `init` reports it when absent."""
    return os.path.join(vault, ".claude", "skills", "delegate", "lane-home-src")


def core_source(vault):
    """The shipped lane core, materialised into the home so a spawn needs no vault read."""
    return os.path.join(vault, ".claude", "skills", "delegate", "templates", CORE_NAME)


def resolve_slice(name, home, vault):
    """A slice's text, from the lane home first (what init materialised) then the shipped
    source. Returns (source path, body with its frontmatter stripped) or (None, None)."""
    for candidate in (os.path.join(home, "skills", name, "SKILL.md"),
                      os.path.join(slice_sources(vault), name, "SKILL.md"),
                      os.path.join(home, "skills", "%s.md" % name)):
        if os.path.isfile(candidate):
            return candidate, strip_frontmatter(read_text(candidate, "slice %s" % name))
    return None, None


def display_path(path, vault):
    """Vault-relative where it can be, absolute otherwise: the audit heading stays readable
    and carries no machine-specific prefix for anything that lives in the vault. Symlinks are
    resolved first, so a slice linked into the lane home names the shipped file it came
    from — the path a reader can go and check."""
    path = os.path.realpath(path)
    try:
        relative = os.path.relpath(path, vault)
    except ValueError:
        return path
    return relative if not relative.startswith(os.pardir) else path


def extract_schema_section(vault):
    """The contract's page-schema section: from its heading to the next same-level heading."""
    path = os.path.join(vault, "CLAUDE.md")
    text = read_text(path, "the vault contract")
    match = re.search(r"^## \d+\. Wiki Page Schema.*?$", text, re.M)
    if not match:
        die("CLAUDE.md has no wiki page schema heading — the contract slice cannot be built")
    start = match.start()
    nxt = re.search(r"^## ", text[match.end():], re.M)
    body = text[start:match.end() + nxt.start()] if nxt else text[start:]
    return path, body.rstrip() + "\n"


def extract_confidence_rubric(vault):
    path = os.path.join(vault, "wiki", "developments", "wiki-confidence-levels.md")
    if not os.path.exists(path):
        # A fresh clone: the rubric page is vault knowledge and never ships (found by the export suite on
        # 2026-09-04). The slice is optional: lanes then rely on the schema slice's section 4.6 summary.
        return path, None
    return path, strip_frontmatter(read_text(path, "the confidence rubric page")).rstrip() + "\n"


def state_path(home):
    return os.path.join(home, ".lane-home-state.json")


def load_state(home):
    try:
        with open(state_path(home), "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def materialise(home, rel, source_path, source_text, content, state, report):
    """Write `content` at `rel` under the home, but only when the source changed or the file
    drifted. Returns the verb for the report line."""
    target = os.path.join(home, rel)
    src_sha = sha(source_text)
    out_sha = sha(content)
    previous = state.get(rel) or {}
    current = None
    if os.path.exists(target):
        try:
            with open(target, "r", encoding="utf-8") as handle:
                current = sha(handle.read())
        except OSError:
            current = None
    if current is None:
        verb = "created"
    elif previous.get("src_sha") == src_sha and current == out_sha:
        state[rel] = {"src_sha": src_sha, "out_sha": out_sha, "source": source_path}
        report.append(("kept", rel))
        return "kept"
    else:
        verb = "regenerated"
    write_atomic(target, content)
    state[rel] = {"src_sha": src_sha, "out_sha": out_sha, "source": source_path}
    report.append((verb, rel))
    return verb


def cmd_init(args):
    vault = vault_root()
    home = os.path.realpath(os.path.expanduser(args.home or default_home()))
    os.makedirs(home, mode=0o700, exist_ok=True)
    state = load_state(home)
    report = []

    fence_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lane-fence.py")
    fence_text = read_text(fence_src, "the fence hook")
    materialise(home, "lane-fence.py", fence_src, fence_text, fence_text, state, report)
    os.chmod(os.path.join(home, "lane-fence.py"), 0o700)

    settings = {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{
        "type": "command",
        "command": "%s %s" % (shlex.quote(sys.executable),
                              shlex.quote(os.path.join(home, "lane-fence.py")))}]}]}}
    settings_text = json.dumps(settings, indent=2) + "\n"
    materialise(home, "lane-settings.json", "(computed)", settings_text, settings_text,
                state, report)

    src, body = extract_schema_section(vault)
    materialise(home, os.path.join("contract", "schema-s4.md"), src, body, body, state, report)
    src, body = extract_confidence_rubric(vault)
    if body is None:
        report.append(("absent", os.path.join("contract", "confidence-rubric.md")
                       + " (no rubric page in this vault: a fresh clone; optional)"))
    else:
        materialise(home, os.path.join("contract", "confidence-rubric.md"), src, body, body,
                    state, report)

    # Skills: the harness discovers project skills under <cwd>/.claude/skills, and the design
    # names the home's directory `skills/`; the symlink lets one directory serve both.
    skills_dir = os.path.join(home, "skills")
    os.makedirs(skills_dir, exist_ok=True)
    dot_claude = os.path.join(home, ".claude")
    os.makedirs(dot_claude, exist_ok=True)
    link = os.path.join(dot_claude, "skills")
    if not os.path.islink(link) and not os.path.exists(link):
        os.symlink(skills_dir, link)
        report.append(("created", ".claude/skills -> skills"))
    else:
        report.append(("kept", ".claude/skills -> skills"))

    core_src = core_source(vault)
    installed, missing = [], []
    if os.path.isfile(core_src):
        core_text = read_text(core_src, "the lane core")
        materialise(home, CORE_NAME, core_src, core_text, core_text, state, report)
    else:
        missing.append(os.path.relpath(core_src, vault))

    source_dir = slice_sources(vault)
    if os.path.isdir(source_dir):
        for name in sorted(os.listdir(source_dir)):
            entry = os.path.join(source_dir, name)
            if not os.path.isdir(entry):
                continue          # only a directory holding a SKILL.md is a slice
            target = os.path.join(skills_dir, name)
            if os.path.islink(target) or os.path.exists(target):
                if os.path.islink(target) and os.path.realpath(target) == os.path.realpath(entry):
                    report.append(("kept", os.path.join("skills", name)))
                    installed.append(name)
                    continue
                os.remove(target) if os.path.islink(target) else None
            if not os.path.exists(target):
                os.symlink(entry, target)
                report.append(("created", os.path.join("skills", name)))
            installed.append(name)
    else:
        missing.append(os.path.relpath(source_dir, vault))

    # A memory directory per class whose definition declares `memory: local`, mirrored at the
    # relative path the vault uses. Keyed on the declaration, so a future memory class is
    # covered without editing this list.
    agents_dir = os.path.join(vault, ".claude", "agents")
    memory_classes = []
    for name in sorted(os.listdir(agents_dir)) if os.path.isdir(agents_dir) else []:
        if not name.endswith(".md"):
            continue
        fields, _ = parse_frontmatter(read_text(os.path.join(agents_dir, name), "a definition"))
        if fields.get("memory") == "local":
            memory_classes.append(name[:-3])
    for cls_name in memory_classes:
        mem_rel = os.path.join(".claude", "agent-memory-local", cls_name)
        vault_mem = os.path.join(vault, mem_rel)
        home_mem = os.path.join(home, mem_rel)
        if not os.path.isdir(vault_mem):
            missing.append(mem_rel)
            continue
        os.makedirs(os.path.dirname(home_mem), exist_ok=True)
        if os.path.islink(home_mem) and os.path.realpath(home_mem) == os.path.realpath(vault_mem):
            report.append(("kept", mem_rel))
        elif not os.path.exists(home_mem):
            os.symlink(os.path.realpath(vault_mem), home_mem)
            report.append(("created", mem_rel))
        else:
            report.append(("kept", mem_rel + " (not a symlink to the vault's; left alone)"))
    if not memory_classes:
        missing.append("a class declaring `memory: local`")

    write_atomic(state_path(home), json.dumps(state, indent=1, sort_keys=True) + "\n")

    print("lane home: %s" % home)
    for verb, rel in report:
        print("  %-12s %s" % (verb, rel))
    print("  skill slices available to append: %s"
          % (", ".join(installed) if installed else "none installed"))
    if missing:
        print("  not present (init succeeds without them): %s" % ", ".join(missing))
    trust = trust_state(home)
    print("  workspace trust entry: %s" % {True: "accepted", False: "declined",
                                           None: "absent"}[trust])
    return 0


def trust_state(home, config_dir=None):
    """A headless run on an untrusted workspace can degrade silently (delegate skill section
    2). Returns True/False/None; the wrapper records it and `--require-trust` enforces it.
    Under a configuration directory the entry lives in that directory's `.claude.json`."""
    path = os.path.join(config_home(config_dir) or os.path.expanduser("~"), ".claude.json")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    entry = (data.get("projects") or {}).get(os.path.realpath(home))
    if not isinstance(entry, dict) or "hasTrustDialogAccepted" not in entry:
        return None
    return bool(entry["hasTrustDialogAccepted"])


# ------------------------------------------------------------------------ routing ----------

def load_routing(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as exc:
        die("routing table unreadable (%s): %s" % (path, exc))
    except ValueError as exc:
        die("routing table is not JSON (%s): %s" % (path, exc))
    if data.get("schema") != SCHEMA:
        die("routing table %s is schema %r, this wrapper speaks schema %d — the v2 table with "
            "per-class option sets, grants, tools, skills, mcp and cache is required"
            % (path, data.get("schema"), SCHEMA))
    for field_name in ("order", "classes"):
        if field_name not in data:
            die("routing table %s has no `%s` field" % (path, field_name))
    for field_name in ("model", "effort"):
        if field_name not in (data.get("order") or {}):
            die("routing table %s has no `order.%s` list" % (path, field_name))
    return data


def field(row, cls, *keys):
    node = row
    for key in keys:
        if not isinstance(node, dict) or key not in node:
            die("routing class `%s` has no `%s` field" % (cls, ".".join(keys)))
        node = node[key]
    return node


def pick(order, options, default, throttle):
    """Map the throttle onto one class's option set; strength follows the global order."""
    known = [o for o in options if o in order]
    if not known:
        die("no option in %r appears in the global order %r" % (options, order))
    strongest = max(known, key=order.index)
    weakest = min(known, key=order.index)
    return {"top": strongest, "cheap": weakest, "default": default,
            "fast": None, "cheap-fast": None}.get(throttle, default), weakest, strongest


def resolve_tier(routing, row, cls, throttle):
    model_opts = field(row, cls, "model", "options")
    model_default = field(row, cls, "model", "default")
    effort_opts = field(row, cls, "effort", "options")
    effort_default = field(row, cls, "effort", "default")
    model_order = routing["order"]["model"]
    effort_order = routing["order"]["effort"]
    model, model_weak, _ = pick(model_order, model_opts, model_default, throttle)
    effort, effort_weak, _ = pick(effort_order, effort_opts, effort_default, throttle)
    if throttle == "fast":
        model, effort = model_default, effort_weak
    elif throttle == "cheap-fast":
        model, effort = model_weak, effort_weak
    return model, effort, model_opts, effort_opts


# ------------------------------------------------------------------ definition -------------

def thin_definition(vault, cls, tools, description_fallback):
    """The class's own body with a thin frontmatter: the row's tools and skills, no `effort:`
    (ignored on the headless path), `memory: local` only where the source definition had it."""
    path = os.path.join(vault, ".claude", "agents", "%s.md" % cls)
    if not os.path.isfile(path):
        die("no definition for class `%s` at %s" % (cls, path))
    text = read_text(path, "the class definition")
    fields, body = parse_frontmatter(text)
    if not body.strip():
        die("definition %s has an empty body" % path)
    # No `skills:` key: measured never to load through the inline --agents JSON (2026-09-04).
    # The slices travel in the appended system-prompt file instead.
    agent = {"description": fields.get("description") or description_fallback,
             "prompt": body.rstrip() + "\n",
             "tools": list(tools)}
    if fields.get("memory") == "local":
        agent["memory"] = "local"
    return path, sha(text), agent


def definition_markdown(cls, agent, model, effort):
    lines = ["---", "name: %s" % cls, "description: %s" % agent["description"],
             "tools: %s" % ", ".join(agent["tools"])]
    if agent.get("memory"):
        lines.append("memory: %s" % agent["memory"])
    lines += ["# model and effort are spawn flags, not definition fields, on the headless path",
              "# spawned with: model %s, effort %s" % (model, effort), "---", "",
              agent["prompt"]]
    return "\n".join(lines)


# ---------------------------------------------------------------------- grants -------------

def split_placeholders(values):
    """A routing row states some directories literally and leaves the rest to the call. A
    `<…>` value is one of those per-call slots, not a path."""
    literals, slots = [], []
    for value in values or []:
        value = str(value)
        (slots if ("<" in value or ">" in value) else literals).append(value)
    return literals, slots


def memory_dir(home, cls):
    """The class's own memory directory inside the lane home, when it has one. Keyed on the
    directory `init` materialises for a class whose definition declares `memory: local`, not
    on a class name or a placeholder's wording, so a future memory class is covered."""
    path = os.path.join(home, ".claude", "agent-memory-local", cls)
    return path if os.path.isdir(path) else None


def entry_for(value, vault, what, files_ok):
    """One grant: its spelling as given (absolute, symlinks unresolved), its real path and
    whether it is a file. Vault-relative names resolve against the vault."""
    given = os.path.expanduser(str(value))
    if not os.path.isabs(given):
        given = os.path.join(vault, given)
    given = os.path.abspath(given)
    real = os.path.realpath(given)
    if not os.path.exists(real):
        die("%s does not exist: %s" % (what, given))
    if os.path.isdir(real):
        return {"given": given, "real": real, "file": False}
    if not files_ok:
        die("%s must be a directory, not a file: %s (grant its directory instead)"
            % (what, given))
    return {"given": given, "real": real, "file": True}


def dir_entry(path):
    """An entry for a directory the wrapper itself names (the input directory, the vault root)."""
    given = os.path.abspath(path)
    return {"given": given, "real": os.path.realpath(given), "file": False}


def add_entry(target, entry):
    if entry["real"] not in [e["real"] for e in target]:
        target.append(entry)


def resolve_entries(values, vault, what, files_ok):
    out = []
    for value in values or []:
        add_entry(out, entry_for(value, vault, what, files_ok))
    return out


def reals(entries):
    return [e["real"] for e in entries]


def files_of(entries):
    return [e["real"] for e in entries if e["file"]]


def spellings(given, real):
    return [real] if given == real else [real, given]


def add_unique(target, items):
    for item in items:
        if item not in target:
            target.append(item)


def add_dirs_for(entries):
    """The `--add-dir` values: each entry's directory (a file's parent) in every spelling,
    real path first. The harness compares the spelling a tool call uses, so a symlinked path
    granted in one spelling alone refuses the other (session A residue, 2026-09-05)."""
    out = []
    for entry in entries:
        real_dir = os.path.dirname(entry["real"]) if entry["file"] else entry["real"]
        given_dir = os.path.dirname(entry["given"]) if entry["file"] else entry["given"]
        add_unique(out, spellings(given_dir, real_dir))
    return out


def allow_pattern(path, is_dir):
    """A harness permission-rule path: a doubled leading separator marks an absolute
    filesystem path (a single one would be project-relative); a directory covers everything
    beneath it."""
    pattern = os.sep + os.sep + path.lstrip(os.sep)
    return pattern + (os.sep + "**" if is_dir else "")


def settings_for(home, write_entries):
    """The per-spawn settings: the home's hooks plus Edit and Write allow rules for every
    write grant, in both spellings (design D18). PROBE RESULT 2026-09-05 (test_lane.sh
    --live-handsoff, a haiku lane, a fixture SKILL.md under a .claude directory on the allow
    list): the sensitive-path guard WINS - the harness answered `requested permissions to edit
    ... which is a sensitive file` and no edit landed; the shell stays the write channel there."""
    base_path = os.path.join(home, "lane-settings.json")
    try:
        with open(base_path, "r", encoding="utf-8") as handle:
            base = json.load(handle)
    except (OSError, ValueError) as exc:
        die("lane settings unreadable (%s): %s" % (base_path, exc))
    hooks = base.get("hooks") if isinstance(base, dict) else None
    if not hooks:
        die("lane settings %s carry no hooks — run `lane.py init`" % base_path)
    allow = []
    for entry in write_entries:
        for spelling in spellings(entry["given"], entry["real"]):
            pattern = allow_pattern(spelling, not entry["file"])
            add_unique(allow, ["Edit(%s)" % pattern, "Write(%s)" % pattern])
    out = {"hooks": hooks}
    if allow:
        out["permissions"] = {"allow": allow}
    return out, allow


# ---------------------------------------------------------------------- controls -----------

CONTROL_RE = re.compile(r"^.*?\bCONTROL\+:\s*(.+?)\s*$")   # anywhere on the line: a control after a label (`VERIFICATION: CONTROL+: …`) ran unchecked in rehearsal R2 (2026-09-05)


def unwrap(text):
    text = text.strip()
    if 1 < len(text) and text[0] == text[-1] and text[0] in "\"'`":
        return text[1:-1]
    return text


def parse_controls(brief):
    """Every `CONTROL+: <phrase> in <file>` line of a brief; the split is on the LAST ` in `,
    so a phrase may contain the word and a file path may not."""
    out = []
    for number, line in enumerate(brief.splitlines(), 1):
        match = CONTROL_RE.match(line)
        if not match:
            continue
        body = match.group(1)
        cut = body.rfind(" in ")
        phrase = unwrap(body[:cut]) if cut != -1 else ""
        path = unwrap(body[cut + 4:]) if cut != -1 else ""
        if not phrase or not path:
            die("brief line %d: malformed control line (want `CONTROL+: <phrase> in <file>`): %s"
                % (number, line.strip()))
        out.append({"line": number, "phrase": phrase, "file": path})
    return out


def check_controls(controls, vault):
    """Each phrase as a fixed string in its file; a zero match refuses the spawn (design D19)."""
    checked = []
    for control in controls:
        path = os.path.expanduser(control["file"])
        if not os.path.isabs(path):
            path = os.path.join(vault, path)
        path = os.path.realpath(path)
        if not os.path.isfile(path):
            die("brief line %d: control file not found: %s" % (control["line"], control["file"]))
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            count = handle.read().count(control["phrase"])
        if count == 0:
            die("brief line %d: control phrase %r matches nothing in %s — the spawn is refused"
                % (control["line"], control["phrase"], path))
        checked.append({"phrase": control["phrase"], "file": path, "matches": count})
    return checked


# ------------------------------------------------------------------- transcript ------------

def find_transcript(projects_root, home, session_id):
    direct = os.path.join(projects_root, dashed(home), "%s.jsonl" % session_id)
    if os.path.isfile(direct):
        return direct
    hits = sorted(globmod.glob(os.path.join(projects_root, "*", "%s.jsonl" % session_id)))
    return hits[0] if hits else None


def block_text(block):
    if isinstance(block, str):
        return block
    if isinstance(block, dict):
        content = block.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return " ".join(block_text(item) for item in content)
        return str(block.get("text") or "")
    return ""


USAGE_KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
              "output_tokens")


def parse_transcript(path):
    """Everything the close line reports, read from JSON records, never by substring grep on
    the raw file: efforts applied, cache write tiers, peak call context, fence denials, a
    refusal, the last assistant text, token totals, and the limit-stop shape (the last
    assistant record carrying a synthetic model with all-zero usage)."""
    out = {"efforts": [], "tiers": [], "peak": 0, "fence_denials": 0, "fence_allows": 0,
           "refusal": False, "last_text": "", "records": 0, "unparseable": 0,
           "transcript": path, "calls": 0, "synthetic_stop": False, "last_model": None,
           "tokens": dict((key, 0) for key in USAGE_KEYS)}
    if not path or not os.path.isfile(path):
        out["transcript"] = None
        return out
    final = {}
    order = []
    try:
        handle = open(path, "r", encoding="utf-8", errors="replace")
    except OSError:
        out["transcript"] = None
        return out
    with handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            out["records"] += 1
            try:
                record = json.loads(line)
            except ValueError:
                out["unparseable"] += 1
                continue
            if not isinstance(record, dict):
                continue
            kind = record.get("type")
            message = record.get("message") if isinstance(record.get("message"), dict) else {}
            if kind == "assistant":
                if record.get("effort"):
                    out["efforts"].append(record["effort"])
                if message.get("stop_reason") == "refusal":
                    out["refusal"] = True
                mid = message.get("id") or "anon-%d" % out["records"]
                if mid not in final:
                    order.append(mid)
                final[mid] = message
                text = " ".join(block_text(b) for b in (message.get("content") or [])
                                if isinstance(b, dict) and b.get("type") == "text")
                if text.strip():
                    out["last_text"] = text.strip()
                usage = message.get("usage") if isinstance(message.get("usage"), dict) else {}
                stock = sum(int(usage.get(key) or 0) for key in USAGE_KEYS)
                out["last_model"] = str(message.get("model") or "")
                out["synthetic_stop"] = out["last_model"].startswith("<synthetic") and stock == 0
            # A fence DENIAL is a tool result whose text starts with the fence prefix; the
            # lane's own prose quoting that prefix back (it does, when the brief asks it to
            # report the reason) is not a denial, so the test is the record kind and the
            # start of the text, never a substring search over the whole record.
            if kind == "user":
                for block in (message.get("content") or []):
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        text = block_text(block).lstrip()
                        if text.startswith("lane-fence:") and "within grants" not in text:
                            out["fence_denials"] += 1
            elif kind == "attachment":
                attachment = record.get("attachment")
                stdout = (attachment or {}).get("stdout") if isinstance(attachment, dict) else ""
                if isinstance(stdout, str) and "lane-fence: within grants" in stdout:
                    out["fence_allows"] += 1
    for mid in order:
        usage = final[mid].get("usage") or {}
        context = (int(usage.get("input_tokens") or 0)
                   + int(usage.get("cache_creation_input_tokens") or 0)
                   + int(usage.get("cache_read_input_tokens") or 0))
        out["peak"] = max(out["peak"], context)
        for key in USAGE_KEYS:
            out["tokens"][key] += int(usage.get(key) or 0)
        creation = usage.get("cache_creation")
        if isinstance(creation, dict):
            for key, label in (("ephemeral_1h_input_tokens", "1h"),
                               ("ephemeral_5m_input_tokens", "5m")):
                if int(creation.get(key) or 0) > 0 and label not in out["tiers"]:
                    out["tiers"].append(label)
        elif int(usage.get("cache_creation_input_tokens") or 0) > 0 and "untiered" not in out["tiers"]:
            out["tiers"].append("untiered")
    if order:
        first = final[order[0]].get("usage") or {}
        out["first_call_context"] = (int(first.get("input_tokens") or 0)
                                     + int(first.get("cache_creation_input_tokens") or 0)
                                     + int(first.get("cache_read_input_tokens") or 0))
    out["calls"] = len(order)
    return out


# ----------------------------------------------------------------------- record -------------

def append_record(path, payload):
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as exc:
        die("spawn record is not writable (%s): %s" % (path, exc))


def load_record(path):
    """Every JSON line of a record; an unparseable line (a torn write) is skipped, not fatal."""
    if not os.path.isfile(path):
        die("no spawn record at %s" % path)
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if isinstance(record, dict):
                out.append(record)
    return out


def lane_state(records, lane, session_id=None):
    """The lane's latest open, its latest spawn-ish event (lane-spawned or lane-resumed) and
    the lane-closed that follows it, if any; with a session id, only that session's lines,
    so a re-spawn of a lane id never reads its predecessor's close as its own."""
    opened = spawned = closed = None
    for record in records:
        if record.get("lane") != lane:
            continue
        if session_id and record.get("session_id") not in (None, session_id):
            continue
        event = record.get("event")
        if event == "lane-open":
            opened, spawned, closed = record, None, None
        elif event in ("lane-spawned", "lane-resumed"):
            spawned, closed = record, None
        elif event == "lane-closed":
            closed = record
    return opened, spawned, closed


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def parse_ts(ts):
    """A record timestamp (the `now()` shape) as an epoch, or None when unparseable."""
    try:
        return datetime.datetime.strptime(str(ts), "%Y-%m-%dT%H:%M:%S%z").timestamp()
    except (TypeError, ValueError):
        return None


# -------------------------------------------------------------- watching and closing -------

def cut_words(text, limit):
    """The first `limit` words with their line structure kept: (shown, shown count, total,
    cut?). A limit of 0 shows nothing and leaves the pointer line to name the file."""
    total = len(text.split())
    if limit <= 0:
        return "", 0, total, total > 0
    if total <= limit:
        return text.rstrip(), total, total, False
    count = 0
    for match in re.finditer(r"\S+", text):
        count += 1
        if count == limit:
            return text[:match.end()].rstrip(), limit, total, True
    return text.rstrip(), total, total, False


def limit_signal(parsed, result_text, stderr_text, subtype, failed):
    """Where a lane hit an account or usage limit (design: the account plan, C2 N12), the
    evidence as one phrase; None otherwise. A budget cap (`error_max_budget_usd`) is never a
    limit."""
    if parsed.get("synthetic_stop"):
        return "transcript: last assistant record has model %s with zero usage" % parsed.get("last_model")
    sub = (subtype or "").lower()
    if "limit" in sub and "budget" not in sub:
        return "subtype %s" % subtype
    low = (result_text or "").lower()
    if "limit" in low and ("reset" in low or "usage" in low):
        if failed or sub not in ("", "success") or len(low.split()) <= LIMIT_TEXT_WORDS:
            return "result text names a limit"
    low = (stderr_text or "").lower()
    if failed and "limit" in low and ("reset" in low or "usage" in low):
        return "stderr names a limit"
    return None


def classify(killed, stall, parsed, result, subtype, returncode, parse_error, stderr):
    """The close line's exit_class and, for a limit, the evidence."""
    if stall:
        return "stall", None
    if killed:
        return "deadline", None
    failed = bool(result.get("is_error")) or returncode != 0
    signal_text = limit_signal(parsed, result.get("result") or "", stderr, subtype, failed)
    if signal_text:
        return "limit", signal_text
    if parsed["refusal"]:
        return "refusal", None
    if "max_budget" in subtype:
        return "budget", None
    if "max_turns" in subtype:
        return "max-turns", None
    if failed or parse_error:
        return "error", None
    return "completed", None


def pid_alive(pid):
    """True/False, or None when the pid is missing or unreadable."""
    if not pid:
        return None
    try:
        os.kill(int(pid), 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except (OSError, ValueError):
        return None
    return True


def signal_group(pid, sig):
    try:
        os.killpg(os.getpgid(int(pid)), sig)
        return True
    except (OSError, ValueError):
        try:
            os.kill(int(pid), sig)
            return True
        except (OSError, ValueError):
            return False


def kill_group(process):
    """SIGTERM the lane's process group, wait the grace, SIGKILL; returns (stdout, stderr)."""
    signal_group(process.pid, signal.SIGTERM)
    try:
        return process.communicate(timeout=KILL_GRACE_S)
    except subprocess.TimeoutExpired:
        signal_group(process.pid, signal.SIGKILL)
        return process.communicate()


def kill_pid_group(pid):
    """The same sequence for a lane the wrapper does not own (watch's orphan path)."""
    signal_group(pid, signal.SIGTERM)
    waited = 0.0
    while waited < KILL_GRACE_S and pid_alive(pid):
        time.sleep(0.5)
        waited += 0.5
    if pid_alive(pid):
        signal_group(pid, signal.SIGKILL)


def silence_of(started, transcript, progress, threshold, no_transcript_s):
    """Seconds since the lane last showed life (the newer of the transcript and the progress
    file, never earlier than the spawn), the reason label and the bound that applies."""
    marks = [started]
    if progress and os.path.isfile(progress):
        marks.append(os.path.getmtime(progress))
    if transcript and os.path.isfile(transcript):
        marks.append(os.path.getmtime(transcript))
        reason, bound = "silent", threshold
    else:
        reason, bound = "no transcript", no_transcript_s
    return round(time.time() - max(marks), 1), reason, bound


def resolve_silence(args, record_path):
    """The stall threshold and where it came from; 0 disables the watch."""
    if args.silence_s is not None and args.silence_s < 0:
        die("--silence-s must be 0 (watch disabled) or a positive number of seconds")
    if args.silence_s == 0:
        return 0, "--silence-s 0 (watch disabled)"
    base = DEFAULT_SILENCE_S if args.silence_s is None else args.silence_s
    source = "default" if args.silence_s is None else "--silence-s"
    if getattr(args, "baseline_lane", None):
        duration = None
        for record in load_record(record_path):
            if record.get("event") == "lane-closed" and record.get("lane") == args.baseline_lane:
                duration = record.get("duration_s")
        if not isinstance(duration, (int, float)):
            die("--baseline-lane %s has no lane-closed with a duration_s in %s"
                % (args.baseline_lane, record_path))
        derived = round(BASELINE_FACTOR * float(duration), 1)
        if base < derived:
            base, source = derived, "%s x baseline %s (%.1f s)" % (BASELINE_FACTOR,
                                                                  args.baseline_lane, duration)
    return base, source


def stall_event(run, lane, session_id, silent_s, threshold_s, reason, by):
    return {"ts": now(), "run": run, "lane": lane, "event": "stall", "session_id": session_id,
            "silent_s": silent_s, "threshold_s": threshold_s, "reason": reason,
            "action": STALL_ACTION, "by": by}


def summary_of(run, lane, cls, model, effort, close):
    cost = close.get("total_cost_usd")
    denials = close.get("denials") or {}
    if not isinstance(denials, dict):
        denials = {"tool": denials, "fence": denials}
    usage = close.get("usage") or {}
    line = ("lane %s/%s: %s %s·%s · %s · %s turns · $%s · denials tool %s fence %s · "
            "effort applied %s · tier %s · peak %s · session %s"
            % (run, lane, cls, model, effort, close.get("exit_class"),
               close.get("num_turns") if close.get("num_turns") is not None else "?",
               ("%.2f" % cost) if isinstance(cost, (int, float)) else "?",
               denials.get("tool", "?"), denials.get("fence", "?"),
               ",".join(close.get("effort_applied") or []) or "unread",
               ",".join(close.get("cache_write_tier") or []) or "unread",
               format(usage.get("peak_context") or 0, ","), close.get("session_id")))
    if close.get("report_words") is not None:
        line += " · report %s/%s words%s" % (close.get("report_shown", "?"),
                                              close["report_words"],
                                              " (cut)" if close.get("report_cut") else "")
    return line


def emit(summary, close, report_words, fmt, open_line=None, text=None):
    """The wrapper's stdout: the summary line, the report pointer, and the report's first
    `report_words` words with the `(N of M words shown; full text: <path>)` line (design D8)."""
    report_path = close.get("report")
    if text is None:
        text = ""
        if report_path and os.path.isfile(report_path):
            try:
                with open(report_path, "r", encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
            except OSError:
                text = ""
    shown, n_shown, n_total, cut = cut_words(text, report_words)
    if fmt == "json":
        print(json.dumps({"summary": summary, "open": open_line, "close": close,
                          "report_path": report_path, "report_text": shown,
                          "report_words": n_total, "report_shown": n_shown,
                          "report_cut": cut}, indent=1))
        return
    print(summary)
    if report_path:
        print("report: %s" % report_path)
    if close.get("parse_error"):
        print("note: %s" % close["parse_error"])
    if report_path:
        if shown:
            print(shown)
        print("(%d of %d words shown; full text: %s)" % (n_shown, n_total, report_path))


def wait_process(process, stdin_text, started, deadline, silence, poll, no_transcript_s,
                 locate, progress):
    """Feed the brief and wait, checking liveness every `poll` seconds while a silence
    threshold is set. Returns (stdout, stderr, killed for the deadline?, stall dict or None)."""
    first, stall, killed = True, None, False
    stdout = stderr = None
    while True:
        remaining = deadline - (time.time() - started)
        if remaining <= 0:
            killed = True
            stdout, stderr = kill_group(process)
            break
        timeout = min(poll, remaining) if (silence and poll and poll > 0) else remaining
        try:
            stdout, stderr = process.communicate(input=stdin_text if first else None,
                                                 timeout=timeout)
            break
        except subprocess.TimeoutExpired:
            first = False
        if silence and silence > 0:
            silent_s, reason, bound = silence_of(started, locate(), progress, silence,
                                                 no_transcript_s)
            if silent_s > bound:
                stall = {"silent_s": silent_s, "threshold_s": bound, "reason": reason}
                stdout, stderr = kill_group(process)
                break
    return stdout, stderr, killed, stall


def run_lane(ctx):
    """Start the lane process, feed the brief, watch it, write the close line and print the
    summary. Shared by spawn and resume. Returns the wrapper's exit code."""
    record_path, run, lane = ctx["record"], ctx["run"], ctx["lane"]
    try:
        os.makedirs(os.path.dirname(ctx["progress"]) or ".", exist_ok=True)
    except OSError:
        pass          # the lane's own append will report it; /tmp exists on every platform
    started = time.time()
    try:
        process = subprocess.Popen(
            ctx["command"], cwd=ctx["home"], env=ctx["env"], start_new_session=True, text=True,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as exc:
        append_record(record_path, {"ts": now(), "run": run, "lane": lane,
                                    "event": "lane-closed", "session_id": ctx["session_id"],
                                    "class": ctx["cls"], "exit_class": "spawn-failed",
                                    "error": str(exc), "exit_code": 3,
                                    "wrapper_pid": os.getpid()})
        sys.stderr.write("lane.py: could not start the lane process: %s\n" % exc)
        return 3

    spawned = {"ts": now(), "run": run, "lane": lane, "event": ctx["spawn_event"],
               "session_id": ctx["session_id"], "pid": process.pid, "wrapper_pid": os.getpid(),
               "class": ctx["cls"], "detached": ctx.get("detached", False),
               "mechanism": "lane.py headless, model %s, effort %s" % (ctx["model"], ctx["effort"])}
    spawned.update(ctx.get("spawn_extra") or {})
    append_record(record_path, spawned)

    def locate():
        return find_transcript(ctx["projects_root"], ctx["home"], ctx["session_id"])

    stdout, stderr, killed, stall = wait_process(
        process, ctx["stdin"], started, ctx["deadline"], ctx["silence"], ctx["poll"],
        ctx["no_transcript_s"], locate, ctx["progress"])
    duration = round(time.time() - started, 1)
    if stall:
        append_record(record_path, stall_event(run, lane, ctx["session_id"], stall["silent_s"],
                                               stall["threshold_s"], stall["reason"], "spawn"))

    result, parse_error = None, None
    if stdout and stdout.strip():
        try:
            result = json.loads(stdout)
        except ValueError as exc:
            parse_error = "result JSON unparseable: %s" % exc
    if not isinstance(result, dict):
        result = {} if result is None else {"result": str(result)}

    transcript = locate()
    parsed = parse_transcript(transcript)

    report_text = (result.get("result") or "").strip() or parsed["last_text"]
    if not report_text:
        report_text = "(no report text: exit %s%s%s)" % (
            process.returncode, ", deadline reached" if killed else "",
            ", stall (%s)" % stall["reason"] if stall else "")
    try:
        write_atomic(ctx["report_path"], report_text.rstrip() + "\n")
        report_written = ctx["report_path"]
    except OSError as exc:
        report_written = None
        sys.stderr.write("lane.py: report not written (%s)\n" % exc)
    shown, n_shown, n_total, cut = cut_words(report_text, ctx["report_words"])

    denials = result.get("permission_denials")
    denial_count = len(denials) if isinstance(denials, list) else 0
    subtype = result.get("subtype") or ""
    exit_class, limit_text = classify(killed, stall, parsed, result, subtype,
                                      process.returncode, parse_error, stderr or "")
    exit_code = EXIT_CODES.get(exit_class, 3)

    close_line = {
        "ts": now(), "run": run, "lane": lane, "event": "lane-closed",
        "session_id": result.get("session_id") or ctx["session_id"], "class": ctx["cls"],
        "exit_class": exit_class, "exit_code": exit_code, "process_exit": process.returncode,
        "duration_s": duration, "subtype": subtype, "is_error": bool(result.get("is_error")),
        "num_turns": result.get("num_turns"), "total_cost_usd": result.get("total_cost_usd"),
        "cost_src": "result",
        "usage": {"modelUsage": result.get("modelUsage"),
                  "peak_context": parsed["peak"], "calls": parsed.get("calls", 0),
                  "first_call_context": parsed.get("first_call_context"),
                  "tokens": parsed.get("tokens")},
        "effort_applied": sorted(set(parsed["efforts"])) or None,
        "cache_write_tier": parsed["tiers"] or None,
        "denials": {"tool": denial_count, "fence": parsed["fence_denials"],
                    "fence_allows": parsed["fence_allows"]},
        "permission_denials": denials if isinstance(denials, list) else [],
        "transcript": parsed["transcript"], "report": report_written,
        "report_words": n_total, "report_shown": n_shown, "report_cut": cut,
        "limit_signal": limit_text, "silence_s": ctx["silence"],
        "stall": stall, "wrapper_pid": os.getpid(),
        "stderr_tail": (stderr or "").strip()[-400:] or None,
        "parse_error": parse_error}
    close_line.update(ctx.get("close_extra") or {})
    append_record(record_path, close_line)

    summary = summary_of(run, lane, ctx["cls"], ctx["model"], ctx["effort"], close_line)
    emit(summary, close_line, ctx["report_words"], ctx["format"], ctx.get("open_line"),
         text=report_text)
    return exit_code


def close_from_transcript(record_path, run, lane, opened, spawned, home, projects_root,
                          note, report_words, extra=None):
    """The close line `watch` writes for a lane whose wrapper is gone: everything the
    transcript shows, the cost marked as a transcript estimate (token totals, no dollar
    figure — the wrapper has no price table, and a wrong figure is worse than none)."""
    session_id = spawned.get("session_id") or opened.get("session_id")
    transcript = find_transcript(projects_root, home, session_id)
    parsed = parse_transcript(transcript)
    report_path = store_paths(run, lane)["report"]
    report_text = parsed["last_text"] or "(no report text: closed by watch, wrapper gone)"
    try:
        write_atomic(report_path, report_text.rstrip() + "\n")
        report_written = report_path
    except OSError as exc:
        report_written = None
        sys.stderr.write("lane.py: report not written (%s)\n" % exc)
    shown, n_shown, n_total, cut = cut_words(report_text, report_words)
    started = parse_ts(spawned.get("ts"))
    ended = os.path.getmtime(transcript) if transcript and os.path.isfile(transcript) else None
    duration = round(ended - started, 1) if (started and ended and ended >= started) else None
    close_line = {
        "ts": now(), "run": run, "lane": lane, "event": "lane-closed",
        "session_id": session_id, "class": opened.get("class"),
        "exit_class": "watch-closed", "exit_code": 0, "process_exit": None,
        "duration_s": duration, "subtype": None, "is_error": None,
        "num_turns": parsed.get("calls"), "total_cost_usd": None,
        "cost_src": "transcript-estimate",
        "usage": {"modelUsage": None, "peak_context": parsed["peak"],
                  "calls": parsed.get("calls", 0),
                  "first_call_context": parsed.get("first_call_context"),
                  "tokens": parsed.get("tokens")},
        "effort_applied": sorted(set(parsed["efforts"])) or None,
        "cache_write_tier": parsed["tiers"] or None,
        "denials": "unknown", "fence_denials_transcript": parsed["fence_denials"],
        "permission_denials": [], "transcript": parsed["transcript"],
        "report": report_written, "report_words": n_total, "report_shown": n_shown,
        "report_cut": cut, "limit_signal": None, "note": note,
        "wrapper_pid": spawned.get("wrapper_pid"), "stderr_tail": None, "parse_error": None}
    close_line.update(extra or {})
    append_record(record_path, close_line)
    return close_line


def log_tail(path, lines=6):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return "".join(handle.readlines()[-lines:])
    except OSError:
        return ""


def watch_lane(run, lane, record_path, home, projects_root, silence, poll, no_transcript_s,
               max_wait, report_words, fmt, session_id=None, worker=None, log_path=None):
    """The shared waiting loop of `watch` and the `--detach` foreground. Never kills a live
    wrapper's lane for silence unless `silence` is set; closes an orphaned lane (wrapper gone,
    no lane-closed) from its transcript once its process is gone or its recorded deadline
    passes. Returns the exit code."""
    began = time.time()
    unwatched = False
    stalled = None
    killed_at = None
    while True:
        records = load_record(record_path) if os.path.isfile(record_path) else []
        opened, spawned, closed = lane_state(records, lane, session_id)
        if closed:
            cls = closed.get("class") or (opened or {}).get("class")
            summary = summary_of(run, lane, cls, (opened or {}).get("model"),
                                 (opened or {}).get("effort"), closed)
            emit(summary, closed, report_words, fmt, opened)
            if stalled:
                return EXIT_CODES["stall"]
            if worker is not None:
                code = closed.get("exit_code")
                if isinstance(code, int):
                    return code
                try:
                    return worker.wait(timeout=KILL_GRACE_S)
                except subprocess.TimeoutExpired:
                    return 0
            return 0
        if worker is not None and worker.poll() is not None and not spawned:
            # The worker died before it started the lane: a premise failure or a crash; its
            # log holds the reason.
            sys.stderr.write(log_tail(log_path) if log_path else "")
            sys.stderr.write("lane.py: detached worker exited %s before lane-spawned\n"
                             % worker.returncode)
            return worker.returncode if worker.returncode else 3
        if opened and spawned:
            lane_pid = spawned.get("pid")
            wrapper_pid = spawned.get("wrapper_pid")
            if worker is not None:
                wrapper_alive = worker.poll() is None
            else:
                wrapper_alive = pid_alive(wrapper_pid) if wrapper_pid else None
            lane_alive = pid_alive(lane_pid)
            started = parse_ts(spawned.get("ts")) or began
            transcript = find_transcript(projects_root, home, spawned.get("session_id"))
            progress = progress_path(run, lane)
            orphan = (wrapper_alive is False
                      or (wrapper_alive is None and lane_alive is False
                          and time.time() - began > 2 * poll))
            if orphan:
                if lane_alive:
                    deadline_at = started + float(opened.get("deadline_s") or DEFAULT_DEADLINE_S)
                    reason = None
                    if time.time() > deadline_at:
                        reason = "deadline"
                    elif silence and silence > 0:
                        silent_s, label, bound = silence_of(started, transcript, progress,
                                                            silence, no_transcript_s)
                        if silent_s > bound and label == "silent":
                            reason = "stall"
                            stalled = stall_event(run, lane, spawned.get("session_id"), silent_s,
                                                  bound, label, "watch")
                            append_record(record_path, stalled)
                    if reason is None:
                        if max_wait and time.time() - began > max_wait:
                            print("still-running: lane %s/%s (wrapper gone, lane pid %s alive)"
                                  % (run, lane, lane_pid))
                            return EXIT_STILL_RUNNING
                        time.sleep(poll)
                        continue
                    kill_pid_group(lane_pid)
                    note = "closed by watch (wrapper gone; lane killed: %s)" % reason
                else:
                    note = "closed by watch (wrapper gone)"
                close_from_transcript(record_path, run, lane, opened, spawned, home,
                                      projects_root, note, report_words)
                continue
            if killed_at is not None:
                if time.time() - killed_at > KILL_GRACE_S + 2 * poll:
                    print("stall: lane %s/%s killed; its wrapper wrote no lane-closed within "
                          "%d s" % (run, lane, KILL_GRACE_S + 2 * poll))
                    return EXIT_CODES["stall"]
            elif silence and silence > 0:
                silent_s, label, bound = silence_of(started, transcript, progress, silence,
                                                    no_transcript_s)
                if silent_s > bound:
                    if label == "no transcript":
                        if not unwatched:
                            append_record(record_path, {
                                "ts": now(), "run": run, "lane": lane, "event": "unwatched",
                                "session_id": spawned.get("session_id"),
                                "note": "no transcript found under %s after %.0f s; the "
                                        "deadline stays the only bound" % (projects_root, silent_s)})
                            unwatched = True
                    else:
                        stalled = stall_event(run, lane, spawned.get("session_id"), silent_s,
                                              bound, label, "watch")
                        append_record(record_path, stalled)
                        kill_pid_group(lane_pid)
                        killed_at = time.time()
        elif worker is None:
            die("lane %s/%s is unknown in %s (no lane-open and lane-spawned)"
                % (run, lane, record_path))
        if max_wait and time.time() - began > max_wait:
            print("still-running: lane %s/%s after %.0f s" % (run, lane, time.time() - began))
            return EXIT_STILL_RUNNING
        time.sleep(poll if spawned else min(poll, 1.0))


# ------------------------------------------------------------------------ spawn -------------

def detach_spawn(args):
    """The double fork: a worker (its own session) runs the whole spawn and writes every
    record line; the foreground watches it, or with --no-wait returns at once."""
    session_id = args.session_id or str(uuid.uuid4())
    argv = [a for a in sys.argv[1:] if a not in ("--detach", "--no-wait")]
    if not args.session_id:
        argv += ["--session-id", session_id]
    argv.append("--as-worker")
    paths = store_paths(args.run, args.lane, args.record)
    try:
        os.makedirs(os.path.dirname(paths["detach_log"]), exist_ok=True)
        fd = os.open(paths["detach_log"], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    except OSError as exc:
        die("detach log is not writable (%s): %s" % (paths["detach_log"], exc))
    try:
        worker = subprocess.Popen([sys.executable, "-B", os.path.abspath(__file__)] + argv,
                                  stdin=subprocess.DEVNULL, stdout=fd, stderr=fd,
                                  start_new_session=True, close_fds=True)
    except OSError as exc:
        os.close(fd)
        die("could not start the detached worker: %s" % exc)
    os.close(fd)
    if args.no_wait:
        print("detached pid %d session %s" % (worker.pid, session_id))
        return 0
    home = os.path.realpath(os.path.expanduser(args.home or default_home()))
    projects_root = projects_root_for(args.projects_root, args.config_dir)
    # The worker runs the silence watch itself; the foreground never kills for silence.
    return watch_lane(args.run, args.lane, paths["record"], home, projects_root, None,
                      args.poll_s, args.no_transcript_s, 0, args.report_words, args.format,
                      session_id=session_id, worker=worker, log_path=paths["detach_log"])


def cmd_spawn(args):
    if args.detach and not args.dry_run:
        return detach_spawn(args)
    if args.no_wait:
        die("--no-wait goes with --detach")
    vault = vault_root()
    home = os.path.realpath(os.path.expanduser(args.home or default_home()))
    for required in ("lane-settings.json", "lane-fence.py"):
        if not os.path.isfile(os.path.join(home, required)):
            die("lane home %s has no %s — run `lane.py init` first" % (home, required))

    routing_path = args.routing or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                "routing.json")
    routing = load_routing(routing_path)
    cls = getattr(args, "class")
    if cls not in routing["classes"]:
        die("unknown class `%s` (routing table has: %s)"
            % (cls, ", ".join(sorted(routing["classes"]))))
    row = routing["classes"][cls]

    throttle = args.throttle or customisation_value("throttle", "default")
    throttle_note = None
    if throttle not in THROTTLES:
        throttle_note = "unknown throttle %r, treated as `default`" % throttle
        sys.stderr.write("lane.py: %s\n" % throttle_note)
        throttle = "default"
    model, effort, model_opts, effort_opts = resolve_tier(routing, row, cls, throttle)
    outside = []
    if args.model:
        if args.model not in model_opts:
            outside.append("model %s outside the class options %s" % (args.model, model_opts))
        model = args.model
    if args.effort:
        if args.effort not in effort_opts:
            outside.append("effort %s outside the class options %s" % (args.effort, effort_opts))
        effort = args.effort
    mode, mode_src, mode_from = resolve_delegation(args)

    if not os.path.isfile(args.brief):
        die("brief file not found: %s" % args.brief)
    brief = read_text(args.brief, "the brief")
    if not brief.strip():
        die("brief file is empty: %s" % args.brief)
    controls_checked = check_controls(parse_controls(brief), vault)

    config_dir = None
    if args.config_dir:
        config_dir = os.path.abspath(os.path.expanduser(args.config_dir))
        if not os.path.isdir(config_dir):
            die("--config-dir is not a directory: %s (a second login needs its own directory, "
                "logged in by the owner first)" % config_dir)

    grant_literals, grant_slots = split_placeholders(field(row, cls, "grants", "default"))
    write_literals, write_slots = split_placeholders(field(row, cls, "writes"))
    call_grants = resolve_entries(args.grant, vault, "granted path", True)
    call_writes = resolve_entries(args.write, vault, "write path", True)
    # A row's literal defaults (`wiki`, `raw`, `assets`) name the LIVE vault. A lane working on
    # a fixture must see none of it, so --grants-only drops them and makes the call the whole
    # scope; the dropped tokens go into the record rather than disappearing quietly.
    dropped = []
    if args.grants_only:
        if not call_grants:
            die("--grants-only needs at least one --grant: it drops the row's literal "
                "defaults, so the call is the lane's whole read scope")
        dropped = sorted(set(grant_literals + write_literals))
        grant_literals, write_literals = [], []
    grants = resolve_entries(grant_literals, vault, "class default grant", False)
    writes = resolve_entries(write_literals, vault, "class write directory", False)

    # A row's per-call slot is filled by the call. `--write` fills a write slot (and the
    # class's own memory directory fills one by itself, when the home holds it); `--grant`
    # fills a read slot, and so does `--write`, since a path a lane may write is necessarily
    # one it may read. A slot the call left empty is a premise failure that names the flag
    # which fills it.
    own_memory = memory_dir(home, cls)
    for slot in write_slots:
        if call_writes:
            continue
        if own_memory and not args.grants_only:
            # Under --grants-only the home's memory directory is a symlink into the vault, so
            # the auto-resolution is off and the slot takes a --write like any other.
            add_entry(writes, dir_entry(own_memory))
            continue
        die("class `%s` leaves `%s` to the call: needs --write for %s"
            % (cls, slot, slot))
    for slot in grant_slots:
        if call_grants or call_writes:
            continue
        flag = "--write" if slot in write_slots else "--grant"
        die("class `%s` leaves `%s` to the call: needs %s for %s" % (cls, slot, flag, slot))

    for entry in call_grants:
        add_entry(grants, entry)
    for entry in call_writes:
        add_entry(writes, entry)
    for entry in writes:
        add_entry(grants, entry)
    if args.grant_vault_root:
        add_entry(grants, {"given": vault_given(), "real": vault, "file": False})

    tools = ([t.strip() for t in args.tools.split(",") if t.strip()] if args.tools
             else list(field(row, cls, "tools")))
    if not tools:
        die("class `%s` resolves to an empty tool list" % cls)

    skills = list(field(row, cls, "skills", "default")) + list(args.skill or [])
    seen, ordered = set(), []
    for name in skills:
        if name not in seen:
            seen.add(name)
            ordered.append(name)
    skills = ordered
    defaults = field(row, cls, "skills", "default")

    mcp_default = field(row, cls, "mcp", "default")
    if mcp_default and not args.mcp_config:
        die("class `%s` names default MCP servers %r but no --mcp-config was passed"
            % (cls, mcp_default))

    definition_path, definition_sha, agent = thin_definition(
        vault, cls, tools, "thin %s lane" % cls)
    agents_json = json.dumps({cls: agent})

    # The appended file: the one carrier of everything the lane reads besides its brief.
    # Order is the row's, core first; `lane-core` in the row list IS the core, so naming it
    # there never doubles it.
    sections, appended_names = [], []
    if not args.no_core:
        if args.append_core:
            if not os.path.isfile(args.append_core):
                die("--append-core file not found: %s" % args.append_core)
            core_path = os.path.abspath(args.append_core)
        else:
            core_path = os.path.join(home, CORE_NAME)
            if not os.path.isfile(core_path):
                core_path = core_source(vault)
        if not os.path.isfile(core_path):
            if CORE_SLICE in defaults:
                die("class `%s` names the default slice `%s`, but no lane core is installed "
                    "(looked in the lane home and %s) — run `lane.py init`"
                    % (cls, CORE_SLICE, display_path(core_source(vault), vault)))
            sys.stderr.write("lane.py: no lane core found; spawning without one\n")
        else:
            sections.append((CORE_SLICE, core_path,
                             strip_frontmatter(read_text(core_path, "the lane core"))))
            appended_names.append(CORE_SLICE)
    for name in skills:
        if name == CORE_SLICE:
            continue
        path, body = resolve_slice(name, home, vault)
        if path is None:
            if name in defaults:
                die("class `%s` needs the default skill slice `%s`, which resolves nowhere "
                    "(looked in the lane home's skills/ and %s) — run `lane.py init` after "
                    "the slice is installed"
                    % (cls, name, display_path(slice_sources(vault), vault)))
            sys.stderr.write("lane.py: skill `%s` resolves to no slice; it is not appended\n"
                             % name)
            continue
        sections.append((name, path, body))
        appended_names.append(name)
    appended_text = ""
    for name, path, body in sections:
        appended_text += ("## Lane slice: %s — source: %s\n\n%s\n\n"
                          % (name, display_path(path, vault), body.strip()))
    appended_bytes = len(appended_text.encode("utf-8"))

    session_id = args.session_id or str(uuid.uuid4())
    budget = args.budget_usd
    breadth = customisation_value("breadth", DEFAULT_BREADTH)
    if budget is None:
        budget = BREADTH_BUDGET.get(breadth, BREADTH_BUDGET[DEFAULT_BREADTH])
    deadline = args.deadline_s or DEFAULT_DEADLINE_S
    trust = trust_state(home, config_dir)
    if args.require_trust and trust is not True:
        die("lane home %s has no accepted workspace-trust entry in .claude.json (state: %s) "
            "— a headless run on an untrusted workspace degrades silently"
            % (home, {True: "accepted", False: "declined", None: "absent"}[trust]))

    paths = store_paths(args.run, args.lane, args.record)
    record_path = paths["record"]
    silence, silence_src = resolve_silence(args, record_path)
    projects_root = projects_root_for(args.projects_root, config_dir)
    progress = progress_path(args.run, args.lane)

    # The lane's own input directory: the brief copied in, the head's hand inputs beside it,
    # granted read in both spellings; the store itself only when the call names it.
    input_entry = dir_entry(paths["input_dir"])
    brief_abs = os.path.abspath(args.brief)
    if os.path.realpath(brief_abs).startswith(input_entry["real"] + os.sep):
        brief_copy = brief_abs
    else:
        brief_copy = os.path.join(paths["input_dir"], "%s-brief-%s.md" % (args.run, args.lane))
    add_dirs = add_dirs_for(grants + [input_entry])
    grants_env = os.pathsep.join(reals(grants) + [input_entry["real"], home, "/tmp"])
    writes_env = os.pathsep.join(reals(writes))
    settings, settings_allow = settings_for(home, writes)
    env = dict(os.environ)
    env.update({"LLM_WIKI_LANE": "1", "LLM_WIKI_LANE_RUN": args.run, "LLM_WIKI_LANE_ID": args.lane,
                "LLM_WIKI_LANE_GRANTS": grants_env, "LLM_WIKI_LANE_WRITES": writes_env,
                "LLM_WIKI_LANE_PROGRESS": progress})
    if config_dir:
        env["CLAUDE_CONFIG_DIR"] = config_dir

    command = ["claude", "-p", "--agents", agents_json, "--agent", cls,
               "--model", model, "--effort", effort, "--restricted",
               "--tools", ",".join(tools),
               "--settings", paths["settings"],
               "--strict-mcp-config", "--session-id", session_id,
               "--max-budget-usd", str(budget), "--permission-prompts", "none",
               "--output-format", "json"]
    for path in add_dirs:
        command += ["--add-dir", path]
    if args.mcp_config:
        command += ["--mcp-config", args.mcp_config]
    if appended_text:
        command += ["--append-system-prompt-file", paths["appended"]]
    if args.max_turns:
        command += ["--max-turns", str(args.max_turns)]
    if writes:
        command += ["--permission-mode", "acceptEdits"]
    if args.prompt_arg:
        command.append(brief)

    open_line = {
        "ts": now(), "run": args.run, "lane": args.lane, "event": "lane-open",
        "class": cls, "definition": os.path.relpath(definition_path, vault),
        "definition_sha256": definition_sha, "definition_copy": paths["definition_copy"],
        "model": model, "effort": effort, "throttle": throttle, "tools": tools,
        "grants": reals(grants), "writes": reals(writes),
        "grants_files": files_of(grants), "writes_files": files_of(writes),
        "add_dirs": add_dirs, "input_dir": paths["input_dir"],
        "grant_vault_root": bool(args.grant_vault_root),
        "grants_env": grants_env, "writes_env": writes_env,
        "row_literals_dropped": dropped,
        "controls_checked": controls_checked,
        "settings": paths["settings"], "settings_allow": settings_allow,
        "config_dir": config_dir, "projects_root": projects_root,
        "skills": skills, "mcp": ([args.mcp_config] if args.mcp_config else []),
        "appended": appended_names, "appended_bytes": appended_bytes,
        "appended_file": paths["appended"] if appended_text else None,
        "cache_tier_expected": row.get("cache", "unstated"),
        "session_id": session_id, "budget_usd": budget, "breadth": breadth,
        "max_turns": args.max_turns, "deadline_s": deadline,
        "silence_s": silence, "silence_src": silence_src, "poll_s": args.poll_s,
        "progress_file": progress, "report_words_cap": args.report_words,
        "reason": args.reason, "plant": args.plant, "reading_list": args.reading_list,
        "brief": brief_abs, "brief_copy": brief_copy, "mode": mode, "mode_src": mode_src,
        "mode_from": mode_from, "baseline": args.baseline,
        "baseline_lane": args.baseline_lane or None,
        "cwd": home, "workspace_trust": trust,
        "mechanism": "lane.py headless (claude -p --agents/--agent, --restricted, "
                     "lane-side fence hook, per-spawn settings, silence watch)"}
    if outside:
        open_line["outside_options"] = outside
    if throttle_note:
        open_line["throttle_note"] = throttle_note

    if args.dry_run:
        print("command:")
        print("  " + " ".join(shlex.quote(part) for part in command))
        print("environment:")
        for key in ("LLM_WIKI_LANE", "LLM_WIKI_LANE_RUN", "LLM_WIKI_LANE_ID",
                    "LLM_WIKI_LANE_GRANTS", "LLM_WIKI_LANE_WRITES", "LLM_WIKI_LANE_PROGRESS"):
            print("  %s=%s" % (key, env[key]))
        if config_dir:
            print("  CLAUDE_CONFIG_DIR=%s" % config_dir)
        print("add-dirs: %s" % " ".join(add_dirs))
        print("settings (%s): allow %s" % (paths["settings"], settings_allow or "none"))
        print("controls checked: %s" % json.dumps(controls_checked))
        print("silence: %s s (%s)" % (silence, silence_src))
        print("brief delivery: %s" % ("prompt argument" if args.prompt_arg else "stdin"))
        print("appended system prompt (%s, %d bytes): %s"
              % (paths["appended"], appended_bytes, ", ".join(appended_names) or "nothing"))
        print("record line (%s):" % record_path)
        print("  " + json.dumps(open_line))
        print("would write: %s · %s · %s · %s/%s"
              % (paths["definition_copy"], paths["report"], paths["settings"],
                 paths["input_dir"], os.path.basename(brief_copy)))
        return 0

    append_record(record_path, open_line)
    if appended_text:
        try:
            write_atomic(paths["appended"], appended_text)
        except OSError as exc:
            die("the appended system-prompt file is not writable (%s): %s"
                % (paths["appended"], exc))
    try:
        write_atomic(paths["settings"], json.dumps(settings, indent=2) + "\n")
    except OSError as exc:
        die("the per-spawn settings file is not writable (%s): %s" % (paths["settings"], exc))
    try:
        os.makedirs(paths["input_dir"], exist_ok=True)
        if brief_copy != brief_abs:
            shutil.copyfile(brief_abs, brief_copy)
    except OSError as exc:
        die("the lane's input directory is not writable (%s): %s" % (paths["input_dir"], exc))
    try:
        write_atomic(paths["definition_copy"], definition_markdown(cls, agent, model, effort))
    except OSError as exc:
        sys.stderr.write("lane.py: definition copy not written (%s)\n" % exc)

    ctx = {"run": args.run, "lane": args.lane, "cls": cls, "model": model, "effort": effort,
           "command": command, "env": env, "home": home,
           "stdin": None if args.prompt_arg else brief, "deadline": deadline,
           "silence": silence, "poll": args.poll_s, "no_transcript_s": args.no_transcript_s,
           "record": record_path, "report_path": paths["report"],
           "projects_root": projects_root, "session_id": session_id, "progress": progress,
           "report_words": args.report_words, "format": args.format,
           "spawn_event": "lane-spawned", "detached": bool(args.as_worker),
           "open_line": open_line}
    return run_lane(ctx)


# ----------------------------------------------------------------------- watch --------------

def cmd_watch(args):
    paths = store_paths(args.run, args.lane, args.record)
    # A detached worker writes lane-open and lane-spawned within a second of its start; a
    # watch issued right after `--detach --no-wait` waits up to --appear-s for them.
    opened = spawned = closed = None
    waited = 0.0
    while True:
        if os.path.isfile(paths["record"]):
            opened, spawned, closed = lane_state(load_record(paths["record"]), args.lane)
        if (opened and spawned) or waited >= args.appear_s:
            break
        time.sleep(0.5)
        waited += 0.5
    if not os.path.isfile(paths["record"]):
        die("no spawn record at %s" % paths["record"])
    if not opened or not spawned:
        die("lane %s/%s is unknown in %s (no lane-open and lane-spawned)"
            % (args.run, args.lane, paths["record"]))
    if closed:
        print(summary_of(args.run, args.lane, closed.get("class") or opened.get("class"),
                         opened.get("model"), opened.get("effort"), closed))
        die("lane %s/%s is already closed (%s at %s)"
            % (args.run, args.lane, closed.get("exit_class"), closed.get("ts")))
    home = os.path.realpath(os.path.expanduser(args.home or opened.get("cwd") or default_home()))
    projects_root = projects_root_for(args.projects_root or opened.get("projects_root"),
                                      opened.get("config_dir"))
    silence = args.silence_s if (args.silence_s and args.silence_s > 0) else None
    return watch_lane(args.run, args.lane, paths["record"], home, projects_root, silence,
                      args.poll_s, args.no_transcript_s, args.max_wait_s, args.report_words,
                      args.format, session_id=spawned.get("session_id"))


# ---------------------------------------------------------------------- resume --------------

def cmd_resume(args):
    vault = vault_root()
    paths = store_paths(args.run, args.lane, args.record)
    if not os.path.isfile(paths["record"]):
        die("no spawn record at %s" % paths["record"])
    records = load_record(paths["record"])
    opened, spawned, closed = lane_state(records, args.lane)
    if not opened or not spawned:
        die("lane %s/%s is unknown in %s (no lane-open and lane-spawned)"
            % (args.run, args.lane, paths["record"]))
    if not closed:
        die("lane %s/%s has no lane-closed yet — resume re-enters a finished lane; `watch` it "
            "first" % (args.run, args.lane))
    if closed.get("exit_class") == "spawn-failed":
        die("lane %s/%s never started (spawn-failed); re-spawn it" % (args.run, args.lane))
    last = parse_ts(closed.get("ts"))
    if last is None:
        die("lane %s/%s: lane-closed carries no parseable ts (%r)"
            % (args.run, args.lane, closed.get("ts")))
    age = time.time() - last
    # D29: the window is a cost rule, not a safety rule, and a lane stopped by the account limit
    # is resumed after the reset however long that took — one cold re-read of its context, once
    # per lane, against the whole task re-run that a re-spawn would cost.
    after_limit = closed.get("exit_class") == "limit"
    if age > RESUME_WINDOW_S and not after_limit:
        die("lane %s/%s: last call %.0f min ago, over the %d-minute resume window — the cache "
            "has lapsed; re-spawn with the finding in the brief instead"
            % (args.run, args.lane, age / 60.0, RESUME_WINDOW_S // 60))
    if after_limit and age > RESUME_WINDOW_S:
        print("lane %s/%s: closed on a limit %.0f min ago — the %d-minute cache window is waived "
              "(D29); expect a cold re-read of the lane's context on this first call"
              % (args.run, args.lane, age / 60.0, RESUME_WINDOW_S // 60))
    if not os.path.isfile(args.brief):
        die("brief file not found: %s" % args.brief)
    brief = read_text(args.brief, "the follow-up brief")
    if not brief.strip():
        die("brief file is empty: %s" % args.brief)
    controls_checked = check_controls(parse_controls(brief), vault)

    cls = opened.get("class")
    model, effort = opened.get("model"), opened.get("effort")
    tools = opened.get("tools") or []
    if not (cls and model and effort and tools):
        die("lane %s/%s: lane-open lacks class, model, effort or tools" % (args.run, args.lane))
    session_id = closed.get("session_id") or spawned.get("session_id") or opened.get("session_id")
    home = os.path.realpath(os.path.expanduser(args.home or opened.get("cwd") or default_home()))
    config_dir = opened.get("config_dir")
    if config_dir and not os.path.isdir(config_dir):
        die("lane %s/%s: recorded config_dir %s is gone" % (args.run, args.lane, config_dir))
    projects_root = projects_root_for(args.projects_root or opened.get("projects_root"), config_dir)
    # D29: a resume re-enters a session by its transcript. No transcript, no session to re-enter —
    # the harness would start a fresh one under the old id and the lane would answer from nothing.
    if not find_transcript(projects_root, home, session_id):
        die("lane %s/%s: no transcript for session %s under %s — the session cannot be re-entered; "
            "re-spawn the lane with the finding in the brief instead"
            % (args.run, args.lane, session_id, projects_root))
    settings = opened.get("settings") or os.path.join(home, "lane-settings.json")
    if not os.path.isfile(settings):
        die("lane %s/%s: settings file %s is gone" % (args.run, args.lane, settings))
    add_dirs = list(opened.get("add_dirs") or opened.get("grants") or [])
    for path in add_dirs:
        if not os.path.exists(path):
            die("lane %s/%s: granted path %s is gone" % (args.run, args.lane, path))
    writes = list(opened.get("writes") or [])
    appended = opened.get("appended_file")
    if appended and not os.path.isfile(appended):
        die("lane %s/%s: appended file %s is gone" % (args.run, args.lane, appended))
    definition_path, definition_sha, agent = thin_definition(vault, cls, tools, "thin %s lane" % cls)
    budget = args.budget_usd if args.budget_usd is not None else opened.get("budget_usd")
    if budget is None:
        budget = BREADTH_BUDGET[DEFAULT_BREADTH]
    deadline = args.deadline_s or opened.get("deadline_s") or DEFAULT_DEADLINE_S
    if args.silence_s is None:
        silence = opened.get("silence_s")
        silence_src = "lane-open"
        if silence is None:
            silence, silence_src = DEFAULT_SILENCE_S, "default"
    else:
        silence, silence_src = resolve_silence(args, paths["record"])
    progress = progress_path(args.run, args.lane)
    resume_n = 1 + sum(1 for r in records
                       if r.get("lane") == args.lane and r.get("event") == "lane-resumed")
    brief_abs = os.path.abspath(args.brief)
    brief_copy = os.path.join(paths["input_dir"], "%s-brief-%s-resume-%d.md"
                              % (args.run, args.lane, resume_n))

    grants_env = opened.get("grants_env") or os.pathsep.join(
        list(opened.get("grants") or []) + [home, "/tmp"])
    writes_env = opened.get("writes_env") or os.pathsep.join(writes)
    env = dict(os.environ)
    env.update({"LLM_WIKI_LANE": "1", "LLM_WIKI_LANE_RUN": args.run, "LLM_WIKI_LANE_ID": args.lane,
                "LLM_WIKI_LANE_GRANTS": grants_env, "LLM_WIKI_LANE_WRITES": writes_env,
                "LLM_WIKI_LANE_PROGRESS": progress})
    if config_dir:
        env["CLAUDE_CONFIG_DIR"] = config_dir

    command = ["claude", "-p", "--resume", session_id, "--agents", json.dumps({cls: agent}),
               "--agent", cls, "--model", model, "--effort", effort, "--restricted",
               "--tools", ",".join(tools), "--settings", settings, "--strict-mcp-config",
               "--max-budget-usd", str(budget), "--permission-prompts", "none",
               "--output-format", "json"]
    for path in add_dirs:
        command += ["--add-dir", path]
    if appended:
        command += ["--append-system-prompt-file", appended]
    max_turns = args.max_turns or opened.get("max_turns")
    if max_turns:
        command += ["--max-turns", str(max_turns)]
    if writes:
        command += ["--permission-mode", "acceptEdits"]

    try:
        os.makedirs(paths["input_dir"], exist_ok=True)
        shutil.copyfile(brief_abs, brief_copy)
    except OSError as exc:
        die("the lane's input directory is not writable (%s): %s" % (paths["input_dir"], exc))

    ctx = {"run": args.run, "lane": args.lane, "cls": cls, "model": model, "effort": effort,
           "command": command, "env": env, "home": home, "stdin": brief, "deadline": deadline,
           "silence": silence, "poll": args.poll_s, "no_transcript_s": args.no_transcript_s,
           "record": paths["record"], "report_path": paths["report"],
           "projects_root": projects_root, "session_id": session_id, "progress": progress,
           "report_words": args.report_words, "format": args.format,
           "spawn_event": "lane-resumed", "detached": False, "open_line": opened,
           "spawn_extra": {"brief": brief_abs, "brief_copy": brief_copy, "resume_n": resume_n,
                           "resumes_close_ts": closed.get("ts"), "age_s": round(age, 1),
                           "after_limit": after_limit,
                           "controls_checked": controls_checked, "budget_usd": budget,
                           "deadline_s": deadline, "silence_s": silence,
                           "silence_src": silence_src, "definition_sha256": definition_sha},
           "close_extra": {"resumed": True, "resume_n": resume_n}}
    return run_lane(ctx)


# ------------------------------------------------------------------------- cli --------------

def add_wait_flags(parser):
    parser.add_argument("--silence-s", type=float, default=None,
                        help="stall threshold in seconds (default %d; 0 disables the watch)"
                             % DEFAULT_SILENCE_S)
    parser.add_argument("--poll-s", type=float, default=POLL_S,
                        help="liveness check interval in seconds (default %d)" % POLL_S)
    parser.add_argument("--no-transcript-s", type=float, default=NO_TRANSCRIPT_S,
                        help="seconds without a transcript that count as a stall (default %d)"
                             % NO_TRANSCRIPT_S)
    parser.add_argument("--report-words", type=int, default=REPORT_WORDS,
                        help="words of the report printed to stdout (default %d; 0 prints the "
                             "pointer line only)" % REPORT_WORDS)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--record", help="spawn record path (default: the run store)")
    parser.add_argument("--projects-root")
    parser.add_argument("--home")


def build_parser():
    parser = argparse.ArgumentParser(
        prog="lane.py", description="Spawn a thin headless lane from a lane home.")
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init", help="build or refresh the base lane home")
    init.add_argument("--home", help="lane home (default: $LLM_WIKI_LANE_HOME or the run store)")
    init.set_defaults(func=cmd_init)

    spawn = sub.add_parser("spawn", help="spawn one lane and record it")
    spawn.add_argument("--run", required=True)
    spawn.add_argument("--lane", required=True)
    spawn.add_argument("--class", required=True, dest="class")
    spawn.add_argument("--brief", required=True)
    spawn.add_argument("--model")
    spawn.add_argument("--effort")
    spawn.add_argument("--grant", action="append", default=[],
                       help="a directory or file the lane may read (repeatable)")
    spawn.add_argument("--write", action="append", default=[],
                       help="a directory or file the lane may write (repeatable)")
    spawn.add_argument("--grant-vault-root", action="store_true",
                       help="grant the vault root itself as a read grant")
    spawn.add_argument("--grants-only", action="store_true",
                       help="drop the row's literal grants and writes, so the call's --grant "
                            "and --write are the lane's whole scope (a fixture-bound lane)")
    spawn.add_argument("--config-dir", help="CLAUDE_CONFIG_DIR for the lane process only "
                                            "(a second login)")
    spawn.add_argument("--tools", help="comma-separated override of the class tool set")
    spawn.add_argument("--skill", action="append", default=[])
    spawn.add_argument("--mcp-config")
    spawn.add_argument("--no-core", action="store_true",
                       help="leave the lane core out of the appended file (slices still go in)")
    spawn.add_argument("--append-core", metavar="FILE",
                       help="use this file as the lane core instead of the home's copy")
    spawn.add_argument("--reason", default="")
    spawn.add_argument("--plant", default="")
    spawn.add_argument("--reading-list", default="")
    spawn.add_argument("--budget-usd", type=float)
    spawn.add_argument("--max-turns", type=int)
    spawn.add_argument("--deadline-s", type=int)
    spawn.add_argument("--baseline-lane", default="",
                       help="raise the stall threshold to 1.5 x this lane's recorded duration")
    spawn.add_argument("--session-id")
    spawn.add_argument("--throttle")
    spawn.add_argument("--routing")
    spawn.add_argument("--baseline", default="")
    spawn.add_argument("--delegation", choices=REGIMES,
                       help="the run's delegation regime for the record (required while the "
                            "Settings line reads auto); goes with --delegation-src")
    spawn.add_argument("--delegation-src", choices=("head", "owner"),
                       help="who chose it: head (resolved under auto) or owner")
    spawn.add_argument("--require-trust", action="store_true",
                       help="treat a missing workspace-trust entry as a premise failure")
    spawn.add_argument("--prompt-arg", action="store_true",
                       help="pass the brief as the prompt argument instead of on stdin")
    spawn.add_argument("--detach", action="store_true",
                       help="run the lane in a worker that survives the caller; the foreground "
                            "watches it")
    spawn.add_argument("--no-wait", action="store_true",
                       help="with --detach: print `detached pid N session S` and return at once")
    spawn.add_argument("--dry-run", action="store_true")
    spawn.add_argument("--as-worker", action="store_true", help=argparse.SUPPRESS)
    add_wait_flags(spawn)
    spawn.set_defaults(func=cmd_spawn)

    watch = sub.add_parser("watch", help="wait on a running lane; close it if its wrapper is gone")
    watch.add_argument("--run", required=True)
    watch.add_argument("--lane", required=True)
    watch.add_argument("--max-wait-s", type=float, default=WATCH_MAX_WAIT_S,
                       help="return `still-running` (exit %d) after this many seconds "
                            "(default %d; 0 waits without bound)"
                            % (EXIT_STILL_RUNNING, WATCH_MAX_WAIT_S))
    watch.add_argument("--appear-s", type=float, default=WATCH_APPEAR_S,
                       help="seconds to wait for a just-detached lane's record lines before "
                            "calling it unknown (default %d)" % WATCH_APPEAR_S)
    add_wait_flags(watch)
    watch.set_defaults(func=cmd_watch)

    resume = sub.add_parser("resume", help="re-enter a finished lane's session with a follow-up "
                                           "brief (D29: after a `limit` close the cache window is "
                                           "waived and `lane-resumed` records after_limit and age_s)")
    resume.add_argument("--run", required=True)
    resume.add_argument("--lane", required=True)
    resume.add_argument("--brief", required=True)
    resume.add_argument("--budget-usd", type=float)
    resume.add_argument("--max-turns", type=int)
    resume.add_argument("--deadline-s", type=int)
    resume.add_argument("--baseline-lane", default="")
    add_wait_flags(resume)
    resume.set_defaults(func=cmd_resume)
    return parser


def main():
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
