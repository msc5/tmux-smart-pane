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

    # One row per session: uses the active pane of the active window as the
    # jump target. Avoids the ps cost since the pane picker handles that.
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

        printf "%020d|%s|%-20.20s  %-11s  %-30s  %-26.26s  %-26.26s  %-30s\n" \
            "$age_secs" "$p_id" "$s_name" "$win_label" "$p_cmd" \
            "$uptime_disp" "$age_disp" "$s_clients"
    done |
    sort -n -t'|' -k1,1 |
    cut -d'|' -f2-
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
    tmux has-session -t "remote" 2>/dev/null || return 0

    local ssh_hosts remote_windows hosts=()
    ssh_hosts=$(grep -E '^Host[[:space:]]+' ~/.ssh/config 2>/dev/null \
        | grep -v -e '\*' -e 'github' | awk '{print $2}')
    remote_windows=$(tmux list-windows -t "remote" -F "#{window_name}" 2>/dev/null)

    while IFS= read -r win; do
        echo "$ssh_hosts" | grep -qx "$win" && hosts+=("$win")
    done <<< "$remote_windows"

    [[ ${#hosts[@]} -eq 0 ]] && return 0

    local now
    now="$(date +%s)"

    for host in "${hosts[@]}"; do
        (
            ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" \
                "tmux list-panes -a -f '#{&&:#{window_active},#{pane_active}}' \
                 -F '#{session_last_attached}|#{session_created}|#{session_name}|#{session_windows}'" \
                2>/dev/null |
            while IFS='|' read -r s_last s_created s_name s_windows; do
                local uptime_secs=$((now - s_created))
                (( uptime_secs < 0 )) && uptime_secs=0
                local uptime_disp="up $(_humanize_seconds "$uptime_secs")"

                local ref_time="${s_last:-0}"
                (( ref_time == 0 )) && ref_time="$s_created"
                local age_secs=$((now - ref_time))
                (( age_secs < 0 )) && age_secs=0
                local age_disp="active $(_humanize_seconds "$age_secs") ago"

                local win_label="$s_windows window"
                (( s_windows != 1 )) && win_label="$s_windows windows"

                printf "remote:%s:%s|%-20.20s  @%-14.14s  %-11s  %-26.26s  %-26.26s\n" \
                    "$host" "$s_name" "$s_name" "$host" "$win_label" \
                    "$uptime_disp" "$age_disp"
            done
        ) &
    done
    wait
}

case "${1:-sessions}" in
    panes)    _jump_list_panes ;;
    sessions) _jump_list_sessions; _jump_list_remote_sessions ;;
    *)        _jump_list_sessions; _jump_list_remote_sessions ;;
esac
