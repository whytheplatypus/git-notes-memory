#!/usr/bin/env bash
# PreToolUse (Read|Edit|Write): inject the file's note; remember its blob
# hash before an edit so post-tool.sh can migrate the note.
. "$(dirname "$0")/lib.sh"

hook_input
path=$(field .tool_input.file_path)
tool=$(field .tool_name)
session=$(field .session_id)
enter_file_repo "$path"

h=$(git hash-object -- "$path")
case $tool in Edit | Write)
	[ -n "$session" ] && echo "$h" >"$(state_file "$session" "$(path_key "$path")")"
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

emit_context PreToolUse "git-notes-memory: file note for $REL ($label):
$(note_body <<<"$note")"
exit 0
