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

# new_entries <old> <new>: print the blank-line-separated entries of <new>
# that are not in <old>.
new_entries() {
	awk 'BEGIN { RS = "" } FILENAME == ARGV[1] { seen[$0]; next }
		!($0 in seen) { printf "%s%s", sep, $0; sep = "\n\n" } END { if (sep) print "" }' \
		<(printf '%s\n' "$1") <(printf '%s\n' "$2")
}

# Remote notes: origin's notes are fetched into refs/notes/origin/* (staged)
# and merged into the local refs only once the user trusts origin's URL.
# Staging stays under refs/notes/ because `git notes --ref=X` prefixes
# refs/notes/ to any X that doesn't already start with it.
SYNC_REFS="$FILE_REF $LEARN_REF $ARCH_REF"

# origin_url: print origin's URL; non-zero if there is no origin.
origin_url() {
	git remote get-url origin 2>/dev/null
}

# remote_state: print trusted, ignored or unknown for origin's URL.
remote_state() {
	local url
	url=$(origin_url) || return 1
	if git config --get-all gitnotesmemory.trustedRemote | grep -qxF -- "$url"; then
		echo trusted
	elif git config --get-all gitnotesmemory.ignoredRemote | grep -qxF -- "$url"; then
		echo ignored
	else
		echo unknown
	fi
}

# set_remote <trusted|ignored>: record origin's URL as trusted or ignored.
set_remote() {
	local url key=trustedRemote other=ignoredRemote
	url=$(origin_url) || return 1
	[ "$1" = ignored ] && key=ignoredRemote other=trustedRemote
	git config --fixed-value --unset-all "gitnotesmemory.$other" "$url" 2>/dev/null
	git config --get-all "gitnotesmemory.$key" | grep -qxF -- "$url" ||
		git config --add "gitnotesmemory.$key" "$url"
}

# fetch_staged: fetch origin's notes into refs/notes/origin/*, never into the
# local refs. Never prompts for credentials and gives up after 10 seconds.
fetch_staged() {
	local t=()
	command -v timeout >/dev/null && t=(timeout 10)
	GIT_TERMINAL_PROMPT=0 \
		GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-$(git config core.sshCommand || echo ssh)} -o BatchMode=yes" \
		"${t[@]}" git fetch -q --prune origin '+refs/notes/*:refs/notes/origin/*' 2>/dev/null
}

# note_counts [prefix]: print "<learnings entries> <file notes>" for the refs
# under refs/notes/<prefix>.
note_counts() {
	echo "$(note_read "$1$LEARN_REF" "$(root_commit)" | awk 'BEGIN { RS = "" } END { print NR }')" \
		"$(git notes --ref="$1$FILE_REF" list 2>/dev/null | wc -l)"
}

# resolve <ref> <obj>: print the merged note for a conflict on <obj>.
# Learnings: local entries, then remote entries not already present.
# Others: the local note, unless only the remote one is current.
resolve() {
	local ours theirs extra
	ours=$(note_read "$1" "$2")
	theirs=$(note_read "origin/$1" "$2")
	if [ "$1" = "$LEARN_REF" ]; then
		extra=$(new_entries "$ours" "$theirs")
		printf '%s%s%s\n' "$ours" "${ours:+${extra:+$'\n\n'}}" "$extra"
	elif [ "$(parse_header status <<<"$ours")" = needs-review ] &&
		[ "$(parse_header status <<<"$theirs")" = current ]; then
		printf '%s\n' "$theirs"
	else
		echo "conflict: kept local $1 note on ${2:0:12}" >&2
		printf '%s\n' "$ours"
	fi
}

# merge_ref <ref>: 3-way merge the staged origin/<ref> into the local <ref>.
merge_ref() {
	local dir f
	git rev-parse -q --verify "refs/notes/origin/$1" >/dev/null || return 0
	git notes --ref="$1" merge -q -s manual "origin/$1" >/dev/null 2>&1 && return 0
	dir=$(git rev-parse --git-path NOTES_MERGE_WORKTREE)
	[ -d "$dir" ] || { echo "git-notes-memory: merge of $1 failed" >&2; return 1; }
	for f in "$dir"/*; do
		resolve "$1" "${f##*/}" >"$f"
	done
	git notes merge -q --commit
}

# merge_staged: merge every staged ref, then print what came in, e.g.
# "+2 learnings entries, +1 file notes, architecture note updated".
merge_staged() {
	local root l0 f0 l1 f1 a0 r out=
	root=$(root_commit)
	read -r l0 f0 < <(note_counts)
	a0=$(note_read "$ARCH_REF" "$root")
	for r in $SYNC_REFS; do
		merge_ref "$r"
	done
	read -r l1 f1 < <(note_counts)
	[ "$l1" -gt "$l0" ] && out+=", +$((l1 - l0)) learnings entries"
	[ "$f1" -gt "$f0" ] && out+=", +$((f1 - f0)) file notes"
	[ "$(note_read "$ARCH_REF" "$root")" != "$a0" ] && out+=", architecture note updated"
	[ -z "$out" ] || echo "${out#, }"
}

# staged_summary: describe the staged notes from origin; empty if none.
staged_summary() {
	local l f out=
	read -r l f < <(note_counts origin/)
	[ "$l" -gt 0 ] && out+=", $l learnings entries"
	[ "$f" -gt 0 ] && out+=", $f file notes"
	note_read "origin/$ARCH_REF" "$(root_commit)" >/dev/null && out+=", an architecture note"
	[ -z "$out" ] || echo "${out#, }"
}

# emit_context <event> <text> [message]: print hook JSON that adds context
# for Claude and, if given, shows a message to the user.
emit_context() {
	jq -n --arg e "$1" --arg c "$2" --arg m "${3:-}" \
		'{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}} +
		if $m == "" then {} else {systemMessage: $m} end'
}
