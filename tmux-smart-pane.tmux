#!/usr/bin/env bash
# TPM plugin entry point. Sets up the @last_seen hook and keybindings.
# Override keys in tmux.conf before this run line (see README).
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

_get_opt() {
    local val
    val=$(tmux show-option -gqv "$1" 2>/dev/null)
    echo "${val:-$2}"
}

tmux set-option -g focus-events on
tmux set-hook -g pane-focus-in \
    'run-shell "tmux set-option -p -t #{pane_id} @last_seen $(date +%s)"'

UNDO_KEY=$(_get_opt "@smart-pane-undo-swap-key" "P")
JUMP_SESSION_KEY=$(_get_opt "@smart-pane-jump-session-key" "s")
JUMP_PANE_KEY=$(_get_opt "@smart-pane-jump-pane-key" "p")

# Keep the debug log bounded: trim to the most recent lines once it passes ~1 MB.
if [[ -f "$SMART_PANE_LOG" ]] && (( $(wc -c < "$SMART_PANE_LOG") > 1048576 )); then
    tail -n 5000 "$SMART_PANE_LOG" > "$SMART_PANE_LOG.tmp" && mv "$SMART_PANE_LOG.tmp" "$SMART_PANE_LOG"
fi
_log info "plugin loaded from $CURRENT_DIR (tmux $(tmux -V | cut -d' ' -f2), log level $TMSP_LOG_LEVEL)"

# `prefix + :smart-pane-report` — shows the debug report and copies it to the
# tmux buffer/clipboard. Reuses its existing slot so re-sourcing doesn't duplicate it.
_report_alias="smart-pane-report=display-popup -w 90% -h 90% -E '$CURRENT_DIR/scripts/debug-report.sh --pager'"
_report_idx=$(tmux show-options -s command-alias 2>/dev/null |
    awk -F'[][]' '/smart-pane-report=/ { print $2; exit }')
if [[ -n "$_report_idx" ]]; then
    tmux set-option -s "command-alias[$_report_idx]" "$_report_alias"
else
    tmux set-option -sa command-alias "$_report_alias"
fi

tmux bind "$UNDO_KEY" run-shell \
    "$CURRENT_DIR/scripts/undo-swap-pane.sh"
tmux bind "$JUMP_SESSION_KEY" display-popup -w "100%" -h "100%" -b none \
    -E "$CURRENT_DIR/scripts/jump-session.sh"
tmux bind "$JUMP_PANE_KEY" display-popup -w "100%" -h "100%" -b none \
    -E "$CURRENT_DIR/scripts/jump-pane.sh"
