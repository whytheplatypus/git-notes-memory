#!/usr/bin/env bash
# Stop: remind Claude, once, of file notes it left needs-review this session.
. "$(dirname "$0")/lib.sh"

hook_input
[ "$(field .stop_hook_active)" = true ] && exit 0
session=$(field .session_id)
[ -n "$session" ] || exit 0
touched=$(state_file "$session" touched)
[ -f "$touched" ] || exit 0

list=
# Latest entry per path only; earlier blobs are intermediate edits.
while IFS=$'\t' read -r path blob; do
	status=$( (enter_file_repo "$path" && note_read "$FILE_REF" "$blob" | parse_header status) )
	[ "$status" = needs-review ] && list="$list
- $path"
done < <(awk -F'\t' '{last[$1] = $2} END {for (p in last) print p "\t" last[p]}' "$touched")

rm -f "$touched" # remind once; don't nag every later turn
[ -n "$list" ] || exit 0
emit_context Stop "git-notes-memory: these file notes are still needs-review after your edits:$list
Re-verify each and update it with /git-notes-memory:note <path> \"<text>\", or tell the user why it can't be resolved."
exit 0
