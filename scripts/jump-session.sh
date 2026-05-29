#!/usr/bin/env bash
# Invoked via tmux display-popup (normal) or directly from connect-remote.sh
# (--standalone mode, where fzf runs in the bare terminal before re-attaching).
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
JUMP_LIST="$PLUGIN_DIR/scripts/jump-list.sh"
PREVIEW="$PLUGIN_DIR/scripts/preview.sh"

STANDALONE=0
FALLBACK_SESSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --standalone)
            STANDALONE=1
            FALLBACK_SESSION="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done


KILL_SESSION="$PLUGIN_DIR/scripts/kill-session.sh"
HEADER="Jump to Session (ctrl-x: kill session)"

selected=$(
    fzf --delimiter='|' \
        --ansi \
        --with-nth=2.. \
        --layout=reverse \
        --highlight-line \
        --preview-window 'bottom,70%' \
        --preview-label ' Preview ' \
        --preview "$PREVIEW {1}" \
        --prompt "@$(hostname) > " \
        --header "$HEADER" \
        --bind "load:reload-sync($JUMP_LIST all)" \
        --bind "ctrl-x:execute-silent($KILL_SESSION {1})+reload($JUMP_LIST all 1)" \
        < <("$JUMP_LIST" all 1)
)

p_id="${selected%%|*}"

# None selected from fzf
if [[ -z "$p_id" ]]; then
    (( STANDALONE )) && exec tmux attach-session -t "$FALLBACK_SESSION"
    exit 0
fi

if [[ "$p_id" == remote:* ]]; then
    rest="${p_id#remote:}"
    if [[ -n "${TMSP_LOCAL_SOCKET:-}" ]]; then
        # On a managed remote — signal connect-remote.sh via the local socket
        # to initiate the SSH connection from the local machine.
        tmux -S "$TMSP_LOCAL_SOCKET" set-environment -g \
            TMSP_PENDING_REMOTE "${rest%%:*}:${rest#*:}" 2>/dev/null || true
        tmux detach-client -t "$(tmux display-message -p '#{client_name}' 2>/dev/null)"
    elif (( STANDALONE )); then
        exec "$PLUGIN_DIR/scripts/connect-remote.sh" \
            "${rest%%:*}" "${rest#*:}" "$FALLBACK_SESSION"
    else
        saved_session="$(tmux display-message -p '#S')"
        cmd=$(printf '%q ' \
            "$PLUGIN_DIR/scripts/connect-remote.sh" \
            "${rest%%:*}" "${rest#*:}" \
            "$saved_session")
        tmux detach-client -E "$cmd"
    fi
elif [[ "$p_id" == local:* ]]; then
    actual_pane_id="${p_id#local:}"
    if [[ -n "${TMSP_LOCAL_SOCKET:-}" ]]; then
        tmux -S "$TMSP_LOCAL_SOCKET" set-environment -g \
            TMSP_PENDING_LOCAL "$actual_pane_id" 2>/dev/null || true
        tmux detach-client -t "$(tmux display-message -p '#{client_name}' 2>/dev/null)"
    fi
elif [[ "$p_id" == tmuxinator:* ]]; then
    session_name="${p_id#tmuxinator:}"
    tmuxinator start "$session_name"
    if (( STANDALONE )); then
        exec tmux attach-session -t "$session_name"
    else
        tmux switch-client -t "$session_name"
    fi
else
    if (( STANDALONE )); then
        target_sess=$(tmux list-panes -a \
            -F "#{pane_id}|#{session_name}" 2>/dev/null | \
            awk -F'|' -v id="$p_id" '$1==id{print $2;exit}')
        exec tmux attach-session -t "${target_sess:-$FALLBACK_SESSION}" \
            ';' select-pane -t "$p_id"
    else
        tmux switch-client -t "$p_id"
        tmux select-pane -t "$p_id"
    fi
fi
