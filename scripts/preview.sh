#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

id="$1"
if [[ "$id" == remote:* ]]; then
    rest="${id#remote:}"
    host="${rest%%:*}"
    sess="${rest#*:}"
    ssh -o ConnectTimeout=2 \
        -o BatchMode=yes \
        "$host" "tmux capture-pane -ep -t '$sess' 2>/dev/null" 2>/dev/null \
        || printf "(session unavailable)\n"
else
    tmux capture-pane -ep -t "$id"
fi
