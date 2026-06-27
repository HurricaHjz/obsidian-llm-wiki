#!/usr/bin/env bash
# setup.sh — first-run bootstrap for the obsidian-llm-wiki framework.
#
#   bash setup.sh                 create empty registries (wiki/index.md, wiki/log.md) if missing
#   bash setup.sh --with-example  also load the demo from examples/seed/ into wiki/ + raw/
#   bash setup.sh --reset         remove the demo and blank the registries (start your own)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p wiki raw

mk_index() {
  cat > wiki/index.md <<'IDX'
---
title: "Wiki Index"
type: index
---

# Wiki Index

> Global catalogue. **Read this first** when answering a query, then drill into the relevant pages.
> Auto-maintained by the `ingest` skill. Format: `- [[Page Name]] — one-line description.`

## Sources
## Entities
## Tools
## Models
## Benchmarks
## Concepts
## Syntheses
## Developments
## Maps
## User
IDX
}

mk_log() {
  cat > wiki/log.md <<'LOG'
# Wiki Log

> Append-only timeline. Append a `## [date] action | title` entry on every brain-updating op — via shell
> (`cat >> wiki/log.md`), never by reading the whole file. Actions: ingest · query · lint · sync · setup · maps.

## [setup] Initialised from the obsidian-llm-wiki framework
- **Changed**: created the directory scaffold + registries.
LOG
}

DEMO_RAW="raw/2-papers/example-gpt4-and-mmlu.md"
DEMO_WIKI=("wiki/sources/example-gpt4-and-mmlu.md" "wiki/concepts/Large Language Model.md" \
           "wiki/entities/OpenAI.md" "wiki/models/GPT.md" "wiki/benchmarks/MMLU.md" "wiki/maps/home.md")

case "${1:-}" in
  --with-example)
    [ -f wiki/index.md ] || mk_index
    [ -f wiki/log.md ]   || mk_log
    if [ -d examples/seed ]; then
      cp -R examples/seed/raw/.  raw/
      cp -R examples/seed/wiki/. wiki/
      echo "✓ demo loaded. Open the graph view, then ask the agent:  /query what is GPT?"
      echo "  When finished exploring:  bash setup.sh --reset"
    else
      echo "! examples/seed not found — created empty registries only."
    fi
    ;;
  --reset)
    rm -f "$DEMO_RAW" "${DEMO_WIKI[@]}" 2>/dev/null || true
    mk_index; mk_log
    echo "✓ reset: demo removed, registries blanked. Drop a source into raw/ and run /ingest."
    ;;
  ""|--init)
    [ -f wiki/index.md ] || mk_index
    [ -f wiki/log.md ]   || mk_log
    echo "✓ ready. Drop a source into raw/ and run /ingest"
    echo "  (or try the demo first:  bash setup.sh --with-example)"
    ;;
  *)
    echo "usage: bash setup.sh [--with-example | --reset]"; exit 1 ;;
esac
