#!/usr/bin/env bash
# Manages a remote tmux session connection. Invoked via `tmux detach-client -E`.
# Args: host sess saved-session plugin-dir
host="$1"
sess="$2"
saved_session="$3"
plugin_dir="$4"

# TMSP_MANAGED tells jump-pane.sh on the remote that C-b+s should detach
# rather than open fzf. Unset after tmux exits so it doesn't linger.
remote_cmd=$(printf \
    'clear; tmux set-environment -g TMSP_MANAGED 1 >/dev/null 2>&1; tmux new-session -As %q; tmux set-environment -gu TMSP_MANAGED >/dev/null 2>&1' \
    "$sess")

ssh -t "$host" "$remote_cmd" || true

exec "$plugin_dir/scripts/jump-pane.sh" --standalone "$saved_session"
