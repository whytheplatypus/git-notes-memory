#!/usr/bin/env bash
# sync.sh [--push]: migrate file notes across commits made since the last
# sync (refs/notes/meta on the root commit), then record HEAD as synced.
# --push merges origin's file-notes, learnings and architecture notes into the
# local ones, then pushes those three refs. refs/notes/meta stays local.
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

# resolve <ref> <obj>: print the merged note for a conflict on <obj>.
# Learnings: local entries, then remote entries not already present.
# Others: the local note, unless only the remote one is current.
resolve() {
	local ours theirs
	ours=$(note_read "$1" "$2")
	theirs=$(note_read "origin/$1" "$2")
	if [ "$1" = "$LEARN_REF" ]; then
		awk 'BEGIN { RS = "" } FILENAME == ARGV[1] { seen[$0] }
			FILENAME == ARGV[1] || !($0 in seen) {
			printf "%s%s", sep, $0; sep = "\n\n" } END { print "" }' \
			<(printf '%s\n' "$ours") <(printf '%s\n' "$theirs")
	elif [ "$(parse_header status <<<"$ours")" = needs-review ] &&
		[ "$(parse_header status <<<"$theirs")" = current ]; then
		printf '%s\n' "$theirs"
	else
		echo "conflict: kept local $1 note on ${2:0:12}" >&2
		printf '%s\n' "$ours"
	fi
}

# merge_ref <ref>: fetch origin's <ref> and 3-way merge it into the local one.
merge_ref() {
	local dir f
	git fetch -q origin "+refs/notes/$1:refs/notes/origin/$1" 2>/dev/null || return 0
	git notes --ref="$1" merge -q -s manual "origin/$1" >/dev/null 2>&1 && return 0
	dir=$(git rev-parse --git-path NOTES_MERGE_WORKTREE)
	[ -d "$dir" ] || { echo "git-notes-memory: merge of $1 failed" >&2; return 1; }
	for f in "$dir"/*; do
		resolve "$1" "${f##*/}" >"$f"
	done
	git notes merge -q --commit
}

if [ "${1:-}" = --push ]; then
	if git remote get-url origin >/dev/null 2>&1; then
		refs=()
		for r in "$FILE_REF" "$LEARN_REF" "$ARCH_REF"; do
			merge_ref "$r" && git rev-parse -q --verify "refs/notes/$r" >/dev/null &&
				refs+=("refs/notes/$r")
		done
		[ ${#refs[@]} -eq 0 ] || git push -q origin "${refs[@]}" ||
			echo "git-notes-memory: push failed" >&2
	else
		echo "git-notes-memory: push skipped (no origin remote)"
	fi
fi
exit 0
