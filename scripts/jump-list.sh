#!/usr/bin/env bash
# Generates row listings consumed by jump-session.sh and jump-pane.sh
# Each row: <sort_key>|<pane_id>|<display>
#
# Usage:
#   jump-list.sh sessions   — one row per session (default)
#   jump-list.sh panes      — one row per pane, sorted by @last_seen recency
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

_jump_list_all() {
    (
        _jump_list_sessions
        _jump_list_remote_sessions $1
    ) |
    sort -r -n -t'|' -k1,1 |
    cut -d'|' -f2-
}

_jump_list_sessions() {
    local now
    now="$(date +%s)"

    # Local sessions — sorted and flushed immediately.
    tmux list-panes -a -f "#{&&:#{window_active},#{pane_active}}" \
        -F "#{session_last_attached}|#{session_created}|#{session_name}|#{session_windows}|#{session_attached_list}|#{pane_current_command}|#{pane_id}|#{@last_seen}" |
    while IFS=$'|' read -r s_last_attached s_created s_name s_windows s_clients p_cmd p_id p_last_seen; do

        local uptime_secs=$((now - s_created))
        (( uptime_secs < 0 )) && uptime_secs=0
        local uptime_disp="up $(_humanize_seconds "$uptime_secs")"

        local ref_time="${p_last_seen:-0}"
        (( ref_time == 0 )) && ref_time="${s_last_attached:-0}"
        (( ref_time == 0 )) && ref_time="$s_created"
        local age_secs=$((now - ref_time))
        (( age_secs < 0 )) && age_secs=0
        local age_disp="active $(_humanize_seconds "$age_secs") ago"

        local win_label="$s_windows window"
        (( s_windows != 1 )) && win_label="$s_windows windows"

        printf "%010d|%s|%-20.20s  %-15s  %-11s  %-30s  %-26.26s  %-26.26s  %-30s\n" \
            "$ref_time" "$p_id" "$s_name" "" "$win_label" "$p_cmd" \
            "$uptime_disp" "$age_disp" "$s_clients"
    done | 
    sort -r -n -t'|' -k1,1
}

_jump_list_remote_sessions() {

    # Return cache if one exists, otherwise exit immediately
    if (( $1 )); then
        [[ -s $REMOTE_SESSIONS_CACHE_PATH ]] && cat $REMOTE_SESSIONS_CACHE_PATH 
        return
    fi

    touch $REMOTE_SESSIONS_CACHE_PATH
    echo "" > $REMOTE_SESSIONS_CACHE_PATH

    now="$(date +%s)"

    # @smart-pane-ssh-hosts overrides auto-discovery; if unset, parse ~/.ssh/config.
    local hosts_opt
    hosts_opt=$(tmux show-option -gqv "@smart-pane-ssh-hosts" 2>/dev/null)

    local hosts=()
    if [[ -n "$hosts_opt" ]]; then
        read -ra hosts <<< "$hosts_opt"
    else
        local ssh_hosts
        ssh_hosts=$(grep -E '^Host[[:space:]]+' ~/.ssh/config 2>/dev/null \
            | grep -v -e '\*' -e 'github' | awk '{print $2}')
        [[ -z "$ssh_hosts" ]] && return 0
        while IFS= read -r h; do
            hosts+=("$h")
        done <<< "$ssh_hosts"
    fi

    [[ ${#hosts[@]} -eq 0 ]] && return 0

    for host in "${hosts[@]}"; do
        (
            ssh -o ConnectTimeout=3 \
                -o BatchMode=yes \
                "$host" \
                "tmux list-panes -a -f '#{&&:#{window_active},#{pane_active}}' \
                 -F '#{session_last_attached}|#{session_created}|#{session_name}|#{session_windows}|#{@last_seen}'" \
                2>/dev/null |
            while IFS='|' read -r s_last s_created s_name s_windows p_last_seen; do
                # Sort and display age by @last_seen; fall back to session_last_attached.
                ref="${p_last_seen:-0}"
                (( ref == 0 )) && ref="${s_last:-0}"
                (( ref == 0 )) && ref="$s_created"
                sort_key=$ref
                age_secs=$((now - ref))
                (( sort_key < 0 )) && sort_key=0
                age_disp="active $(_humanize_seconds "$age_secs") ago"

                uptime_secs=$((now - s_created))
                (( uptime_secs < 0 )) && uptime_secs=0
                uptime_disp="up $(_humanize_seconds "$uptime_secs")"

                win_label="$s_windows window"
                (( s_windows != 1 )) && win_label="$s_windows windows"

                printf "%010d|remote:%s:%s|%-20.20s  @%-14.14s  %-11s  %30s  %-26.26s  %-26.26s\n" \
                    "$sort_key" "$host" "$s_name" "$s_name" "$host" "$win_label" "" \
                    "$uptime_disp" "$age_disp"
            done >> $REMOTE_SESSIONS_CACHE_PATH
        ) &
    done
    wait

    cat $REMOTE_SESSIONS_CACHE_PATH | sort -r -n -t'|' -k1,1
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
    all)                _jump_list_all "$2" ;;
    sessions)           _jump_list_sessions ;;
    remote_sessions)    _jump_list_remote_sessions "$2" ;;
    panes)              _jump_list_panes "$2" ;;
    *)                  _jump_list_sessions ;;
esac
