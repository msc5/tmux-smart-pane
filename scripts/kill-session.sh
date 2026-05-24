#!/usr/bin/env bash
# Kill the tmux session that owns the given pane ID.
# Called from jump-session.sh's ctrl-x fzf binding.
p="$1"
[[ "$p" == %* ]] || exit 0
sess=$(tmux display-message -p -t "$p" "#{session_name}" 2>/dev/null)
[[ -n "$sess" ]] && tmux kill-session -t "$sess"
