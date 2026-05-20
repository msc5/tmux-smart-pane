#!/usr/bin/env bash
# Invoked via tmux display-popup. Single fzf instance that toggles between a
# session picker and a pane picker with Ctrl-L.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUMP_LIST="$PLUGIN_DIR/scripts/jump-list.sh"
PREVIEW="$PLUGIN_DIR/scripts/preview.sh"
source "$PLUGIN_DIR/scripts/helpers.sh"

# In a managed SSH session: signal local tmux to open the picker on re-attach,
# then exit SSH. The local connect-remote.sh wrapper handles re-attaching.
if [[ -n "${TMUX_LOCAL_SOCKET:-}" && -S "${TMUX_LOCAL_SOCKET}" ]]; then
    TMUX="${TMUX_LOCAL_SOCKET}" tmux set-environment TMSP_RETURN_PICKER 1 2>/dev/null || true
    tmux detach-client
    exit 0
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
[[ -z "$p_id" ]] && exit 0

if [[ "$p_id" == remote:* ]]; then
    rest="${p_id#remote:}"
    _remote_jump "${rest%%:*}" "${rest#*:}"
else
    tmux switch-client -t "$p_id"
    tmux select-pane -t "$p_id"
fi
