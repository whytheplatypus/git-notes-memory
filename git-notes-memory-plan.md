# Plan: `git-notes-memory` — a Claude Code plugin

**Usage:** `execute this plan git-notes-memory-plan.md`

## Instructions to the executing agent
- Build everything under `./git-notes-memory-build/` (create it in the current directory). Do not touch `~/.claude`, global settings, or any existing repo.
- Work through the phases in order. After each phase run its **Verify** step; fix failures before moving on.
- Before writing hook code, read https://code.claude.com/docs/en/hooks and confirm the exact stdin fields and output JSON for `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`. Where this plan and the docs disagree, follow the docs and note the deviation in `TESTING.md`.
- Also confirm plugin layout against https://code.claude.com/docs/en/plugins/components and marketplace format against https://code.claude.com/docs/en/plugin-marketplaces.
- Requirements: `bash`, `git`, `jq`. Check at start; stop and report if missing.
- Never push or fetch notes unless `GIT_NOTES_MEMORY_SYNC=1` is set. Default is local-only.
- Last step is mandatory: print the contents of `TESTING.md` to the user (Phase 7).

## Goal
Persistent, git-native project memory for Claude Code, replacing CLAUDE.md for decision/architecture knowledge:
- **Architecture note** on the repo's root commit (`refs/notes/architecture`)
- **File notes** on blob hashes (`refs/notes/file-notes`)
- **Bookkeeping** in `refs/notes/meta` (`last-synced` sha)

Blob notes are content-pinned: any edit changes the hash and orphans the note. The plugin therefore resolves with fallback and migrates notes on change.

## Plugin layout
```
git-notes-memory-build/
├── plugin/
│   ├── .claude-plugin/plugin.json
│   ├── skills/git-notes/SKILL.md
│   ├── commands/note.md
│   ├── commands/notes-sync.md
│   ├── hooks/hooks.json
│   └── scripts/
│       ├── lib.sh            # shared: root commit, header parse/write, in-repo check
│       ├── session-start.sh  # architecture inject + drift check + optional fetch
│       ├── pre-tool.sh       # file-note inject + record pre-edit blob hash
│       ├── post-tool.sh      # migrate note to new blob (needs-review)
│       ├── stop.sh           # list unresolved needs-review notes
│       ├── note.sh           # writer (architecture | <path>)
│       └── sync.sh           # /notes-sync: diff last-synced..HEAD, migrate, update meta
├── marketplace/
│   └── .claude-plugin/marketplace.json   # local test marketplace; plugin copied/symlinked under plugins/
├── tests/run.sh               # automated scratch-repo test suite
├── TESTING.md                 # manual test guide (Phase 6)
└── README.md
```
Name: plugin `git-notes-memory`; marketplace `git-notes-local`. Entry `name` must equal manifest `name`. Commands appear as `/git-notes-memory:note` and `/git-notes-memory:notes-sync`.

## Note format
```
status: current | needs-review
verified-at: <HEAD sha when confirmed>
migrated-from: <prior blob sha, optional>
---
<free text>
```
`lib.sh` provides `note_read <ref> <obj>`, `note_write <ref> <obj> <status> <text>`, `parse_header`. Notes lacking a header are treated as `status: current`.

## Phases

### Phase 1 — Scaffold + manifest
Create layout above. `plugin.json`: name, version `0.1.0`, description. Scripts `chmod +x`.
**Verify:** `claude plugin validate ./plugin` passes (if the `claude` CLI is absent, skip and say so).

### Phase 2 — Core library + resolver
`lib.sh`:
- `in_repo`: `git rev-parse --git-dir` else exit 0 silently (every script must no-op outside git).
- `root_commit`: `git rev-list --max-parents=0 HEAD`; if multiple, oldest by commit date.
- Header parse/write per format above.
`pre-tool.sh` (matcher `Read|Edit|Write`):
1. Read stdin JSON; get `tool_input.file_path`; no-op if missing, outside repo, or file doesn't exist.
2. `h=$(git hash-object <path>)`; look up `file-notes` at `h`.
3. Miss → walk `git log --follow --format=%H -- <path>`, for each commit get blob via `git rev-parse <sha>:<path>`, first hit wins; label "from earlier version <sha>, possibly stale".
4. Emit `additionalContext`; label `needs-review` notes "UNVERIFIED — file changed since written".
5. If tool is `Edit|Write`: save `h` to `${TMPDIR:-/tmp}/gnm-<session_id>-<sha1(path)>`.
**Verify:** unit cases in `tests/run.sh` (Phase 6).

### Phase 3 — Writer + hooks
`note.sh <architecture|path> <text>`: sets `status: current`, `verified-at: HEAD`; if a note exists, print it and require `--force` to overwrite. `commands/note.md` invokes it via Bash with `allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/note.sh:*)`; instruct Claude to confirm overwrite with the user.
`hooks/hooks.json` (scripts referenced as `"${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"`):
- `SessionStart` → `session-start.sh`
- `PreToolUse` `Read|Edit|Write` → `pre-tool.sh`
- `PostToolUse` `Edit|Write` → `post-tool.sh`
- `Stop` → `stop.sh` (must honor `stop_hook_active` to avoid loops)
`session-start.sh`: inject architecture note; run `sync.sh`; if `GIT_NOTES_MEMORY_SYNC=1` and a remote exists, best-effort `git fetch origin 'refs/notes/*:refs/notes/*'` (ignore failure).
**Verify:** hooks.json valid JSON; each script exits 0 with empty/valid JSON output when run outside a repo.

