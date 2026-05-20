#!/usr/bin/env bash
# Shared helpers — source this file, do not execute it directly.

: "${SMART_PANE_CACHE:=${HOME}/.local/share/tmux-smart-pane/cache.sh}"

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

# Find-or-create local session remote-<host> with a window for <session>,
# then switch the tmux client into it.
_remote_jump() {
    local host="$1" sess="$2"
    local local_sess="remote-$host"

    if ! tmux has-session -t "$local_sess" 2>/dev/null; then
        tmux new-session -d -s "$local_sess" -n "$sess" \
            "ssh $host -t tmux new-session -As '$sess'"
    elif ! tmux list-windows -t "$local_sess" -F "#{window_name}" 2>/dev/null \
            | grep -qx "$sess"; then
        tmux new-window -t "$local_sess:" -n "$sess" \
            "ssh $host -t tmux new-session -As '$sess'"
    else
        # Window exists but inner tmux may have drifted to a different session;
        # switch all remote clients back to the intended one.
        ssh -o BatchMode=yes "$host" \
            "tmux list-clients -F '#{client_name}' 2>/dev/null \
             | while read -r c; do tmux switch-client -c \"\$c\" -t '$sess'; done" \
            2>/dev/null || true
    fi

    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$local_sess:$sess"
    else
        tmux attach-session -t "$local_sess:$sess"
    fi
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
