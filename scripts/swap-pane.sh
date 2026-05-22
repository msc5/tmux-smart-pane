#!/usr/bin/env bash
# Invoked via tmux display-popup. Shows the shared pane picker and swaps the
# current pane with the selection.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PLUGIN_DIR/scripts/helpers.sh"

_cache_opt=$(tmux show-option -gqv "@smart-pane-cache-path" 2>/dev/null)
[[ -n "$_cache_opt" ]] && SMART_PANE_CACHE="$_cache_opt"
unset _cache_opt

this_pane_id="$(tmux display-message -p "#{pane_id}")"

"$PLUGIN_DIR/scripts/jump-list.sh" panes |
"$PLUGIN_DIR/scripts/pick-pane.sh" | 
_store_swap_pane "$this_pane_id"
