#!/usr/bin/env bash
# Reverses the last pane swap recorded in the cache (acts as a toggle).
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PLUGIN_DIR/scripts/helpers.sh"

_cache_opt=$(tmux show-option -gqv "@smart-pane-cache-path" 2>/dev/null)
[[ -n "$_cache_opt" ]] && SMART_PANE_CACHE="$_cache_opt"
unset _cache_opt

[[ -f "$SMART_PANE_CACHE" ]] || exit 0

declare -A CACHE
source -- "$SMART_PANE_CACHE"

[[ -z "${CACHE[swap-pane]:-}" ]] && exit 0

IFS=":" read -r old_src old_target <<< "${CACHE[swap-pane]}"
[[ -z "$old_src" || -z "$old_target" ]] && exit 0

_swap_pane "$old_src" "$old_target" 
