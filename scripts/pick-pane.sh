#!/usr/bin/env bash
# fzf pane picker — reads pre-sorted `<pane_id>|<display>` lines from stdin,
# shows only the display column, and prints the selected pane_id to stdout.
# Exits non-zero without output if the user cancels.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW="$PLUGIN_DIR/scripts/preview.sh"
set -e

fzf --delimiter='|' \
    --with-nth=2.. \
    --layout=reverse \
    --highlight-line \
    --preview-window 'bottom,70%' \
    --preview-label ' Preview ' \
    --prompt 'panes ❯ ' \
    --preview "${PREVIEW} {1}" \
| cut -d'|' -f1
