#!/usr/bin/env bash
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PLUGIN_DIR/scripts/helpers.sh"

id="$1"
if [[ "$id" == remote:* ]]; then
    rest="${id#remote:}"
    host="${rest%%:*}"
    sess="${rest#*:}"
    ctrl_sock="$SMART_PANE_CTRL_DIR/${host}.sock"
    ssh -o "ControlPath=${ctrl_sock}" \
        -o ConnectTimeout=2 \
        -o BatchMode=yes \
        "$host" "tmux capture-pane -ep -t '$sess' 2>/dev/null" 2>/dev/null \
        || printf "(session unavailable)\n"
else
    tmux capture-pane -ep -t "$id"
fi
