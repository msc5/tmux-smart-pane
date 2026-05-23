#!/usr/bin/env bash
# Swaps two panes and records the pair in the undo cache.
# Usage: swap-pane.sh <src_pane_id> <target_pane_id>
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

src_pane="$1"
target_pane="$2"

[[ -z "$target_pane" ]] && exit 0

mkdir -p "$(dirname "$SMART_PANE_CACHE")"
declare -A CACHE
[[ -f "$SMART_PANE_CACHE" ]] && source -- "$SMART_PANE_CACHE"
CACHE[swap-pane]="${src_pane}:${target_pane}"
declare -p CACHE > "$SMART_PANE_CACHE"

tmux swap-pane -s "$src_pane" -t "$target_pane"
