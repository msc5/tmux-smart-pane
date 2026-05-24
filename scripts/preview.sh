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
elif [[ "$id" == tmuxinator:* ]]; then
    name="${id#tmuxinator:}"
    config_path="${XDG_CONFIG_HOME:-$HOME/.config}/tmuxinator/${name}.yml"
    [[ ! -f "$config_path" ]] && config_path="$HOME/.tmuxinator/${name}.yml"
    if [[ -f "$config_path" ]]; then
        _bat=$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null)
        if [[ -n "$_bat" ]]; then
            "$_bat" --style=plain --color=always --language=yaml "$config_path"
        else
            cat "$config_path"
        fi
    else
        printf "(tmuxinator config not found: %s)\n" "$name"
    fi
else
    tmux capture-pane -ep -t "$id"
fi
