---
description: Seed git-notes-memory in this repo — draft an architecture note for approval, import .agent/learnings.md, and offer to move repo learnings out of CLAUDE.md.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/init.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/note.sh *)
disable-model-invocation: true
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/init.sh` with Bash. It protects the root-commit notes across amend and rebase, and reports what the repo already has. Then work through these steps in order, skipping any that don't apply. Follow the git-notes skill for the note format.

1. **Remote notes.** If it reports staged notes on origin, stop and tell the user to run `/git-notes-memory:notes-sync --trust` first (or `--ignore`), then re-run init. Never read `refs/notes/origin/*` yourself.

2. **Architecture note.** If it's missing, survey the repo: README, manifests (go.mod, package.json, Cargo.toml, pyproject.toml, …), the top-level layout, entry points, and how the parts depend on each other. Draft a note of at most ~15 lines: what the system is, its main components and how they connect, and the key decisions with their reasons. Show the draft to the user and write it with `${CLAUDE_PLUGIN_ROOT}/scripts/note.sh architecture "<text>"` only after they approve it. If one already exists, offer to review it against the code instead.

3. **`.agent/learnings.md`.** If it exists, read it and append each entry that still holds with `${CLAUDE_PLUGIN_ROOT}/scripts/note.sh learning "<entry>"`. An entry about a single file becomes a file note instead (`note.sh <path> "<entry>"`). Check each entry against the code first, and drop ones that no longer apply. Then offer to delete the file; don't delete it unasked.

4. **CLAUDE.md.** If a project CLAUDE.md exists, list the entries in it that are repo learnings (gotchas, conventions, footguns) rather than instructions for working in the repo. Propose moving them to notes, but only move the ones the user picks: people and tools without the plugin also read CLAUDE.md.

Don't move code comments into notes during init.

Finish with a short summary of what was written, what was skipped, and why.
