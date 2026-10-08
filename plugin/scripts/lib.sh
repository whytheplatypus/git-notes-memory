# lib.sh — shared helpers for git-notes-memory. Source, don't execute.
#
# Note format:
#   status: current | needs-review
#   verified-at: <sha>
#   migrated-from: <blob sha>      (optional)
#   ---
#   <free text>
# Notes without a header are treated as status: current.

ARCH_REF=architecture
LEARN_REF=learnings
FILE_REF=file-notes
META_REF=meta

# in_repo: exit 0 silently unless cwd is inside a git work tree with commits.
in_repo() {
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
	git rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 0
}

# hook_input: read hook JSON from stdin into $INPUT and cd to its cwd.
hook_input() {
	INPUT=$(cat)
	local dir
	dir=$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)
	[ -n "$dir" ] && cd "$dir" 2>/dev/null
	return 0
}

# enter_file_repo <abs path>: cd to the top of the file's repo; set $REL to its
# repo-relative path. Exits 0 silently if the file is missing or outside git.
enter_file_repo() {
	[ -n "$1" ] && [ -f "$1" ] || exit 0
	cd "$(dirname "$1")" 2>/dev/null || exit 0
	in_repo
	local dir top
	dir=$(pwd -P)
	top=$(git rev-parse --show-toplevel)
	REL=${dir#"$top"}
	REL=${REL#/}${REL:+/}$(basename "$1")
	cd "$top" || exit 0
}

# field <jq path>: read a value from $INPUT.
field() {
	jq -r "$1 // empty" <<<"$INPUT" 2>/dev/null
}

# root_commit: the repo's root commit; the oldest by commit date if several.
root_commit() {
	git log --max-parents=0 --format='%ct %H' HEAD |
		sort -n | head -n 1 | cut -d' ' -f2
}

# state_file <session_id> <name>: per-session temp file path.
state_file() {
	printf '%s/gnm-%s-%s' "${TMPDIR:-/tmp}" "$1" "$2"
}

# path_key <path>: stable hash of a path, for temp file names.
path_key() {
	printf '%s' "$1" | git hash-object --stdin
}

# note_read <ref> <obj>: print the raw note; non-zero if none.
note_read() {
	git notes --ref="$1" show "$2" 2>/dev/null
}

# has_header: true if the note on stdin starts with a header.
has_header() {
	local first
	IFS= read -r first || return 1
	case $first in status:*) ;; *) return 1 ;; esac
	grep -qx -- '---'
}

# parse_header <name>: print header field <name> of the note on stdin.
parse_header() {
	local note
	note=$(cat)
	if ! has_header <<<"$note"; then
		[ "$1" = status ] && echo current
		return 0
	fi
	sed -n '/^---$/q; s/^'"$1"': *//p' <<<"$note"
}

# note_body: print the free-text body of the note on stdin.
note_body() {
	local note
	note=$(cat)
	if has_header <<<"$note"; then
		sed '1,/^---$/d' <<<"$note"
	else
		printf '%s\n' "$note"
	fi
}

# note_put <ref> <obj>: replace the note on <obj> with stdin.
note_put() {
	git notes --ref="$1" add -f -F - "$2" >/dev/null 2>&1
}

# note_write <ref> <obj> <status> <text> [migrated-from] [verified-at]
note_write() {
	local verified=${6:-$(git rev-parse HEAD)}
	{
		echo "status: $3"
		echo "verified-at: $verified"
		[ -n "$5" ] && echo "migrated-from: $5"
		echo '---'
		printf '%s\n' "$4"
	} | note_put "$1" "$2"
}

# note_migrate <old blob> <new blob>: copy a file note forward as
# needs-review. Never overwrites a note already on <new>. True if copied.
note_migrate() {
	local note
	[ "$1" != "$2" ] || return 1
	note=$(note_read "$FILE_REF" "$1") || return 1
	note_read "$FILE_REF" "$2" >/dev/null && return 1
	note_write "$FILE_REF" "$2" needs-review "$(note_body <<<"$note")" \
		"$1" "$(parse_header verified-at <<<"$note")"
}

# emit_context <event> <text>: print hook JSON that adds context for Claude.
emit_context() {
	jq -n --arg e "$1" --arg c "$2" \
		'{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
}
