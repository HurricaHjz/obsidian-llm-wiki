# Contributing

Thanks for your interest! This repo is the **framework** for a self-maintaining LLM-Wiki second brain
(Obsidian + an AI coding agent). Contributions that improve the *framework* are welcome.

## What lives here (and what doesn't)
- **In scope (tracked):** `CLAUDE.md`, `Manual.md`, `.claude/skills/**`, `.obsidian/` config, the folder
  skeleton (`.gitkeep`), and the demo in `examples/`.
- **Never committed:** anyone's actual knowledge — `wiki/`, `raw/`, `index.md`, `log.md`, `output/`,
  `okf-export/` are git-ignored. Please don't add personal notes or content to the repo.

## How to contribute
- **Issues / ideas:** open an issue describing the workflow problem or the improvement.
- **Pull requests:** keep changes to the framework (skills, rules, docs). A good PR is small and focused.
- **Skills** are a `SKILL.md` (the contract) plus optional helper scripts *with tests* — see
  `.claude/skills/gather/` (`gather_links.py` + `test_gather_links.py`). If you touch a helper, run its
  `test_*.py` and keep it green.
- **Docs:** British/UK English (the vault convention). Keep the always-loaded `CLAUDE.md` lean — put depth
  in skill bodies (they load only when the skill runs).
- **Integrity:** no dead links / orphans / unindexed pages (the `lint` skill's checks).

## Philosophy
Compile knowledge once, reuse it (not RAG). Token-efficiency is a first-class constraint: prefer opt-in
and fallback-only designs for anything expensive. Specialised for AI/LLM research, but kept reusable.
