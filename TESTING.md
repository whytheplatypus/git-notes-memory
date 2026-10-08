# Testing git-notes-memory

Repo: `/home/whytheplatypus/Development/git-notes-memory`

## 1. Automated

```bash
bash /home/whytheplatypus/Development/git-notes-memory/tests/run.sh
```

Expected output: `PASS` for T1–T15 plus the sub-checks T5-stop, T5-once, T9-stale, T10-clean, T12-enabled and T13-replace, then `ALL PASS`. The script exits non-zero if any check fails. Each run uses throwaway repos in a `mktemp -d` directory with its own git config, and deletes them afterwards.

## 2. Make a scratch repo

```bash
git init ~/tmp/gnm-poc && cd ~/tmp/gnm-poc
printf 'module example.com/poc\n\ngo 1.22\n' > go.mod
mkdir -p cmd && printf 'package main\n\nfunc main() {}\n' > cmd/main.go
git add -A && git commit -m init
echo '# poc' > README.md && git add -A && git commit -m readme
```

## 3. Load without installing (fastest loop)

```bash
cd ~/tmp/gnm-poc && claude --plugin-dir /home/whytheplatypus/Development/git-notes-memory/plugin
```

After editing anything in `/home/whytheplatypus/Development/git-notes-memory/plugin`, run `/reload-plugins` in the session.

## 4. Try it

1. `/git-notes-memory:note architecture "Single Go binary; cmd/ holds entry points only"`
2. `/git-notes-memory:note cmd/main.go "Keep main thin: flag parsing and wiring only"`
3. Start a new session (`/clear` or restart). The architecture note should appear in the session-start context.
4. Ask Claude to read `cmd/main.go`. The file note should appear, labelled `status: current`.
5. Ask Claude to edit `cmd/main.go`. You should get a `needs-review` reminder after the edit. When Claude tries to finish, the Stop hook should also remind it until it re-verifies the note with `/git-notes-memory:note`.
6. Inspect the notes:
   ```bash
   git notes --ref=file-notes list
   ```
7. `/git-notes-memory:note learning "gotcha | Context: cmd/: build with -trimpath"`. Start a new session; the learnings note should appear. Then run `/git-notes-memory:note --list`.
8. Drift: add a top-level directory or change `go.mod`, commit, then start a new session. Claude should get an ARCHITECTURE DRIFT notice and should only *propose* an update.

## 5. Debugging

- Hook execution and output: run `claude --debug`, or turn on debug in-session. A `PostToolUse` hook that exits 0 shows nothing in the transcript.
- Run a hook by hand:
  ```bash
  echo '{"session_id":"dbg","cwd":"'$PWD'","tool_name":"Read","tool_input":{"file_path":"'$PWD'/cmd/main.go"}}' | /home/whytheplatypus/Development/git-notes-memory/plugin/scripts/pre-tool.sh
  ```
- Inspect a note:
  ```bash
  git notes --ref=file-notes show $(git hash-object cmd/main.go)
  ```
  The architecture note: `git notes --ref=architecture show $(git rev-list --max-parents=0 HEAD)`. Bookkeeping: `git notes --ref=meta show $(git rev-list --max-parents=0 HEAD)`.
- Temp state: `${TMPDIR:-/tmp}/gnm-<session_id>-<hash of path>` holds the blob hash before an edit. `${TMPDIR:-/tmp}/gnm-<session_id>-touched` lists the notes migrated this session, which the Stop hook checks.

## 6. Desktop app (local marketplace)

```bash
claude plugin validate /home/whytheplatypus/Development/git-notes-memory
```

```bash
claude plugin marketplace add /home/whytheplatypus/Development/git-notes-memory
```

In the desktop Code tab, in a **local** session on the scratch repo: **+ → Plugins → Add plugin**, choose `git-notes-memory`, scope **local (this repo only)**. Manage it later under **+ → Plugins → Manage plugins**.

Cloud sessions don't load local plugins.

## 7. Teardown

```bash
claude plugin uninstall git-notes-memory@git-notes-local
```

```bash
claude plugin marketplace remove git-notes-local
```

```bash
rm -rf ~/tmp/gnm-poc
```

## 8. Before promoting

- Push this repo to GitHub, then register it with `claude plugin marketplace add owner/repo`.
- Turn on `GIT_NOTES_MEMORY_SYNC=1` against a throwaway remote first. Fetching uses non-forced `refs/notes/*:refs/notes/*`, so diverged notes refs fail to update instead of being overwritten.

## Design notes

Deviations from the original plan are listed in `README.md` under "Design notes".
