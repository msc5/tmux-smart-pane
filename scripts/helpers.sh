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

# --- Logging -----------------------------------------------------------------
# Level comes from @smart-pane-log-level: off (default) | error | info | debug | trace.
# The first script in a process tree reads the tmux option and exports the
# result, so children (jump-list.sh, fzf previews, connect-remote.sh) skip the
# extra tmux round-trip.
: "${SMART_PANE_LOG:=${SMART_PANE_BASE_PATH}/debug.log}"
if [[ -z "${TMSP_LOG_LEVEL+x}" ]]; then
    TMSP_LOG_LEVEL=$(tmux show-option -gqv "@smart-pane-log-level" 2>/dev/null)
fi
export TMSP_LOG_LEVEL SMART_PANE_LOG

case "$TMSP_LOG_LEVEL" in
    error) TMSP_LOG_LEVEL_NUM=1 ;;
    info)  TMSP_LOG_LEVEL_NUM=2 ;;
    debug) TMSP_LOG_LEVEL_NUM=3 ;;
    trace) TMSP_LOG_LEVEL_NUM=4 ;;
    *)     TMSP_LOG_LEVEL_NUM=0 ;;
esac

# Where diagnostic stderr goes: the log when debugging, otherwise nowhere.
TMSP_ERR=/dev/null
# Extra ssh flags: -E sends ssh's own diagnostics (auth failures, timeouts,
# forwarding errors) to the log without touching the TTY; -v adds handshake detail.
TMSP_SSH_LOG_OPTS=()

if (( TMSP_LOG_LEVEL_NUM > 0 )); then
    mkdir -p "$(dirname "$SMART_PANE_LOG")"
fi
if (( TMSP_LOG_LEVEL_NUM >= 3 )); then
    TMSP_ERR="$SMART_PANE_LOG"
    TMSP_SSH_LOG_OPTS=(-E "$SMART_PANE_LOG")
fi
if (( TMSP_LOG_LEVEL_NUM >= 4 )); then
    TMSP_SSH_LOG_OPTS=(-v -E "$SMART_PANE_LOG")
fi

# _log <level> <message...>
_log() {
    (( TMSP_LOG_LEVEL_NUM > 0 )) || return 0
    local n
    case "$1" in error) n=1 ;; info) n=2 ;; debug) n=3 ;; *) n=4 ;; esac
    (( TMSP_LOG_LEVEL_NUM >= n )) || return 0
    printf '%(%F %T)T %-5s %s[%d] %s\n' -1 "$1" "${0##*/}" "$$" "${*:2}" \
        >> "$SMART_PANE_LOG" 2>/dev/null
    return 0
}

# At debug and above, record any command that fails unexpectedly. Commands in
# if/&&/|| conditions don't trigger ERR, so intentional probes stay quiet.
if (( TMSP_LOG_LEVEL_NUM >= 3 )); then
    set -o errtrace
    trap '_log debug "command failed (exit $?) at ${BASH_SOURCE[0]##*/}:${LINENO} in ${FUNCNAME[0]:-main}: $BASH_COMMAND"' ERR
fi

# At trace, bash xtrace every command (with file:line) into the log.
if (( TMSP_LOG_LEVEL_NUM >= 4 )); then
    exec {_tmsp_xtrace_fd}>>"$SMART_PANE_LOG"
    BASH_XTRACEFD=$_tmsp_xtrace_fd
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO} ${FUNCNAME[0]:-main}: '
    set -x
fi

_humanize_seconds() {
    local t=$1 d h m s
    s=$(( t % 60 ))
    m=$(( (t / 60) % 60 ))
    h=$(( (t / 60 / 60) % 24 ))
    d=$(( t / 60 / 60 / 24 ))

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

    local hosts
    if [[ -n "$hosts_opt" ]]; then
        hosts="$hosts_opt"
    else
        hosts=$(grep -E '^Host[[:space:]]+' ~/.ssh/config 2>/dev/null \
            | grep -v -e '\*' -e 'github' \
            | awk '{print $2}' \
            | xargs)
    fi
    _log debug "ssh hosts from $([[ -n "$hosts_opt" ]] && echo @smart-pane-ssh-hosts || echo '~/.ssh/config'): ${hosts:-<none>}"
    echo "$hosts"
}
