#!/usr/bin/env bash
# sync.sh [--push]: migrate file notes across commits made since the last
# sync (refs/notes/meta on the root commit), then record HEAD as synced.
# --push sends refs/notes/* to origin, only when GIT_NOTES_MEMORY_SYNC=1.
. "$(dirname "$0")/lib.sh"

in_repo
root=$(root_commit)
head=$(git rev-parse HEAD)
last=$(note_read "$META_REF" "$root" | sed -n 's/^last-synced: *//p')

mark_synced() {
	echo "last-synced: $head" | note_put "$META_REF" "$root"
}

if [ -z "$last" ] || ! git cat-file -e "$last^{commit}" 2>/dev/null; then
	mark_synced
elif [ "$last" != "$head" ]; then
	# --raw gives old/new blob shas; renames with R100 keep the same blob.
	while IFS=$'\t' read -r meta p1 p2; do
		set -- $meta
		old=$3 new=$4
		case $5 in M* | R*)
			note_migrate "$old" "$new" && echo "needs-review: ${p2:-$p1}"
			;;
		esac
	done < <(git diff --raw --no-abbrev -M "$last" "$head")
	mark_synced
fi

if [ "${1:-}" = --push ]; then
	if [ "${GIT_NOTES_MEMORY_SYNC:-}" = 1 ] && git remote get-url origin >/dev/null 2>&1; then
		git push -q origin 'refs/notes/*:refs/notes/*' || echo "git-notes-memory: push failed" >&2
	else
		echo "git-notes-memory: push skipped (set GIT_NOTES_MEMORY_SYNC=1 and add an origin remote)"
	fi
fi
exit 0
