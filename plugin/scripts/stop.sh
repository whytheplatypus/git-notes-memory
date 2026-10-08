#!/usr/bin/env bash
# Stop: remind Claude, once, of file notes it left needs-review this session;
# and, once per session, after substantial work with no new note recorded,
# ask whether anything met the bar for one.
. "$(dirname "$0")/lib.sh"

NUDGE_AFTER=20 # tool calls

hook_input
[ "$(field .stop_hook_active)" = true ] && exit 0
session=$(field .session_id)
[ -n "$session" ] || exit 0

ctx= nl=$'\n'
touched=$(state_file "$session" touched)
if [ -f "$touched" ]; then
	list=
	# Latest entry per path only; earlier blobs are intermediate edits. The
	# file's current version wins, since it may have changed (e.g. via Bash) and
	# been re-verified after the last Edit; the recorded blob covers a note left
	# behind.
	while IFS=$'\t' read -r path blob; do
		status=$( (enter_file_repo "$path" && {
			note_read "$FILE_REF" "$(git hash-object -- "$path")" || note_read "$FILE_REF" "$blob"
		} | parse_header status) )
		[ "$status" = needs-review ] && list="$list
- $path"
	done < <(awk -F'\t' '{last[$1] = $2} END {for (p in last) print p "\t" last[p]}' "$touched")
	rm -f "$touched" # remind once; don't nag every later turn
	[ -n "$list" ] && ctx="git-notes-memory: these file notes are still needs-review after your edits:$list
Re-verify each and update it with /git-notes-memory:note <path> \"<text>\", or tell the user why it can't be resolved."
fi

started=$(state_file "$session" started)
nudged=$(state_file "$session" nudged)
if [ -f "$started" ] && [ ! -f "$nudged" ]; then
	calls=$(grep -c '"type": *"tool_use"' "$(field .transcript_path)" 2>/dev/null)
	last=$(cat "$(git rev-parse --git-path gnm-last-note 2>/dev/null)" 2>/dev/null)
	if [ "${calls:-0}" -ge "$NUDGE_AFTER" ] && [ "${last:-0}" -lt "$(cat "$started")" ]; then
		touch "$nudged"
		ctx="${ctx:+$ctx$nl$nl}git-notes-memory: this session has made $calls tool calls without recording a new note. If you were corrected, wasted tool calls on something a one-line note would have prevented, or found an unstated convention or footgun, record it now with /git-notes-memory:note (see the git-notes skill). If nothing met that bar, say so in one line and carry on."
	fi
fi

[ -n "$ctx" ] && emit_context Stop "$ctx"
exit 0
