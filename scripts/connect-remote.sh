#!/usr/bin/env bash
# Manages a remote tmux session connection. Invoked via `tmux detach-client -E`.
# Args: host sess saved-session
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

host="$1"
sess="$2"
saved_session="$3"

# TMSP_MANAGED tells jump-session.sh on the remote that C-b+s should detach
# rather than open fzf. Unset after tmux exits so it doesn't linger.
remote_cmd=$(printf \
    'clear; tmux set-environment -g TMSP_MANAGED 1 >/dev/null 2>&1; tmux new-session -As %q; tmux set-environment -gu TMSP_MANAGED >/dev/null 2>&1' \
    "$sess")

ssh -t "$host" "$remote_cmd" || true

# Update the sort timestamp for this session in the remote cache so it sorts to the top.
_sed_inplace -E "/remote:$host:$sess/ s/[0-9]+/$(date +%s)/" "$REMOTE_SESSIONS_CACHE_PATH"

exec "$PLUGIN_DIR/scripts/jump-session.sh" --standalone "$saved_session"
