#!/usr/bin/env bash
# Collects environment, configuration, SSH, and recent log output into a
# report suitable for pasting into a GitHub issue.
#
# Usage: debug-report.sh [--pager] [--no-remote] [--lines N]
#   --pager      show the report in less (used by `prefix + :smart-pane-report`)
#   --no-remote  skip probing SSH hosts
#   --lines N    number of log lines to include (default 200)
#
# The report is also saved to <base path>/debug-report.txt and loaded into the
# tmux buffer "smart-pane-report" (and the clipboard, if set-clipboard allows).

# Read the configured level for display, but keep this script itself out of the log.
configured_level=$(tmux show-option -gqv "@smart-pane-log-level" 2>/dev/null)
TMSP_LOG_LEVEL=off
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

PAGER_MODE=0
PROBE_REMOTE=1
LOG_LINES=200
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pager)     PAGER_MODE=1; shift ;;
        --no-remote) PROBE_REMOTE=0; shift ;;
        --lines)     LOG_LINES="$2"; shift 2 ;;
        *)           echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

REPORT_PATH="${SMART_PANE_BASE_PATH%/}/debug-report.txt"

_section() { printf '\n## %s\n\n' "$1"; }
_kv()      { printf '%-22s %s\n' "$1:" "$2"; }
_first()   { "$@" 2>&1 | head -n 1; }
_or_none() { local out; out=$(cat); printf '%s\n' "${out:-(none)}"; }

_probe_host() {
    local host="$1"
    echo "### $host$([[ "$(hostname)" == "$host" ]] && echo ' (this machine; skipped by the picker)')"
    ssh -G "$host" 2>&1 |
        grep -E '^(hostname|user|port|controlmaster|controlpath|controlpersist|connecttimeout) ' |
        sed 's/^/    /'
    echo "    master check: $(ssh -O check "$host" 2>&1 | head -n 1)"

    local start=$SECONDS out rc
    out=$(ssh -o ConnectTimeout=3 -o BatchMode=yes "$host" \
        'echo "tmux=$(tmux -V 2>&1)"; echo "sessions=$(tmux list-sessions 2>/dev/null | wc -l)"; echo "plugin_keys=$(tmux list-keys 2>/dev/null | grep -c tmux-smart-pane)"; echo "log_level=$(tmux show-option -gqv @smart-pane-log-level 2>/dev/null)"' 2>&1)
    rc=$?
    echo "    probe: exit $rc in $((SECONDS - start))s"
    printf '%s\n' "$out" | sed 's/^/    /'
    echo
}

