#!/usr/bin/env bash
# Toggle to the previous session, local or remote. Invoked via run-shell.
# Args: client-name session-name
#
# The previous location lives in the local server's @smart-pane-last-location
# option as `local:<session>` or `remote:<host>:<session>`. Local switches keep
# it current through the client-session-changed hook; connect-remote.sh and
# jump-session.sh set it around remote hops.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

client="$1"
current="$2"

# On a managed remote — hand the decision to connect-remote.sh on the local
# machine, which knows where we came from.
if [[ -n "${TMSP_LOCAL_SOCKET:-}" ]] && [[ -n "${TMSP_MANAGED:-}" ]]; then
    _log debug "managed remote: setting TMSP_PENDING_LAST via $TMSP_LOCAL_SOCKET and detaching"
    if tmux -S "$TMSP_LOCAL_SOCKET" set-environment -g TMSP_PENDING_LAST 1 2>>"$TMSP_ERR"; then
        tmux detach-client -t "$client"
        exit 0
    fi
    _log error "failed to set TMSP_PENDING_LAST via $TMSP_LOCAL_SOCKET; falling back to switch-client -l"
fi

last=$(tmux show-option -gqv @smart-pane-last-location)
_log info "jump to last location: ${last:-<none>} (from $current)"

if [[ "$last" == remote:* ]]; then
    rest="${last#remote:}"
    tmux set-option -g @smart-pane-last-location "local:$current"
    cmd=$(printf '%q ' \
        "$PLUGIN_DIR/scripts/connect-remote.sh" \
        "${rest%%:*}" "${rest#*:}" \
        "$current")
    _log debug "detach-client -E $cmd"
    tmux detach-client -t "$client" -E "$cmd"
elif [[ "$last" == local:* && "${last#local:}" != "$current" ]] \
    && tmux has-session -t "=${last#local:}" 2>/dev/null; then
    tmux switch-client -c "$client" -t "=${last#local:}"
else
    tmux switch-client -c "$client" -l 2>>"$TMSP_ERR" \
        || tmux display-message -c "$client" "smart-pane: no previous session"
fi
