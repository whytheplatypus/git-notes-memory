---
name: git-notes
description: Project memory in git notes. Use right after you are corrected (by the user, a test or a build), after wasting tool calls on something a one-line note would have prevented, on finding an unstated convention or a footgun, before writing a code comment that explains why, when handling a needs-review note, or when asked to record or recall decisions, learnings, architecture, or why a file is the way it is.
user-invocable: false
---

# git-notes-memory protocol

Project memory lives in git notes, next to the code it describes:

- `refs/notes/file-notes`: notes on file **blob** hashes, saying why a file is the way it is. Shown when the file is read or edited.
- `refs/notes/learnings`: one append-only note on the root commit, for repo-wide and directory-wide learnings. Shown at session start.
- `refs/notes/architecture`: one note on the root commit, holding the architecture and key decisions. Shown at session start. Propose-only.
- `refs/notes/meta`: bookkeeping (`last-synced`). Don't edit.

## Notes over code comments

Keep code self-explanatory: say *what* through names, structure and small functions. Put the *why* (rationale, history, rejected alternatives, gotchas) in a file note, not a comment. A comment is still right, within reason, when:

- a reader of that exact line would be misled or break something without it, and restructuring can't make it obvious (an ordering dependency, a workaround for an external bug);
- tools or API users read it (doc comments on a public API, license headers, directives);
- the surrounding code clearly does it by convention; match it.

Don't move existing comments into notes unless asked.

## When to write

Write immediately, not at the end of the session (sessions get cut short):

- **You were wrong and corrected**, by a human, a test failure or a build error, in a way that wasn't obvious from the code. The correction is the learning.
- **You wasted more than ~2 tool calls** on something a one-line note would have prevented: a flaky test, a misleading name, an undocumented env var, a build step that must run first.
- **You found an implicit convention**: naming, error handling, a pattern the repo uses consistently but doesn't state.
- **You found a footgun**: something that looks safe to change but breaks something non-adjacent.

Don't write:

- what README, ADRs or existing comments already say; point to them instead;
- task state ("PR #42 still needs review"); that's a TODO;
- anything obvious from reading the code once;
- generic language or framework knowledge.

The bar: would this mistake plausibly happen again, to a future instance of you, in this repo? If not, don't write it.

## Where and how

- About one file: `/git-notes-memory:note <path> "<text>"`.
- Repo-wide or directory-wide: `/git-notes-memory:note learning "<text>"` (appends), with a `Context:` line.

```
<category> | <confidence>     category: gotcha, convention, failure-mode, tooling, architecture; confidence: confirmed, suspected
Context: <file/module/command>   (learnings only; a file note's context is its file)
<1-4 sentences: what you'd tell a competent engineer joining this repo today.>
```

More than 4 sentences belongs in real docs. Examples:

```
/git-notes-memory:note internal/config/config.go "gotcha | confirmed
Editing config.go does not update config_gen.go, and nothing fails loudly if you forget.
Always run `make gen` after touching this file, before running tests."

/git-notes-memory:note learning "convention | confirmed
Context: internal/http/handlers/*
Every handler wraps errors in apperr.Wrap(err, code) before returning. The middleware in
errors.go depends on this to set the HTTP status; raw errors become 500."
```

## Reading and pruning

- Don't go looking: notes are shown when you open a file and at session start. Ones labelled `needs-review`, `UNVERIFIED` or "possibly stale" describe an older version; check them against the code before relying on them.
- **Re-verify:** after editing a file that has a note, or on any `needs-review` note, check it against the code and rewrite it. Don't end a session with unresolved ones.
- **Promote:** if a note is stable and would help a human too, move it into README or an ADR (a comment only under the rules above) and `--delete` it.
- **Delete** a note that no longer applies with `--delete`.
- **Tidy learnings:** print the note, then rewrite it whole with `/git-notes-memory:note learning --force "<full text>"`, keeping every entry you aren't deliberately removing.
- The architecture note is propose-only: on drift, suggest new text to the user; never overwrite it unprompted.
- `/git-notes-memory:note --list` shows every note with its path and status.
