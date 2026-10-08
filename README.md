# git-notes-memory

A Claude Code plugin that keeps project memory in git notes instead of CLAUDE.md.

- **Architecture note**: one note on the repo's root commit (`refs/notes/architecture`), injected at session start, with a drift check. Claude only proposes changes to it.
- **Learnings**: one append-only note on the root commit (`refs/notes/learnings`) for repo-wide and directory-wide learnings, injected at session start. Claude appends to it freely.
- **File notes**: notes on file blob hashes (`refs/notes/file-notes`), injected when Claude reads or edits the file.
- **Bookkeeping**: `refs/notes/meta` holds `last-synced: <sha>` on the root commit.

Why git notes: the memory lives in the repo's own object store and travels with it. Code history stays clean, and each note is tied to the exact content it describes.

The catch: a blob note is pinned to the file's content, so any edit changes the hash and leaves the note behind. The plugin handles that in three ways:

- When Claude edits a file, it copies the note to the new version and marks it `needs-review`. The Stop hook keeps reminding Claude until the note is re-verified.
- At session start, it migrates notes across commits made outside the session (`sync.sh`).
- When Claude reads a file whose current version has no note, it walks `git log --follow` and shows the newest note from an earlier version, labelled "possibly stale".

## Note format

```
status: current | needs-review
verified-at: <HEAD sha when confirmed>
migrated-from: <prior blob sha, optional>
---
<free text>
```

Notes without a header are treated as `status: current`.

## Usage

```
/git-notes-memory:note <path> "text"            file note (--force to overwrite a current one)
/git-notes-memory:note learning "text"          append a repo-wide learning (--force replaces all)
/git-notes-memory:note architecture "text"      architecture note (propose-only for Claude)
/git-notes-memory:note <target>                 show; add --delete to remove
/git-notes-memory:note --list                   every note, with status and path
/git-notes-memory:notes-sync [--push]           migrate notes across new commits
```

## Layout

```
plugin/                     the plugin (source of truth)
  .claude-plugin/plugin.json
  skills/git-notes/         protocol Claude follows (background, not in the / menu)
  skills/note/              /git-notes-memory:note
  skills/notes-sync/        /git-notes-memory:notes-sync
  hooks/hooks.json          SessionStart, PreToolUse, PostToolUse, Stop
  scripts/                  lib.sh plus one script per hook/command
.claude-plugin/marketplace.json   local test marketplace "git-notes-local" (source ./plugin)
tests/run.sh                automated scratch-repo tests
TESTING.md                  manual test guide
```

The build directory itself is the marketplace, and its entry points straight at `plugin/`, so there is no copy to keep in sync.

## Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `GIT_NOTES_MEMORY_SYNC` | unset | Set to `1` to fetch `refs/notes/*` from `origin` at session start and let `/git-notes-memory:notes-sync --push` push them. Unset means local-only: nothing is ever fetched or pushed. |
| `TMPDIR` | `/tmp` | Where the per-session state files (`gnm-<session_id>-*`) are written. |

## Requirements

`bash`, `git`, `jq`. Every script exits 0 silently outside a git repo.

## Design notes

Deviations from the original plan, and why.

- **Not yet validated:** the `claude` CLI wasn't installed on the build machine, so `claude plugin validate` has not run. See `TESTING.md` section 6.
- **Skills instead of commands:** the docs call `commands/` the older format and recommend skills, so `note` and `notes-sync` are skills (`skills/note/`, `skills/notes-sync/`). The slash names are unchanged: `/git-notes-memory:note` and `/git-notes-memory:notes-sync`. Claude can also invoke them itself, e.g. to re-verify a `needs-review` note. Their `allowed-tools` use the `Bash(<path> *)` rule form from the skills docs. The `git-notes` protocol skill sets `user-invocable: false`, so it stays out of the `/` menu.
- **Stop hook** emits `hookSpecificOutput.additionalContext`, which the docs describe as non-error feedback that continues the conversation. It is skipped when `stop_hook_active` is true, per the docs' loop protection.
- **Drift check:** a literal `git diff --stat` over every top-level directory would fire on almost every commit, since most code lives under top-level directories. Drift is therefore defined as top-level directories **added or removed** (from comparing `git ls-tree -d`), plus any diff in `go.mod`, `Cargo.toml`, `package.json` or `pyproject.toml`.
- **`note.sh` overwrite rule:** `--force` is required only when the existing note is `current`. A `needs-review` note can be overwritten freely, because rewriting it is how it gets re-verified. With no text, `note.sh` prints the existing note. Exit code 3 means "exists, needs --force".
- **Learnings ref** (`refs/notes/learnings`, not in the original plan) replaces `.agent/learnings.md`. It is append-only for Claude and kept across amend/rebase via `notes.rewriteRef`. Directory-scoped learnings go here with a `Context:` line, because notes on directory tree objects would break whenever any file in the directory changed.
- **`--list` and `--delete`** were added for pruning. `--list` treats the working-tree version of a modified file as current, and counts notes on older versions instead of listing them.
- **Stop hook reminds once** per batch of edits, then clears its list, so an unresolved note doesn't trigger a reminder on every later turn.
- **Marketplace** lives at the build root with `source: ./plugin`, instead of a copied `marketplace/plugins/` tree.
- **`sync.sh --push`** was added so `/git-notes-memory:notes-sync` can push notes. It only pushes when `GIT_NOTES_MEMORY_SYNC=1` and an `origin` remote exists. Nothing pushes automatically.
- **Migrated notes keep their original `verified-at`.** They are not stamped with the current HEAD, because they haven't been re-verified.
- **Repo resolution:** `pre-tool.sh` and `post-tool.sh` resolve git from the edited file's directory, not the session `cwd`, so a file in a nested or sibling repo uses that repo's notes.