_report() {
    echo "# tmux-smart-pane debug report"
    echo
    echo "Generated $(date '+%F %T %Z'). Review before sharing: this includes"
    echo "hostnames, usernames, paths, and session names from your setup."

    _section "Plugin"
    _kv "path" "$PLUGIN_DIR"
    if git -C "$PLUGIN_DIR" rev-parse --git-dir &>/dev/null; then
        _kv "commit" "$(git -C "$PLUGIN_DIR" log -1 --format='%h %cs %s' 2>/dev/null)"
        _kv "branch" "$(git -C "$PLUGIN_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        _kv "local changes" "$(git -C "$PLUGIN_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ') files"
    else
        _kv "commit" "(not a git checkout)"
    fi

    _section "Versions"
    _kv "os" "$(uname -srm)"
    command -v sw_vers &>/dev/null && _kv "macos" "$(sw_vers -productVersion)"
    _kv "tmux" "$(_first tmux -V)"
    _kv "fzf" "$(_first fzf --version)"
    _kv "bash (running)" "$BASH_VERSION ($BASH)"
    _kv "bash (on PATH)" "$(command -v bash)"
    _kv "ssh" "$(_first ssh -V)"
    _kv "sed" "$(sed --version 2>/dev/null | grep -q GNU && echo GNU || echo BSD)"
    _kv "tmuxinator" "$(command -v tmuxinator || echo '(not found)')"
    _kv "bat" "$(command -v bat || command -v batcat || echo '(not found)')"

    _section "tmux"
    _kv "inside tmux" "$([[ -n "${TMUX:-}" ]] && echo yes || echo no)"
    _kv "socket" "$(tmux display-message -p '#{socket_path}' 2>/dev/null || echo '(no server)')"
    _kv "focus-events" "$(tmux show-option -gqv focus-events 2>/dev/null)"
    _kv "default-shell" "$(tmux show-option -gqv default-shell 2>/dev/null)"
    _kv "set-clipboard" "$(tmux show-option -gqv set-clipboard 2>/dev/null)"
    _kv "PATH (tmux global)" "$(tmux show-environment -g PATH 2>/dev/null | cut -d= -f2-)"
    echo
    echo "Plugin options:"
    tmux show-options -g 2>/dev/null | grep '^@smart-pane' | sed 's/^/    /' | _or_none
    echo "Plugin environment (tmux global):"
    tmux show-environment -g 2>/dev/null | grep '^-\{0,1\}TMSP_' | sed 's/^/    /' | _or_none
    echo "Plugin environment (this process):"
    env | grep '^TMSP_' | grep -v '^TMSP_LOG_LEVEL=' | sed 's/^/    /' | _or_none
    echo "Key bindings:"
    tmux list-keys 2>/dev/null | grep -F "$PLUGIN_DIR" | sed -e "s|$PLUGIN_DIR|<plugin>|g" -e 's/^/    /' | _or_none
    echo "pane-focus-in hook:"
    tmux show-hooks -g pane-focus-in 2>/dev/null | sed 's/^/    /' | _or_none

    _section "Cache"
    _kv "base path" "$SMART_PANE_BASE_PATH"
    _kv "swap cache" "$SMART_PANE_CACHE ($( [[ -f $SMART_PANE_CACHE ]] && echo present || echo missing))"
    if [[ -f "$REMOTE_SESSIONS_CACHE_PATH" ]]; then
        _kv "remote cache" "$REMOTE_SESSIONS_CACHE_PATH ($(wc -l < "$REMOTE_SESSIONS_CACHE_PATH" | tr -d ' ') rows)"
        cut -d'|' -f2 "$REMOTE_SESSIONS_CACHE_PATH" | sed 's/^/    /'
    else
        _kv "remote cache" "$REMOTE_SESSIONS_CACHE_PATH (missing)"
    fi
    _kv "orphaned temp files" "$(find "$(dirname "$REMOTE_SESSIONS_CACHE_PATH")" -maxdepth 1 \
        -name "$(basename "$REMOTE_SESSIONS_CACHE_PATH").??????" 2>/dev/null | wc -l | tr -d ' ')"

    _section "SSH"
    local hosts
    hosts=$(_get_ssh_hosts)
    _kv "hosts" "${hosts:-(none)}"
    _kv "hosts source" "$( [[ -n $(tmux show-option -gqv @smart-pane-ssh-hosts 2>/dev/null) ]] && echo @smart-pane-ssh-hosts || echo '~/.ssh/config')"
    echo
    if (( PROBE_REMOTE )) && [[ -n "$hosts" ]]; then
        # Probe in parallel, then print in a stable order.
        local tmpdir host i=0
        tmpdir=$(mktemp -d)
        for host in $hosts; do
            _probe_host "$host" > "$tmpdir/$(printf '%03d' $i)" &
            i=$((i + 1))
        done
        wait
        cat "$tmpdir"/* 2>/dev/null
        rm -rf "$tmpdir"
    elif (( ! PROBE_REMOTE )); then
        echo "(remote probe skipped)"
    fi

    _section "Log"
    _kv "level" "${configured_level:-off}"
    _kv "path" "$SMART_PANE_LOG"
    if [[ -f "$SMART_PANE_LOG" ]]; then
        _kv "size" "$(wc -c < "$SMART_PANE_LOG" | tr -d ' ') bytes"
        echo
        echo "Last $LOG_LINES lines:"
        echo '```'
        tail -n "$LOG_LINES" "$SMART_PANE_LOG"
        echo '```'
    else
        echo
        echo "(no log file — set @smart-pane-log-level to debug, reproduce the issue, then re-run)"
    fi
}

mkdir -p "$(dirname "$REPORT_PATH")"
_report > "$REPORT_PATH"

copied=""
if tmux load-buffer -w -b smart-pane-report "$REPORT_PATH" 2>/dev/null ||
    tmux load-buffer -b smart-pane-report "$REPORT_PATH" 2>/dev/null; then
    copied=" and copied to tmux buffer 'smart-pane-report'"
fi
footer="Report saved to $REPORT_PATH$copied."

if (( PAGER_MODE )); then
    { echo "$footer (q to close)"; echo; cat "$REPORT_PATH"; } | less
else
    cat "$REPORT_PATH"
    echo >&2
    echo "$footer" >&2
fi
