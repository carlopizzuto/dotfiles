#!/usr/bin/env bash
# Claude Code statusline command — extracts session data and writes to /tmp
# for consumption by nvim lualine (claudecode_status.lua).

json=$(cat)

session_id=$(printf '%s' "$json" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

printf '%s' "$json" | jq -c '{
  context_pct:  (.context_window.used_percentage // 0),
  total_tokens: ((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)),
  rate_pct:     (.rate_limits.five_hour.used_percentage // 0),
  resets_at:    (.rate_limits.five_hour.resets_at // 0),
  session_id:   .session_id
}' > "/tmp/claude_status_${session_id}.json"