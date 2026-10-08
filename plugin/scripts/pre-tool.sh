#!/usr/bin/env bash
# PreToolUse (Read|Edit|Write|NotebookEdit|Bash): inject the notes of the
# files a tool call names; remember a file's blob hash before an edit so
# post-tool.sh can migrate the note. For Bash, files are guessed from the
# command, and notes already shown this session are skipped.
. "$(dirname "$0")/lib.sh"

MAX_BASH_FILES=5

hook_input
tool=$(field .tool_name)
session=$(field .session_id)

# bash_paths <command>: print absolute paths of up to MAX_BASH_FILES existing
# files named in <command>, relative to the hook's cwd.
bash_paths() {
	tr -s ' \t\n|;&<>()' '\n' <<<"$1" | tr -d "'\"" | while IFS= read -r t; do
		[ -f "$t" ] && printf '%s/%s\n' "$(cd "$(dirname "$t")" && pwd -P)" "$(basename "$t")"
	done | awk '!seen[$0]++' | head -n "$MAX_BASH_FILES"
}

# file_note <abs path>: print the note context for a file. Runs in a subshell
# because enter_file_repo changes directory and exits when there is no repo.
file_note() { (
	enter_file_repo "$1"
	git rev-parse -q --verify "refs/notes/$FILE_REF" >/dev/null || exit 0
	h=$(git hash-object -- "$1")
	case $tool in Edit | Write | NotebookEdit)
		[ -n "$session" ] && echo "$h" >"$(state_file "$session" "$(path_key "$1")")"
		;;
	esac

	if note=$(note_read "$FILE_REF" "$h"); then
		status=$(parse_header status <<<"$note")
		label="status: $status"
		[ "$status" = needs-review ] && label="UNVERIFIED — file changed since written"
	else
		# Miss: walk history (following renames) for a note on an earlier version.
		note=
		while read -r sha && read -r _ && read -r p; do
			blob=$(git rev-parse -q --verify "$sha:$p" 2>/dev/null) || continue
			if note=$(note_read "$FILE_REF" "$blob"); then
				label="from earlier version ${sha:0:12}, possibly stale"
				break
			fi
			note=
		done < <(git log --follow -n 200 --format=%H --name-only -- "$REL" 2>/dev/null)
		[ -n "$note" ] || exit 0
	fi

	echo "git-notes-memory: file note for $REL ($label):"
	note_body <<<"$note"
) }

if [ "$tool" = Bash ]; then
	paths=$(bash_paths "$(field .tool_input.command)")
else
	paths=$(field '.tool_input.file_path // .tool_input.notebook_path')
fi

shown=$(state_file "${session:-none}" shown)
ctx= nl=$'\n'
while IFS= read -r p; do
	c=$(file_note "$p")
	[ -n "$c" ] || continue
	key=$(path_key "$c")
	if [ -n "$session" ]; then
		[ "$tool" = Bash ] && grep -qx "$key" "$shown" 2>/dev/null && continue
		echo "$key" >>"$shown"
	fi
	ctx="${ctx:+$ctx$nl$nl}$c"
done <<<"$paths"

[ -n "$ctx" ] && emit_context PreToolUse "$ctx"
exit 0
