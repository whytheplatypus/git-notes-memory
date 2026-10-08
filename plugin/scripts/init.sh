#!/usr/bin/env bash
# init.sh: protect the root-commit notes across amend and rebase, then print
# what the repo already has, for the init skill to build on.
. "$(dirname "$0")/lib.sh"

git rev-parse -q --verify HEAD >/dev/null 2>&1 || { echo "init.sh: not in a git repo with commits" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)" || exit 1
protect_ref "$ARCH_REF"
protect_ref "$LEARN_REF"

read -r learnings files < <(note_counts)
if note_read "$ARCH_REF" "$(root_commit)" >/dev/null; then arch=present; else arch=missing; fi
echo "architecture note: $arch"
echo "learnings entries: $learnings"
echo "file notes: $files"
for f in .agent/learnings.md CLAUDE.md .claude/CLAUDE.md; do
	[ -f "$f" ] && echo "found: $f"
done
if state=$(remote_state); then
	echo "origin: $state ($(origin_url))"
	[ "$state" = unknown ] && staged=$(staged_summary) && [ -n "$staged" ] &&
		echo "origin has staged notes: $staged"
else
	echo "origin: none"
fi
echo "notes.rewriteRef: set for architecture and learnings"
