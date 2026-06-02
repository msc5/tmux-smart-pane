#!/usr/bin/env bash
# Generates row listings consumed by jump-session.sh and jump-pane.sh
# Each row: <sort_key>|<pane_id>|<display>
#
# Usage:
#   jump-list.sh sessions   — one row per session (default)
#   jump-list.sh panes      — one row per pane, sorted by @last_seen recency
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Shared tmux format for all session-listing paths (local, socket, SSH).
TMSP_SESSION_FMT="#{session_last_attached}|#{session_created}|#{session_name}|#{session_windows}|#{session_attached_list}|#{pane_current_command}|#{pane_id}|#{@last_seen}"

# Reads '|'-delimited session rows from stdin; emits sort_key|id|display rows.
# Args: now  host_label  id_prefix  id_field (pane_id|session_name)
#   id_field="pane_id"       — use $p_id  (local sessions, forwarded socket)
#   id_field="session_name"  — use $s_name (SSH remotes; connect-remote.sh needs session name)
_format_session_rows() {
    local now="$1" host_label="$2" id_prefix="$3" id_field="${4:-pane_id}" color="$5"
    while IFS='|' read -r s_last s_created s_name s_windows s_clients p_cmd p_id p_last_seen; do
        local ref="${p_last_seen:-0}"
        (( ref == 0 )) && ref="${s_last:-0}"
        (( ref == 0 )) && ref="$s_created"
        (( ref < 0 )) && ref=0

        local id
        [[ "$id_field" == "session_name" ]] && id="${id_prefix}${s_name}" || id="${id_prefix}${p_id}"

        local age_secs=$((now - ref))
        (( age_secs < 0 )) && age_secs=0
        local uptime_secs=$((now - s_created))
        (( uptime_secs < 0 )) && uptime_secs=0

        local win_label="$s_windows window"
        (( s_windows != 1 )) && win_label="$s_windows windows"

        printf "%010d|%s|${color}%-20.20s  %-20s  %-11s  %-30s  %-26.26s  %-26.26s  %-30s\e[0m\n" \
            "$ref" "$id" "$s_name" "$host_label" "$win_label" "$p_cmd" \
            "up $(_humanize_seconds "$uptime_secs")" \
            "active $(_humanize_seconds "$age_secs") ago" \
            "${s_clients//,/, }"
    done
}

_jump_list_all() {
    (
        _jump_list_sessions
        _jump_list_remote_sessions $1
        _jump_list_tmuxinator_sessions
    ) |
    sort -r -n -t'|' -k1,1 |
    cut -d'|' -f2-
}

_jump_list_sessions() {
    local now
    now="$(date +%s)"

    tmux list-panes -a -f "#{&&:#{window_active},#{pane_active}}" \
        -F "$TMSP_SESSION_FMT" |
    _format_session_rows "$now" "" "" "pane_id" "" |
    sort -r -n -t'|' -k1,1
}

