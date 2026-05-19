#!/usr/bin/env bash
# fzf pane picker — reads pre-sorted `<pane_id>|<display>` lines from stdin,
# shows only the display column, and prints the selected pane_id to stdout.
# Exits non-zero without output if the user cancels.
set -e

fzf --delimiter='|' \
    --with-nth=2.. \
    --layout=reverse \
    --prompt 'panes> ' \
    --preview-window bottom \
    --preview-label ' Pane ' \
    --preview 'tmux capture-pane -ep -t {1}' |
cut -d'|' -f1
