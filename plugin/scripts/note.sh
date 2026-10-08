#!/usr/bin/env bash
# note.sh <architecture|learning|path> [--force|--delete] [text]
# note.sh --list
#
# architecture, path: with text, write a note (status: current, verified-at:
#   HEAD). Overwriting a current note needs --force; a needs-review note may be
#   overwritten freely, since rewriting one is how it is re-verified.
# learning: with text, append an entry to the repo-wide learnings note;
#   --force replaces the whole note (for pruning).
# Without text: print the note. --delete: remove it. --list: list all notes.
. "$(dirname "$0")/lib.sh"

usage() {
	echo "usage: note.sh <architecture|learning|path> [--force|--delete] [text] | --list" >&2
	exit 2
}

# protect_ref <ref>: carry notes on rewritten commits (amend, rebase).
protect_ref() {
	git config --get-all notes.rewriteRef | grep -qx "refs/notes/$1" ||
		git config --add notes.rewriteRef "refs/notes/$1"
}

# list_notes: root-commit notes, then file notes on the current version of
# each file (working tree if modified, else index); older versions are counted.
list_notes() {
	local root ref
	root=$(root_commit)
	for ref in "$ARCH_REF" "$LEARN_REF"; do
		note_read "$ref" "$root" >/dev/null && printf '%s\t(root commit)\n' "$ref"
	done
	cd "$(git rev-parse --show-toplevel)" || exit 1
	git notes --ref="$FILE_REF" list | cut -d' ' -f2 |
		awk -F'\t' 'NR == FNR { path[$1] = $2; next }
			$1 in path { print $1 "\t" path[$1]; next }
			{ old++ }
			END { if (old) print "-\t" old " note(s) on older file versions" }' \
			<({
				git -c core.quotePath=false ls-files -m | while IFS= read -r p; do
					[ -f "$p" ] && printf '%s\t%s\n' "$(git hash-object -- "$p")" "$p"
				done
				git -c core.quotePath=false ls-files -s | awk -F'\t' '{ split($1, f, " "); print f[2] "\t" $2 }'
			} | awk -F'\t' '!seen[$2]++') - |
		while IFS=$'\t' read -r blob what; do
			[ "$blob" = - ] && { echo "$what"; continue; }
			printf '%s\t%s\n' "$(note_read "$FILE_REF" "$blob" | parse_header status)" "$what"
		done
}

force= delete= list= args=()
for a in "$@"; do
	case $a in
	--force) force=1 ;;
	--delete) delete=1 ;;
	--list) list=1 ;;
	*) args+=("$a") ;;
	esac
done

git rev-parse -q --verify HEAD >/dev/null 2>&1 || { echo "note.sh: not in a git repo with commits" >&2; exit 1; }
[ -n "$list" ] && { list_notes; exit 0; }
[ ${#args[@]} -ge 1 ] || usage
target=${args[0]}
text=${args[*]:1}

case $target in
architecture) ref=$ARCH_REF obj=$(root_commit) ;;
learning) ref=$LEARN_REF obj=$(root_commit) ;;
*)
	[ -f "$target" ] || { echo "note.sh: no such file: $target" >&2; exit 1; }
	ref=$FILE_REF obj=$(git hash-object -w -- "$target")
	;;
esac

existing=$(note_read "$ref" "$obj")
if [ -n "$delete" ]; then
	[ -n "$existing" ] && git notes --ref="$ref" remove "$obj" 2>/dev/null
	echo "removed $ref note for $target"
	exit 0
fi
if [ -z "$text" ]; then
	[ -n "$existing" ] || { echo "no note for $target"; exit 0; }
	printf '%s\n' "$existing"
	exit 0
fi

if [ "$ref" = "$LEARN_REF" ]; then
	if [ -n "$force" ]; then
		printf '%s\n' "$text" | note_put "$ref" "$obj"
	else
		printf '%s\n' "$text" | git notes --ref="$ref" append -F - "$obj"
	fi
	protect_ref "$ref"
	if [ -n "$force" ]; then echo "replaced learnings note"; else echo "appended to learnings note"; fi
	exit 0
fi

if [ -n "$existing" ] && [ -z "$force" ] &&
	[ "$(parse_header status <<<"$existing")" != needs-review ]; then
	echo "A note already exists for $target:"
	printf '%s\n' "$existing"
	echo "Re-run with --force to overwrite." >&2
	exit 3
fi

note_write "$ref" "$obj" current "$text"
[ "$ref" = "$ARCH_REF" ] && protect_ref "$ref"
echo "wrote $ref note on ${obj:0:12} for $target"
