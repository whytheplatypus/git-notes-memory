#!/usr/bin/env bash
# PostToolUse (Edit|Write): if the edited file had a note, copy it to the
# new blob as needs-review and remind Claude to re-verify it.
. "$(dirname "$0")/lib.sh"

hook_input
path=$(field .tool_input.file_path)
session=$(field .session_id)
[ -n "$session" ] || exit 0
saved=$(state_file "$session" "$(path_key "$path")")
[ -f "$saved" ] || exit 0
old=$(cat "$saved")
rm -f "$saved"
enter_file_repo "$path"

new=$(git hash-object -- "$path")
note_migrate "$old" "$new" || exit 0
printf '%s\t%s\n' "$path" "$new" >>"$(state_file "$session" touched)"

emit_context PostToolUse "git-notes-memory: $REL has a file note that is now needs-review (migrated-from ${old:0:12}). Re-verify it against your change and update it with /git-notes-memory:note $REL \"<text>\" before finishing."
exit 0