### Phase 4 — Migration and drift
- **A. In-session edit** (`post-tool.sh`): read saved old hash; compute new hash; if different and old has a note → copy to new hash with `status: needs-review`, `migrated-from: <old>`; keep old note; inject reminder to re-verify via `/git-notes-memory:note`.
- **B. External change** (`sync.sh`): read `last-synced` from `refs/notes/meta` (on root commit); `git diff --name-status -M <last-synced> HEAD`; for modified/renamed-with-change, copy note old blob → new blob as `needs-review`; pure renames need nothing; deleted → leave. Update `last-synced`. If no `last-synced`, set to HEAD and exit.
- **C. History rewrite / drift:** set `notes.rewriteRef=refs/notes/architecture` in the repo when the architecture note is first written. At session start, if the architecture note's `verified-at` is reachable, run `git diff --stat <verified-at> HEAD -- <top-level dirs, go.mod, Cargo.toml, package.json, pyproject.toml>`; if non-empty inject a drift summary and say Claude must *propose* an update, never overwrite unprompted. If `verified-at` is unreachable, flag it as stale.
- **D. Stop hook:** list notes with `status: needs-review` touched this session (track in a session temp file) and remind Claude to resolve them.
**Verify:** covered by Phase 6 tests T5–T9.

### Phase 5 — Skill + marketplace
`skills/git-notes/SKILL.md`: precise description ("use in a git repo with architecture/file-notes refs, or when asked to record/recall project decisions"), then the protocol: refs, blob-pinning caveat, how to write via `/git-notes-memory:note`, the rule "after editing a file with a note, or on `needs-review`, re-verify and update; do not end a session with unresolved `needs-review` notes", architecture is propose-only. Keep it short; the description is in context every turn.
`marketplace.json`: `name: git-notes-local`, `owner`, one plugin entry `source: ./plugins/git-notes-memory`. Copy `plugin/` to `marketplace/plugins/git-notes-memory/` via a `make-marketplace.sh` helper so there is one source of truth.
**Verify:** `claude plugin validate ./marketplace` passes (if CLI present).

### Phase 6 — Tests and testing guide
`tests/run.sh` creates a temp repo (`mktemp -d`), runs scripts directly by piping fake hook JSON to stdin, and asserts. Cases:
- T1 outside a repo: all scripts exit 0, no output
- T2 write + read architecture note on root commit
- T3 file note write + read at current blob
- T4 no note → silent
- T5 edit file → post-tool migrates note, `needs-review`, `migrated-from` set, old note intact
- T6 pure rename → note still resolves
- T7 external commit changing a file → `sync.sh` migrates
- T8 miss at current blob → `--follow` fallback finds earlier note with stale label
- T9 amend/rebase root-keyed architecture note survives (rewriteRef)
- T10 drift: change `go.mod`/top-level dirs after verification → drift message
- T11 notes survive `git gc`
- T12 sync disabled by default: no fetch/push attempted
Print PASS/FAIL per case; exit non-zero on any failure. Iterate until all pass.

`TESTING.md` must contain, in this order:
1. **Automated:** `bash tests/run.sh` and expected output.
2. **Make a scratch repo:** `git init ~/tmp/gnm-poc`, a few commits, a Go or text file.
3. **Load without installing (fastest loop):** `cd ~/tmp/gnm-poc && claude --plugin-dir <abs path>/plugin`; `/reload-plugins` after edits.
4. **Try it:** `/git-notes-memory:note architecture "…"`, `/git-notes-memory:note <file> "…"`; start a new session and confirm the architecture note appears; ask Claude to read the file and confirm the file note appears; ask Claude to edit it and confirm a `needs-review` reminder; check with `git notes --ref=file-notes list`.
5. **Debugging:** how to see hook output (`claude --debug`), how to inspect `git notes --ref=<ref> show <hash>`, temp state location.
6. **Desktop app (local marketplace):** `claude plugin validate ./marketplace`; `claude plugin marketplace add <abs>/marketplace`; in the desktop Code tab local session: **+ → Plugins → Add plugin**, choose `git-notes-memory`, scope **local (this repo only)**; later **+ → Plugins → Manage plugins**. Note: cloud sessions don't load local plugins.
7. **Teardown:** `claude plugin uninstall git-notes-memory@git-notes-local`, `claude plugin marketplace remove git-notes-local`, delete scratch repo.
8. **Before promoting:** push marketplace to GitHub (`claude plugin marketplace add owner/repo`); enable `GIT_NOTES_MEMORY_SYNC=1` only in a throwaway remote first.
Use absolute paths in `TESTING.md` (resolve at build time).

### Phase 7 — Finish
- Run `tests/run.sh` one last time; run both `validate` commands if the CLI exists.
- Write `README.md` (what/why, layout, env vars: `GIT_NOTES_MEMORY_SYNC`).
- **Print `TESTING.md` in full to the user**, plus a summary: what passed, what was skipped (e.g. no `claude` CLI), and any deviations from the docs.

## Out of scope
Publishing to a public marketplace, global `~/.claude` edits, auto-pushing notes, auto-rewriting the architecture note.
