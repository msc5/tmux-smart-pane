#!/usr/bin/env bash
# Invoked via tmux display-popup (normal) or directly from connect-remote.sh
# (--standalone mode, where fzf runs in the bare terminal before re-attaching).
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
JUMP_LIST="$PLUGIN_DIR/scripts/jump-list.sh"
PREVIEW="$PLUGIN_DIR/scripts/preview.sh"

# In a managed SSH session: detach to trigger return to local tmux + picker.
if [[ -n "${TMSP_MANAGED:-}" ]]; then
    client=$(tmux display-message -p '#{client_name}' 2>/dev/null)
    tmux detach-client -t "$client"
    exit 0
fi

STANDALONE=0
FALLBACK_SESSION=""
if [[ "${1:-}" == --standalone ]]; then
    STANDALONE=1
    FALLBACK_SESSION="${2:-}"

fi

KILL_SESSION="$PLUGIN_DIR/scripts/kill-session.sh"

selected=$(
    fzf --delimiter='|' \
        --ansi \
        --with-nth=2.. \
        --layout=reverse \
        --highlight-line \
        --preview-window 'bottom,70%' \
        --preview-label ' Preview ' \
        --preview "$PREVIEW {1}" \
        --header 'Jump to Session (ctrl-x: kill session)' \
        --bind "load:reload-sync($JUMP_LIST all; sleep 3)" \
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
    if (( STANDALONE )); then
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
