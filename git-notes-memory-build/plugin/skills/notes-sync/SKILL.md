---
description: Migrate git-notes-memory file notes across commits made since the last sync, e.g. after a pull, merge or rebase.
argument-hint: [--push]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh *)
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh $ARGUMENTS` with Bash.

Report each `needs-review:` path it prints; those notes were copied to new file versions and must be re-verified with `/git-notes-memory:note <path> "<text>"`. If it printed nothing, say notes are in sync. `--push` sends `refs/notes/*` to origin only when `GIT_NOTES_MEMORY_SYNC=1`.
