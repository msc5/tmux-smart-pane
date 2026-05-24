#!/usr/bin/env bash
# Invoked via tmux display-popup.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
JUMP_LIST="$PLUGIN_DIR/scripts/jump-list.sh"
PREVIEW="$PLUGIN_DIR/scripts/preview.sh"

selected=$(
    fzf --delimiter='|' \
        --with-nth=2.. \
        --layout=reverse \
        --highlight-line \
        --preview-window 'bottom,70%' \
        --preview-label ' Preview ' \
        --header 'Jump to pane (ctrl-s: swap pane)' \
        --bind 'ctrl-s:become(echo "swap|{r}")' \
        --bind 'enter:become(echo "jump|{r}")' \
        --preview "$PREVIEW {1}" \
        < <("$JUMP_LIST" panes)
)

action="${selected%%|*}"
selected="${selected#*|}"
p_id="${selected%%|*}"

# None selected from fzf
if [[ -z "$p_id" ]]; then
    (( STANDALONE )) && exec tmux attach-session -t "$FALLBACK_SESSION"
    exit 0
fi

if [[ "$action" = swap ]]; then
    this_pane_id="$(tmux display-message -p "#{pane_id}")"
    "$PLUGIN_DIR/scripts/swap-pane.sh" "$this_pane_id" "$p_id"
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
