#!/usr/bin/env bash
# Generates row listings consumed by jump-pane.sh and swap-pane.sh.
# Each row: <sort_key>|<pane_id>|<display>
#
# Usage:
#   jump-list.sh sessions   — one row per session (default)
#   jump-list.sh panes      — one row per pane, sorted by @last_seen recency
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PLUGIN_DIR/scripts/helpers.sh"

_jump_list_sessions() {
    local now
    now="$(date +%s)"

    # Local sessions — sorted and flushed immediately.
    tmux list-panes -a -f "#{&&:#{window_active},#{pane_active}}" \
        -F "#{session_last_attached}|#{session_created}|#{session_name}|#{session_windows}|#{session_attached_list}|#{pane_current_command}|#{pane_id}" |
    while IFS=$'|' read -r s_last_attached s_created s_name s_windows s_clients p_cmd p_id; do

        local uptime_secs=$((now - s_created))
        (( uptime_secs < 0 )) && uptime_secs=0
        local uptime_disp="up $(_humanize_seconds "$uptime_secs")"

        local ref_time="${s_last_attached:-0}"
        (( ref_time == 0 )) && ref_time="$s_created"
        local age_secs=$((now - ref_time))
        (( age_secs < 0 )) && age_secs=0
        local age_disp="active $(_humanize_seconds "$age_secs") ago"

        local win_label="$s_windows window"
        (( s_windows != 1 )) && win_label="$s_windows windows"

        printf "%020d|%s|%-20.20s  %-15s  %-11s  %-30s  %-26.26s  %-26.26s  %-30s\n" \
            "$age_secs" "$p_id" "$s_name" "" "$win_label" "$p_cmd" \
            "$uptime_disp" "$age_disp" "$s_clients"
    done | sort -n -t'|' -k1,1 | cut -d'|' -f2-

    # Remote sessions — stream in as each SSH call completes; sorted per-host by
    # local @last_seen. Appends below local sessions without blocking them.
    _jump_list_remote_sessions "$now"
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
        [[ "$p_id" == "$this_pane_id" ]] && continue

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

        printf "%08d|%s|%-15.15s  %3d:%-3d  %-20s  %.55s\n" \
            "$raw_age" "$p_id" "$s_name" "$w_index" "$p_index" "$age" "$p_proc"
    done |
    sort -n -t'|' -k1,1 |
    cut -d'|' -f2-
}

_jump_list_remote_sessions() {
    local now="$1"

    local ssh_hosts
    ssh_hosts=$(grep -E '^Host[[:space:]]+' ~/.ssh/config 2>/dev/null \
        | grep -v -e '\*' -e 'github' | awk '{print $2}')

    [[ -z "$ssh_hosts" ]] && return 0

    local hosts=()
    while IFS= read -r h; do
        hosts+=("$h")
    done <<< "$ssh_hosts"

    for host in "${hosts[@]}"; do
        (
            ctrl_sock="$SMART_PANE_CTRL_DIR/${host}.sock"
            ssh -o ControlMaster=auto \
                -o "ControlPath=${ctrl_sock}" \
                -o ControlPersist=60m \
                -o ConnectTimeout=3 \
                -o BatchMode=yes \
                "$host" \
                "tmux list-panes -a -f '#{&&:#{window_active},#{pane_active}}' \
                 -F '#{session_last_attached}|#{session_created}|#{session_name}|#{session_windows}'" \
                2>/dev/null |
            while IFS='|' read -r s_last s_created s_name s_windows; do
                # Sort by when we last connected to this remote session locally.
                last_file="$SMART_PANE_CTRL_DIR/${host}:${s_name}.last"
                if [[ -f "$last_file" ]]; then
                    local_last=$(cat "$last_file")
                    if [[ "$local_last" =~ ^[0-9]+$ ]]; then
                        sort_key=$((now - local_last))
                    else
                        sort_key=99999999
                    fi
                else
                    sort_key=99999999
                fi

                uptime_secs=$((now - s_created))
                (( uptime_secs < 0 )) && uptime_secs=0
                uptime_disp="up $(_humanize_seconds "$uptime_secs")"

                ref_time="${s_last:-0}"
                (( ref_time == 0 )) && ref_time="$s_created"
                age_secs=$((now - ref_time))
                (( age_secs < 0 )) && age_secs=0
                age_disp="active $(_humanize_seconds "$age_secs") ago"

                win_label="$s_windows window"
                (( s_windows != 1 )) && win_label="$s_windows windows"

                printf "%020d|remote:%s:%s|%-20.20s  @%-14.14s  %-11s  %30s  %-26.26s  %-26.26s\n" \
                    "$sort_key" "$host" "$s_name" "$s_name" "$host" "$win_label" "" \
                    "$uptime_disp" "$age_disp"
            done | sort -n -t'|' -k1,1 | cut -d'|' -f2-
        ) &
    done
    wait
}

case "${1:-sessions}" in
    panes)    _jump_list_panes ;;
    sessions) _jump_list_sessions ;;
    *)        _jump_list_sessions ;;
esac
