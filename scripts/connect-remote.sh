#!/usr/bin/env bash
# Manages a remote tmux session connection. Invoked via `tmux detach-client -E`.
# Args: host sess ctrl-sock local-tmux-sock saved-session plugin-dir
host="$1"
sess="$2"
ctrl_sock="$3"
local_tmux_sock="$4"
saved_session="$5"
plugin_dir="$6"

_tmux() { tmux -S "$local_tmux_sock" "$@"; }

ctrl_dir="$(dirname "$ctrl_sock")"
remote_back_sock="/tmp/tmsp-$(id -u)-${host}.sock"

mkdir -p "$ctrl_dir"

# Record connection time for session recency ordering in the jump list.
date +%s > "$ctrl_dir/${host}:${sess}.last"

# Clear any stale return-picker signal.
_tmux set-environment -u TMSP_RETURN_PICKER 2>/dev/null || true

# Pass the local tmux socket to the remote session so jump-pane.sh can signal back.
remote_cmd=$(printf \
    'clear; tmux set-environment -g TMUX_LOCAL_SOCKET %q >/dev/null 2>&1; tmux set-environment -g TMUX_LOCAL_PLUGIN_DIR %q >/dev/null 2>&1; exec tmux new-session -As %q' \
    "$remote_back_sock" "$plugin_dir" "$sess")

# Clean up any stale back-channel socket on the remote (left by a prior crashed session).
# Uses the ControlMaster if it's already open; silently no-ops otherwise.
ssh -q -o ControlPath="$ctrl_sock" -o ControlMaster=no -o BatchMode=yes \
    "$host" "rm -f $(printf '%q' "$remote_back_sock")" >/dev/null 2>&1 || true

ssh \
    -t \
    -o ControlPath=none \
    -R "${remote_back_sock}:${local_tmux_sock}" \
    "$host" \
    "$remote_cmd" \
|| true

# If remote used C-b+s to return, open the session picker immediately on re-attach.
# Passing display-popup as a command sequence after attach-session is more reliable
# than a client-attached hook, which fires before the client terminal is fully ready.
if _tmux show-environment TMSP_RETURN_PICKER 2>/dev/null | grep -q '^TMSP_RETURN_PICKER=1$'; then
    _tmux set-environment -u TMSP_RETURN_PICKER 2>/dev/null || true
    exec tmux -S "$local_tmux_sock" \
        attach-session -t "$saved_session" ';' \
        display-popup -w 100% -h 100% -b none \
        -E "$plugin_dir/scripts/jump-pane.sh"
fi

exec tmux -S "$local_tmux_sock" attach-session -t "$saved_session"
