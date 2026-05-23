#!/usr/bin/env bash
# Reverses the last pane swap recorded in the cache (acts as a toggle).
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

[[ -f "$SMART_PANE_CACHE" ]] || exit 0

declare -A CACHE
source -- "$SMART_PANE_CACHE"

[[ -z "${CACHE[swap-pane]:-}" ]] && exit 0

IFS=":" read -r old_src old_target <<< "${CACHE[swap-pane]}"
[[ -z "$old_src" || -z "$old_target" ]] && exit 0

"$PLUGIN_DIR/scripts/swap-pane.sh" "$old_src" "$old_target"
