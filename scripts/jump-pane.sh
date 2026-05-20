#!/usr/bin/env bash
# Invoked via tmux display-popup. Single fzf instance that toggles between a
# session picker and a pane picker with Ctrl-L.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUMP_LIST="$PLUGIN_DIR/scripts/jump-list.sh"

TOGGLE_ACTION="transform:case \"\$FZF_PROMPT\" in sessions*) echo \"change-prompt(panes ❯ )+reload($JUMP_LIST panes)\";; *) echo \"change-prompt(sessions ❯ )+reload($JUMP_LIST sessions)\";; esac"

selected=$(
    fzf --delimiter='|' \
        --with-nth=2.. \
        --layout=reverse \
        --highlight-line \
        --header 'ctrl-l: toggle sessions / panes' \
        --preview-window 'bottom,70%' \
        --preview-label ' Preview ' \
        --preview 'tmux capture-pane -ep -t {1}' \
        --bind "start:reload($JUMP_LIST sessions)" \
        --bind "ctrl-l:$TOGGLE_ACTION" \
        < /dev/null
)

p_id="${selected%%|*}"
[[ -z "$p_id" ]] && exit 0
tmux switch-client -t "$p_id"
tmux select-pane -t "$p_id"
