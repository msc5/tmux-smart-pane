#!/usr/bin/env bash
# Shared helpers — source this file, do not execute it directly.

: "${SMART_PANE_CACHE:=${HOME}/.local/share/tmux-smart-pane/cache.sh}"
REMOTE_SESSIONS_CACHE_PATH="/tmp/jump-cache-remote-sessions.txt"

_humanize_seconds() {
    local t=$1 d h m s
    (( s = t % 60 ))
    (( m = (t / 60) % 60 ))
    (( h = (t / 60 / 60) % 24 ))
    (( d = (t / 60 / 60 / 24) ))

    if (( d > 0 )); then
        printf "%dd %dh %dm %ds" "$d" "$h" "$m" "$s"
    elif (( h > 0 )); then
        printf "%dh %dm %ds" "$h" "$m" "$s"
    elif (( m > 0 )); then
        printf "%dm %ds" "$m" "$s"
    else
        printf "%ds" "$s"
    fi
}

# Emit `tty<TAB>command` for every controlling terminal's foreground process.
# `pid == tpgid` picks the process-group leader (the actual running command,
# not the shell). Single ps pass.
_tmux_fg_cmd_lines() {
    ps -axo tty=,pid=,tpgid=,args= | awk '
        $1 != "??" && $2 == $3 {
            tty = $1; $1 = $2 = $3 = ""
            sub(/^ +/, "")
            sub(/^[^ ]*\//, "")
            gsub(/[[:cntrl:]]/, "")
            gsub(/\|/, " ")
            print tty "\t" $0
        }'
}

# Detach from local tmux, connect to a remote tmux session via SSH, then
# re-attach on return. The session picker opens on re-attach.
_remote_jump() {
    local host="$1" sess="$2"
    local plugin_dir
    plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local saved_session
    saved_session="$(tmux display-message -p '#S')"

    local cmd
    cmd=$(printf '%q ' \
        "$plugin_dir/scripts/connect-remote.sh" \
        "$host" "$sess" \
        "$saved_session" \
        "$plugin_dir")

    tmux detach-client -E "$cmd"
}

# Swap src_pane (arg) with target_pane (read from stdin), saving state to cache.
_store_swap_pane() {
    local src_pane="$1"
    local target_pane
    read -r target_pane

    [[ -z "$target_pane" ]] && return 0

    mkdir -p "$(dirname "$SMART_PANE_CACHE")"
    declare -A CACHE
    [[ -f "$SMART_PANE_CACHE" ]] && source -- "$SMART_PANE_CACHE"
    CACHE[swap-pane]="${src_pane}:${target_pane}"
    declare -p CACHE > "$SMART_PANE_CACHE"

    tmux swap-pane -s "$src_pane" -t "$target_pane"
}
