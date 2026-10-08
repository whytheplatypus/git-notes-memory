#!/usr/bin/env bash
# SessionStart: optionally fetch notes, sync file notes across new commits,
# and inject the learnings and architecture notes with a drift check.
. "$(dirname "$0")/lib.sh"

hook_input
in_repo

if [ "${GIT_NOTES_MEMORY_SYNC:-}" = 1 ] && git remote get-url origin >/dev/null 2>&1; then
	git fetch -q origin 'refs/notes/*:refs/notes/*' >/dev/null 2>&1
fi

ctx= nl=$'\n'
add() { ctx="${ctx:+$ctx$nl$nl}$1"; }

synced=$("$(dirname "$0")/sync.sh")
[ -n "$synced" ] && add "git-notes-memory: commits since the last session changed files with notes; re-verify these when you touch them:
$synced"

root=$(root_commit)
if note=$(note_read "$LEARN_REF" "$root"); then
	add "git-notes-memory: repo learnings (root commit ${root:0:12}):
$(note_body <<<"$note")"
fi

if note=$(note_read "$ARCH_REF" "$root"); then
	verified=$(parse_header verified-at <<<"$note")
	add "git-notes-memory: architecture note (root commit ${root:0:12}, verified-at ${verified:0:12}):
$(note_body <<<"$note")"
	if [ -n "$verified" ] && git merge-base --is-ancestor "$verified" HEAD 2>/dev/null; then
		# Drift = top-level directories added/removed, or manifest changes.
		dirs=$(diff <(git ls-tree -d --name-only "$verified") <(git ls-tree -d --name-only HEAD) |
			sed -n 's/^< /removed dir: /p; s/^> /added dir: /p')
		stat=$(git diff --stat "$verified" HEAD -- go.mod Cargo.toml package.json pyproject.toml)
		drift=$(printf '%s\n%s' "$dirs" "$stat" | sed '/^$/d')
		[ -n "$drift" ] && add "ARCHITECTURE DRIFT since verified-at ${verified:0:12}:
$drift
Propose an update to the user; never overwrite the architecture note unprompted."
	else
		add "STALE: verified-at ${verified:-<missing>} is not reachable from HEAD (history rewritten?). Treat this note as unverified and propose re-verifying it."
	fi
fi

[ -n "$ctx" ] && emit_context SessionStart "$ctx"
exit 0
