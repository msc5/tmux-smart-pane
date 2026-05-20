#!/usr/bin/env bash
# Invoked via tmux display-popup (normal) or directly from connect-remote.sh
# (--standalone mode, where fzf runs in the bare terminal before re-attaching).
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUMP_LIST="$PLUGIN_DIR/scripts/jump-list.sh"
PREVIEW="$PLUGIN_DIR/scripts/preview.sh"
source "$PLUGIN_DIR/scripts/helpers.sh"

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

TOGGLE_ACTION="transform:case \"\$FZF_PROMPT\" in sessions*) echo \"change-prompt(panes ❯ )+reload($JUMP_LIST panes)\";; *) echo \"change-prompt(sessions ❯ )+reload($JUMP_LIST sessions)\";; esac"

selected=$(
    fzf --delimiter='|' \
        --with-nth=2.. \
        --layout=reverse \
        --highlight-line \
        --header 'ctrl-l: toggle sessions / panes' \
        --preview-window 'bottom,70%' \
        --preview-label ' Preview ' \
        --preview "$PREVIEW {1}" \
        --bind "start:reload($JUMP_LIST sessions)" \
        --bind "ctrl-l:$TOGGLE_ACTION" \
        < /dev/null
)

p_id="${selected%%|*}"

if [[ -z "$p_id" ]]; then
    (( STANDALONE )) && exec tmux attach-session -t "$FALLBACK_SESSION"
    exit 0
fi

if [[ "$p_id" == remote:* ]]; then
    rest="${p_id#remote:}"
    if (( STANDALONE )); then
        exec "$PLUGIN_DIR/scripts/connect-remote.sh" \
            "${rest%%:*}" "${rest#*:}" "$FALLBACK_SESSION" "$PLUGIN_DIR"
    else
        _remote_jump "${rest%%:*}" "${rest#*:}"
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
