---
description: Write, show, delete or list git-notes-memory notes — a file note, the repo-wide learnings note, or the architecture note. Use to record a learning or why code is the way it is, or to re-verify a needs-review note after editing a file.
argument-hint: <architecture|learning|path> [--force|--delete] ["text"] | --list
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/note.sh *)
---

Run `${CLAUDE_PLUGIN_ROOT}/scripts/note.sh $ARGUMENTS` with Bash and report the result.

- With only a target, it prints the note. `--delete` removes it. `--list` lists all notes with their status and path.
- `learning "<text>"` appends an entry; no confirmation needed. `learning --force "<text>"` replaces the whole learnings note: print it first and keep every entry you aren't deliberately pruning.
- If a file note write exits 3, a `current` note already exists and was printed. Show it to the user and ask whether to overwrite. Only re-run with `--force` after they say yes.
- A `needs-review` note may be overwritten without `--force`; that is how it is re-verified.
- For `architecture`, never overwrite unprompted: propose the new text and wait for the user to agree.
