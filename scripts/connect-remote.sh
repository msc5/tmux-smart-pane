#!/usr/bin/env bash
# Manages a remote tmux session connection. Invoked via `tmux detach-client -E`.
# Args: host sess saved-session
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

host="$1"
sess="$2"
saved_session="$3"

local_socket_path=$(tmux display-message -p "#{socket_path}")
remote_socket_path="/tmp/$(hostname)-$(date +%s)-tmux.sock"

# TMSP_MANAGED: signals jump-session.sh on the remote it's in a managed session.
# TMSP_LOCAL_SOCKET: path on the remote where the local socket is forwarded.
# Both are unset when tmux exits so they don't linger.
remote_cmd=$(printf \
    'clear; tmux set-environment -g TMSP_MANAGED 1 >/dev/null 2>&1; tmux set-environment -g TMSP_LOCAL_SOCKET %q >/dev/null 2>&1; tmux new-session -As %q; tmux set-environment -gu TMSP_MANAGED >/dev/null 2>&1; tmux set-environment -gu TMSP_LOCAL_SOCKET >/dev/null 2>&1' \
    "$remote_socket_path" "$sess")

ssh -t \
    -R "${remote_socket_path}:${local_socket_path}" \
    "$host" \
    "$remote_cmd" \
|| true

# Update the sort timestamp for this session in the remote cache so it sorts to the top.
_sed_inplace -E "/remote:$host:$sess/ s/[0-9]+/$(date +%s)/" "$REMOTE_SESSIONS_CACHE_PATH"

# Check for pending navigation requests set by jump-session.sh on the remote
# via the forwarded local socket. Read and clear each var atomically.
_read_and_clear() {
    local val
    val=$(tmux show-environment -g "$1" 2>/dev/null) || return 0
    [[ "$val" == "${1}="* ]] || return 0
    printf '%s' "${val#*=}"
    tmux set-environment -gu "$1" 2>/dev/null || true
}

pending_remote=$(_read_and_clear TMSP_PENDING_REMOTE)
pending_local=$(_read_and_clear TMSP_PENDING_LOCAL)

if [[ -n "$pending_remote" ]]; then
    r_host="${pending_remote%%:*}"
    r_sess="${pending_remote#*:}"
    exec "$PLUGIN_DIR/scripts/connect-remote.sh" "$r_host" "$r_sess" "$saved_session"
elif [[ -n "$pending_local" ]]; then
    target_sess=$(tmux list-panes -a -F "#{pane_id}|#{session_name}" 2>/dev/null | \
        awk -F'|' -v id="$pending_local" '$1==id{print $2;exit}')
    exec tmux attach-session -t "${target_sess:-$saved_session}" \
        ';' select-pane -t "$pending_local"
else
    exec "$PLUGIN_DIR/scripts/jump-session.sh" --standalone "$saved_session"
fi
