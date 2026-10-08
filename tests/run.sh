#!/usr/bin/env bash
# Automated tests for git-notes-memory: run hook scripts against scratch repos
# by piping fake hook JSON to stdin.
set -u
S=$(cd "$(dirname "$0")/../plugin/scripts" && pwd)
WORK=$(mktemp -d)
export TMPDIR=$WORK/tmp GIT_CONFIG_GLOBAL=$WORK/gitconfig GIT_CONFIG_NOSYSTEM=1
mkdir -p "$TMPDIR"
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; fails=$((fails + 1)); }
check() { # check <name> <description> <command...>
	local name=$1 what=$2
	shift 2
	if "$@"; then pass "$name"; else fail "$name" "$what"; fi
}

hook() { # hook <script> <tool> <path> [session]
	jq -n --arg cwd "$PWD" --arg t "$2" --arg p "$3" --arg s "${4:-sess}" \
		'{session_id: $s, cwd: $cwd, tool_name: $t, tool_input: {file_path: $p}}' |
		"$S/$1.sh"
}
start() { jq -n --arg cwd "$PWD" '{session_id: "sess", cwd: $cwd}' | "$S/session-start.sh"; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty'; }
commit() { git add -A && git commit -qm "$1"; }
fnote() { git notes --ref=file-notes show "$1" 2>/dev/null; }
contains() { grep -qF -- "$2" <<<"$1"; }

new_repo() {
	R=$(mktemp -d "$WORK/repo.XXXX")
	cd "$R" && git init -q
	mkdir src && echo 'package main' >src/main.go && echo 'module x' >go.mod
	commit init
}

# T1 outside a repo: all scripts exit 0, no output
cd "$(mktemp -d "$WORK/norepo.XXXX")"
echo hi >f
out= rc=0
for s in session-start pre-tool post-tool stop; do
	out+=$(hook "$s" Edit "$PWD/f") || rc=1
done
out+=$("$S/sync.sh") || rc=1
check T1 "rc=$rc out=[$out]" test "$rc$out" = 0

# T2 write + read architecture note on root commit
new_repo
echo 'more' >>src/main.go && commit second
"$S/note.sh" architecture "Layered: cmd -> svc -> store" >/dev/null
root=$(git rev-list --max-parents=0 HEAD)
out=$(start | ctx)
check T2 "arch note missing at session start: [$out]" \
	contains "$(git notes --ref=architecture show "$root")$out" "Layered: cmd -> svc -> store"

# T3 file note write + read at current blob
"$S/note.sh" src/main.go "Entry point; keep flag parsing here" >/dev/null
out=$(hook pre-tool Read "$R/src/main.go" | ctx)
check T3 "file note not injected: [$out]" contains "$out" "keep flag parsing here"

# T4 no note → silent
out=$(hook pre-tool Read "$R/go.mod")
check T4 "expected no output: [$out]" test -z "$out"

# T5 edit file → post-tool migrates note, needs-review, migrated-from, old intact
old=$(git hash-object src/main.go)
hook pre-tool Edit "$R/src/main.go" >/dev/null
echo '// edited' >>src/main.go
out=$(hook post-tool Edit "$R/src/main.go" | ctx)
new=$(git hash-object src/main.go)
n=$(fnote "$new")
check T5 "migration wrong: new=[$n] ctx=[$out]" eval '
	contains "$n" "status: needs-review" && contains "$n" "migrated-from: $old" &&
	contains "$n" "keep flag parsing here" && contains "$(fnote "$old")" "status: current" &&
	contains "$out" "needs-review"'
# Stop hook reminds, and honors stop_hook_active.
out=$(jq -n --arg cwd "$PWD" '{session_id: "sess", cwd: $cwd, stop_hook_active: false}' | "$S/stop.sh" | ctx)
out2=$(jq -n --arg cwd "$PWD" '{session_id: "sess", cwd: $cwd, stop_hook_active: true}' | "$S/stop.sh")
check T5-stop "stop=[$out] active=[$out2]" eval 'contains "$out" "src/main.go" && test -z "$out2"'
out=$(jq -n --arg cwd "$PWD" '{session_id: "sess", cwd: $cwd}' | "$S/stop.sh")
check T5-once "stop should remind only once: [$out]" test -z "$out"
"$S/note.sh" src/main.go "Entry point; re-verified" >/dev/null
commit edit

# Stop hook judges the file's current version: an edit outside Edit/Write
# that gets re-verified clears the reminder; one that leaves the note behind
# still reminds.
hook pre-tool Edit "$R/src/main.go" >/dev/null
echo '// edit' >>src/main.go
hook post-tool Edit "$R/src/main.go" >/dev/null
echo '// bash edit' >>src/main.go
"$S/note.sh" src/main.go "Entry point; re-verified after bash edit" >/dev/null
out=$(jq -n --arg cwd "$PWD" '{session_id: "sess", cwd: $cwd}' | "$S/stop.sh")
hook pre-tool Edit "$R/src/main.go" >/dev/null
echo '// edit 2' >>src/main.go
hook post-tool Edit "$R/src/main.go" >/dev/null
echo '// bash edit 2' >>src/main.go
out2=$(jq -n --arg cwd "$PWD" '{session_id: "sess", cwd: $cwd}' | "$S/stop.sh" | ctx)
check T5-current "stop: re-verified=[$out] left-behind=[$out2]" eval '
	test -z "$out" && contains "$out2" "src/main.go"'
"$S/note.sh" src/main.go "Entry point; re-verified" >/dev/null
commit edit2

# T6 pure rename → note still resolves
git mv src/main.go src/app.go && commit rename
out=$(hook pre-tool Read "$R/src/app.go" | ctx)
check T6 "rename lost note: [$out]" contains "$out" "re-verified"

# T7 external commit changing a file → sync.sh migrates
start >/dev/null # record last-synced
echo '// external' >>src/app.go && commit external
"$S/sync.sh" >/dev/null
n=$(fnote "$(git hash-object src/app.go)")
check T7 "sync did not migrate: [$n]" eval 'contains "$n" "status: needs-review" && contains "$n" "re-verified"'

# T8 miss at current blob → --follow fallback finds earlier note, stale label
new_repo
seq 1 20 >>src/main.go && commit grow # big enough for rename detection
"$S/note.sh" src/main.go "Original rationale" >/dev/null
git mv src/main.go src/old.go && echo '// x' >>src/old.go && commit "rename+edit"
out=$(hook pre-tool Read "$R/src/old.go" | ctx)
check T8 "fallback missing: [$out]" eval 'contains "$out" "Original rationale" && contains "$out" "possibly stale"'

# T9 amend/rebase: root-keyed architecture note survives (rewriteRef)
new_repo
"$S/note.sh" architecture "Survives amend" >/dev/null
git commit -q --amend -m "init amended"
root=$(git rev-list --max-parents=0 HEAD)
echo y >y && commit second && git rebase -q --root --force-rebase
root2=$(git rev-list --max-parents=0 HEAD)
check T9 "note lost after amend/rebase" eval '
	contains "$(git notes --ref=architecture show "$root")" "Survives amend" &&
	contains "$(git notes --ref=architecture show "$root2")" "Survives amend"'
out=$(start | ctx)
check T9-stale "rewritten verified-at should be flagged: [$out]" contains "$out" "STALE"

# T10 drift: change go.mod / top-level dirs after verification → drift message
new_repo
"$S/note.sh" architecture "Arch" >/dev/null
out=$(start | ctx)
check T10-clean "unexpected drift: [$out]" eval '! contains "$out" "DRIFT"'
echo 'require y v1' >>go.mod && mkdir web && echo x >web/i.html && commit drift
out=$(start | ctx)
check T10 "drift not reported: [$out]" eval '
	contains "$out" "ARCHITECTURE DRIFT" && contains "$out" "go.mod" &&
	contains "$out" "added dir: web" && contains "$out" "never overwrite"'

# T11 notes survive git gc (including notes on uncommitted blobs)
echo 'draft' >draft.txt
"$S/note.sh" draft.txt "Uncommitted draft" >/dev/null
h=$(git hash-object draft.txt)
rm draft.txt
git gc -q --prune=now 2>/dev/null
check T11 "notes lost after gc" eval '
	contains "$(fnote "$h")" "Uncommitted draft" &&
	contains "$(git notes --ref=architecture show "$(git rev-list --max-parents=0 HEAD)")" "Arch"'

# T12 session start only stages remote notes; --push pushes our refs, not
# meta, and trusts origin
remote=$(mktemp -d "$WORK/remote.XXXX")
git init -q --bare "$remote"
git remote add origin "$remote" && git push -q origin HEAD 2>/dev/null
git --git-dir="$remote" notes --ref=remoteonly add -m "remote only" HEAD
out=$(start)
check T12 "remote notes leaked into local refs: [$out]" eval '
	test -z "$(git for-each-ref refs/notes/remoteonly)" &&
	test -n "$(git for-each-ref refs/notes/origin/remoteonly)" && ! contains "$out" "--trust"'
"$S/sync.sh" --push >/dev/null
check T12-push "push should send file-notes and architecture, not meta, and trust origin" eval '
	test -n "$(git --git-dir="$remote" for-each-ref refs/notes/file-notes)" &&
	test -n "$(git --git-dir="$remote" for-each-ref refs/notes/architecture)" &&
	test -z "$(git --git-dir="$remote" for-each-ref refs/notes/meta)" &&
	test "$(git config gitnotesmemory.trustedRemote)" = "$remote"'

# T12-merge diverged clones: learnings union, file-note conflict keeps local
clone=$(mktemp -d "$WORK/clone.XXXX")
git clone -q "$remote" "$clone" && git -C "$clone" fetch -q origin 'refs/notes/*:refs/notes/*'
"$S/note.sh" learning "shared entry" >/dev/null
"$S/sync.sh" --push >/dev/null
(cd "$clone" && "$S/note.sh" learning "clone entry" >/dev/null &&
	"$S/note.sh" go.mod "clone go.mod note" >/dev/null && "$S/sync.sh" --push >/dev/null)
"$S/note.sh" learning "local entry" >/dev/null
"$S/note.sh" go.mod "local go.mod note" >/dev/null
out=$("$S/sync.sh" --push 2>&1)
l=$("$S/note.sh" learning)
check T12-merge "merge wrong: out=[$out] learnings=[$l]" eval '
	test "$(grep -c "shared entry" <<<"$l")" = 1 && contains "$l" "clone entry" &&
	contains "$l" "local entry" && contains "$out" "conflict: kept local file-notes" &&
	contains "$(fnote "$(git hash-object go.mod)")" "local go.mod note" &&
	test "$(git rev-parse refs/notes/learnings)" = "$(git --git-dir="$remote" rev-parse refs/notes/learnings)"'

# T13 learnings: append, inject at session start, survive amend, --force replaces
new_repo
"$S/note.sh" learning "convention: wrap errors" >/dev/null
"$S/note.sh" learning "gotcha: run make gen" >/dev/null
git commit -q --amend -m "init amended"
out=$(start | ctx)
check T13 "learnings not appended/injected after amend: [$out]" eval '
	contains "$out" "repo learnings" && contains "$out" "wrap errors" && contains "$out" "make gen"'
"$S/note.sh" learning --force "gotcha: run make gen" >/dev/null
out=$("$S/note.sh" learning)
check T13-replace "--force should replace: [$out]" eval '! contains "$out" "wrap errors" && contains "$out" "make gen"'

# T14 --list: notes by path and status; older versions counted
"$S/note.sh" go.mod "Pinned module path" >/dev/null
"$S/note.sh" src/main.go "Entry" >/dev/null
hook pre-tool Edit "$R/src/main.go" >/dev/null
echo '// e' >>src/main.go
hook post-tool Edit "$R/src/main.go" >/dev/null
out=$("$S/note.sh" --list)
check T14 "list wrong: [$out]" eval '
	contains "$out" "learnings	(root commit)" && contains "$out" "current	go.mod" &&
	contains "$out" "needs-review	src/main.go" && contains "$out" "1 note(s) on older file versions"'

# T15 --delete removes a file note
"$S/note.sh" go.mod --delete >/dev/null
check T15 "note not deleted" test -z "$(fnote "$(git hash-object go.mod)")"

# T16 Bash: notes for files named in the command, once per session
new_repo
"$S/note.sh" src/main.go "Bash-visible note" >/dev/null
bash_hook() { # bash_hook <command> [session]
	jq -n --arg cwd "$PWD" --arg c "$1" --arg s "${2:-bsess}" \
		'{session_id: $s, cwd: $cwd, tool_name: "Bash", tool_input: {command: $c}}' |
		"$S/pre-tool.sh"
}
out=$(bash_hook "sed -n 1,5p 'src/main.go' | head" | ctx)
check T16 "bash note missing: [$out]" contains "$out" "Bash-visible note"
out=$(bash_hook "cat src/main.go")
check T16-once "bash note repeated: [$out]" test -z "$out"
out=$(hook pre-tool Read "$R/src/main.go" bsess | ctx)
check T16-read "Read should still show the note: [$out]" contains "$out" "Bash-visible note"
out=$(bash_hook "ls -la; echo hi" other)
check T16-none "expected no output: [$out]" test -z "$out"

# T17 NotebookEdit: notebook_path is used, and the note migrates
echo '{}' >nb.ipynb && commit nb
"$S/note.sh" nb.ipynb "Notebook note" >/dev/null
nb_hook() {
	jq -n --arg cwd "$PWD" --arg p "$R/nb.ipynb" \
		'{session_id: "sess", cwd: $cwd, tool_name: "NotebookEdit", tool_input: {notebook_path: $p}}' |
		"$S/$1.sh"
}
out=$(nb_hook pre-tool | ctx)
echo '{"cells": []}' >nb.ipynb
out2=$(nb_hook post-tool | ctx)
check T17 "notebook: pre=[$out] post=[$out2]" eval '
	contains "$out" "Notebook note" && contains "$out2" "needs-review"'

# T18 fresh clone: notes staged and the user asked; --trust merges; later
# sessions merge and announce; --ignore stops fetching
sysmsg() { jq -r '.systemMessage // empty'; }
new_repo
origin_repo=$R remote=$(mktemp -d "$WORK/remote.XXXX")
git init -q --bare "$remote"
"$S/note.sh" learning "origin entry" >/dev/null
git remote add origin "$remote" && git push -q origin HEAD 2>/dev/null && "$S/sync.sh" --push >/dev/null
fresh=$(mktemp -d "$WORK/fresh.XXXX")
git clone -q "$remote" "$fresh" && cd "$fresh"
out=$(start)
check T18 "untrusted origin should ask, not load: [$out]" eval '
	contains "$(sysmsg <<<"$out")" "1 learnings entries" &&
	contains "$(sysmsg <<<"$out")" "notes-sync --trust" &&
	contains "$(ctx <<<"$out")" "not loaded" && ! contains "$out" "origin entry" &&
	test -z "$(git for-each-ref refs/notes/learnings)"'
"$S/sync.sh" --trust >/dev/null
check T18-trust "--trust should merge and trust" eval '
	contains "$("$S/note.sh" learning)" "origin entry" &&
	test "$(git config gitnotesmemory.trustedRemote)" = "$remote"'
(cd "$origin_repo" && "$S/note.sh" learning "second entry" >/dev/null && "$S/sync.sh" --push >/dev/null)
out=$(start)
check T18-merge "trusted session start should merge and announce: [$out]" eval '
	contains "$(sysmsg <<<"$out")" "merged notes from origin" &&
	contains "$(sysmsg <<<"$out")" "+1 learnings entries" &&
	contains "$(ctx <<<"$out")" "just merged from origin (written on another clone" &&
	contains "$(ctx <<<"$out")" "second entry"'
"$S/sync.sh" --ignore >/dev/null
(cd "$origin_repo" && "$S/note.sh" learning "third entry" >/dev/null && "$S/sync.sh" --push >/dev/null)
out=$(start)
check T18-ignore "--ignore should stop fetching: [$out]" eval '
	test -z "$(sysmsg <<<"$out")" && ! contains "$out" "third entry" &&
	! contains "$(git notes --ref=origin/learnings show "$(git rev-list --max-parents=0 HEAD)")" "third entry"'

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; fi
exit "$((fails > 0))"
