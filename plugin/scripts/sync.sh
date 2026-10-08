#!/usr/bin/env bash
# sync.sh [--push|--trust|--ignore]: migrate file notes across commits made
# since the last sync (refs/notes/meta on the root commit), then record HEAD
# as synced.
# --trust merges origin's file-notes, learnings and architecture notes into
#   the local ones and trusts origin, so each session start merges them too.
# --push does the same, then pushes those three refs. refs/notes/meta stays
#   local.
# --ignore stops session start from fetching origin's notes or asking.
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

case ${1:-} in
--push | --trust)
	url=$(origin_url) || { echo "git-notes-memory: no origin remote"; exit 0; }
	fetch_staged || echo "git-notes-memory: fetch from origin failed" >&2
	changes=$(merge_staged)
	[ -z "$changes" ] || echo "git-notes-memory: merged from origin: $changes"
	if [ "$1" = --trust ]; then
		set_remote trusted && echo "git-notes-memory: trusted origin ($url)"
		exit 0
	fi
	refs=()
	for r in $SYNC_REFS; do
		git rev-parse -q --verify "refs/notes/$r" >/dev/null && refs+=("refs/notes/$r")
	done
	if [ ${#refs[@]} -gt 0 ]; then
		if git push -q origin "${refs[@]}"; then
			set_remote trusted
		else
			echo "git-notes-memory: push failed" >&2
		fi
	fi
	;;
--ignore)
	set_remote ignored && echo "git-notes-memory: ignoring notes from origin ($(origin_url))"
	;;
esac
exit 0
