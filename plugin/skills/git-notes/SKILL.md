---
name: git-notes
description: Use in a git repo that has refs/notes/architecture, learnings or file-notes, or when asked to record or recall project decisions, learnings, architecture, or why a file is the way it is.
user-invocable: false
---

# git-notes-memory protocol

Project memory lives in git notes, not CLAUDE.md:

- `refs/notes/architecture`: one note on the root commit, holding the project's architecture and key decisions. Injected at session start.
- `refs/notes/learnings`: one append-only note on the root commit, holding repo-wide and directory-wide learnings. Injected at session start.
- `refs/notes/file-notes`: notes on file **blob** hashes, saying why a file is the way it is. Injected when you Read, Edit or Write the file.
- `refs/notes/meta`: bookkeeping (`last-synced`). Don't edit.

Blob notes are content-pinned: any edit changes the hash. Hooks copy the note to the new version as `status: needs-review`. A note labelled "from earlier version … possibly stale" or "UNVERIFIED" may no longer match the code.

Rules:

1. A learning about one file goes on that file: `/git-notes-memory:note <path> "<text>"`. Anything wider: `/git-notes-memory:note learning "<text>"`. Keep notes about *why*, not *what*.
2. After editing a file that has a note, or on any `needs-review` note, check the note against the code. Then rewrite it, delete it (`--delete`), or promote it to real docs and delete it.
3. Do not end a session with unresolved `needs-review` notes.
4. The architecture note is propose-only: on drift, suggest new text to the user; never overwrite it unprompted.
5. `/git-notes-memory:note --list` shows every note by path; use it when pruning.