_jump_list_remote_sessions() {
    local now
    now="$(date +%s)"

    # Inside a managed SSH session: read the local machine's sessions directly
    # from the forwarded socket (fast, no SSH). Falls through to the SSH scan
    # below so other configured hosts are still discovered.
    local local_host=""
    if [[ -n "${TMSP_LOCAL_SOCKET:-}" ]]; then
        local_host=$(basename "$TMSP_LOCAL_SOCKET" | sed -E 's/-([0-9]+-)?tmux\.sock$//')

        # On macOS, tmux -S <forwarded-socket> hangs when stdout is a pipe but
        # exits normally when stdout is a regular file. Capture to a temp file
        # first to avoid the hang.
        local _socket_tmp
        _socket_tmp=$(mktemp)
        tmux -S "$TMSP_LOCAL_SOCKET" list-panes -a \
            -f "#{&&:#{window_active},#{pane_active}}" \
            -F "$TMSP_SESSION_FMT" \
            2>/dev/null > "$_socket_tmp"
        _format_session_rows "$now" "<- $local_host" "local:" "pane_id" "\e[0;32m" < "$_socket_tmp" |
        sort -r -n -t'|' -k1,1
        rm -f "$_socket_tmp"
    fi

    # Return cached SSH results for the remaining hosts; socket results above are always fresh.
    if (( ${1:-0} )); then
        [[ -s $REMOTE_SESSIONS_CACHE_PATH ]] && sed -E "/$local_host/d" $REMOTE_SESSIONS_CACHE_PATH
        return
    fi

    # Write to a per-run temp file in the same directory as the cache, then
    # atomically replace the cache with mv. Orphaned SSH jobs from a prior
    # interrupted run write to their own abandoned temp file and can't
    # contaminate this run's results.
    local _ssh_tmp
    _ssh_tmp=$(mktemp "${REMOTE_SESSIONS_CACHE_PATH}.XXXXXX")
    trap 'rm -f "$_ssh_tmp"' RETURN

    for host in $(_get_ssh_hosts); do
        [[ "$(hostname)" == "$host" ]] && continue
        # Skip the local machine — already enumerated via the forwarded socket above.
        [[ -n "$local_host" && "$local_host" == "$host" ]] && continue
        (
            ssh -o ConnectTimeout=3 \
                -o BatchMode=yes \
                "$host" \
                "tmux list-panes -a -f '#{&&:#{window_active},#{pane_active}}' \
                 -F '$TMSP_SESSION_FMT'" \
                2>/dev/null |
            _format_session_rows "$now" "-> $host" "remote:$host:" "session_name" "\e[0;33m" \
            >> "$_ssh_tmp"
        ) &
    done
    wait

    mv "$_ssh_tmp" "$REMOTE_SESSIONS_CACHE_PATH"
    sort -r -n -t'|' -k1,1 < "$REMOTE_SESSIONS_CACHE_PATH"
}

_jump_list_tmuxinator_sessions() {
    local enabled
    enabled=$(tmux show-option -gqv "@smart-pane-tmuxinator" 2>/dev/null)
    [[ "$enabled" != "on" ]] && return 0

    command -v tmuxinator &>/dev/null || return 0

    local open_sessions
    open_sessions=$(tmux list-sessions -F "#S" 2>/dev/null || true)

    tmuxinator list -n 2>/dev/null | tail -n +2 | awk '{print $1}' | \
    while IFS= read -r name; do
        printf '%s\n' "$open_sessions" | grep -qx "$name" && continue
        printf "%010d|tmuxinator:%s|\e[2m%-20.20s  (tmuxinator)\e[0m\n" \
            "0" "$name" "$name"
    done
}

_jump_list_panes() {
    local this_pane_id now
    this_pane_id="$(tmux display-message -p "#{pane_id}")"
    now="$(date +%s)"

    local fg_cmd_file
    fg_cmd_file="$(mktemp)"
    trap 'rm -f "$fg_cmd_file"' EXIT
    _tmux_fg_cmd_lines > "$fg_cmd_file"

    tmux list-panes -a -F "#{session_name}|#{window_index}|#{pane_index}|#{pane_current_command}|#{pane_tty}|#{pane_id}|#{@last_seen}" |
    while IFS=$'|' read -r s_name w_index p_index p_cmd p_tty p_id last_seen; do

        # Skip active pane
        (( $1 )) && [[ "$p_id" == "$this_pane_id" ]] && continue

        tty_short="${p_tty##*/}"
        p_proc=$(awk -F'\t' -v tty="$tty_short" '$1 == tty { print $2; exit }' "$fg_cmd_file")
        p_proc="${p_proc:-$p_cmd}"

        raw_age=99999999
        age="never"
        if [[ -n "${last_seen:-}" ]]; then
            raw_age=$((now - last_seen))
            (( raw_age < 0 )) && raw_age=0
            age="$(_humanize_seconds "$raw_age") ago"
        fi

        sort_key="${last_seen:-0}"

        printf "%010d|%s|%-15.15s  %3d:%-3d  %-20s  %.55s\n" \
            "$sort_key" "$p_id" "$s_name" "$w_index" "$p_index" "$age" "$p_proc"
    done |
    sort -r -n -t'|' -k1,1 |
    cut -d'|' -f2-
}


case "${1:-sessions}" in
    "all")                    _jump_list_all "$2" ;;
    "sessions")               _jump_list_sessions ;;
    "remote_sessions")        _jump_list_remote_sessions "$2" ;;
    "tmuxinator_sessions")    _jump_list_tmuxinator_sessions ;;
    "panes")                  _jump_list_panes "$2" ;;
    *)                        _jump_list_sessions ;;
esac
