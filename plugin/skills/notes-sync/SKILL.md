---
description: Migrate git-notes-memory file notes across commits made since the last sync, e.g. after a pull, merge or rebase.
argument-hint: [--push|--trust|--ignore]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh *)
disable-model-invocation: true
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh $ARGUMENTS` with Bash.

Report each `needs-review:` path it prints; those notes were copied to new file versions and must be re-verified with `/git-notes-memory:note <path> "<text>"`. If it printed nothing, say notes are in sync. `--trust` merges origin's `file-notes`, `learnings` and `architecture` notes into the local ones and trusts origin, so later sessions merge them automatically. `--push` does the same, then pushes those three refs. `--ignore` stops session start from fetching origin's notes or asking about them. Report the `merged from origin:` line and each `conflict:` line; for a conflict the local note was kept and the remote one dropped.
