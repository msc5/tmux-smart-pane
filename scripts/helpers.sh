#!/usr/bin/env bash
# Shared helpers — source this file, do not execute it directly.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${SMART_PANE_BASE_PATH:=${HOME}/.local/share/tmux-smart-pane/}"
: "${SMART_PANE_CACHE:=${SMART_PANE_BASE_PATH}/swap-cache.sh}"
: "${REMOTE_SESSIONS_CACHE_PATH:=${SMART_PANE_BASE_PATH}/jump-cache-remote-sessions.txt}"

# Allow tmux.conf to override the cache path.
_cache_opt=$(tmux show-option -gqv "@smart-pane-cache-path" 2>/dev/null)
[[ -n "$_cache_opt" ]] && SMART_PANE_CACHE="$_cache_opt"
unset _cache_opt

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

# Portable in-place sed: GNU sed uses -i, BSD sed requires -i ''.
_sed_inplace() {
    if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

_get_ssh_hosts() {
    # @smart-pane-ssh-hosts overrides auto-discovery; if unset, parse ~/.ssh/config.
    local hosts_opt
    hosts_opt=$(tmux show-option -gqv "@smart-pane-ssh-hosts" 2>/dev/null)

    if [[ -n "$hosts_opt" ]]; then
        echo "$hosts_opt"
    else
        grep -E '^Host[[:space:]]+' ~/.ssh/config 2>/dev/null \
            | grep -v -e '\*' -e 'github' \
            | awk '{print $2}' \
            | xargs
    fi
}
