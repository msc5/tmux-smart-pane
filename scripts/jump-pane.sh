#!/usr/bin/env bash
# Invoked via tmux display-popup (normal) or directly from connect-remote.sh
# (--standalone mode, where fzf runs in the bare terminal before re-attaching).
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUMP_LIST="$PLUGIN_DIR/scripts/jump-list.sh"
PREVIEW="$PLUGIN_DIR/scripts/preview.sh"
source "$PLUGIN_DIR/scripts/helpers.sh"

# In a managed SSH session: detach to trigger return to local tmux + picker.
if [[ -n "${TMSP_MANAGED:-}" ]]; then
    client=$(tmux display-message -p '#{client_name}' 2>/dev/null)
    tmux detach-client -t "$client"
    exit 0
fi

STANDALONE=0
FALLBACK_SESSION=""
if [[ "${1:-}" == --standalone ]]; then
    STANDALONE=1
    FALLBACK_SESSION="${2:-}"
fi

# Allocate a free port for fzf --listen. fzf starts with local-only sessions
# (sessions-fast) for instant display; a background job computes the full
# globally-sorted list (including SSH) and pushes it as a reload via the API.
# Requires fzf 0.36+ and python3. Falls back to blocking full load if unavailable.
_fzf_port=$(python3 -c \
    "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); p=s.getsockname()[1]; s.close(); print(p)" \
    2>/dev/null)
_sessions_tmp=$(mktemp)

_fzf_opts=()
if [[ -n "$_fzf_port" ]]; then
    _fzf_opts+=(--listen "127.0.0.1:$_fzf_port")
    _start_reload="$JUMP_LIST sessions-fast"
    (
        "$JUMP_LIST" sessions > "$_sessions_tmp"
        for _i in 1 2 3 4 5; do
            curl -s "http://127.0.0.1:$_fzf_port" \
                -d "reload(cat $_sessions_tmp)" 2>/dev/null && break
            sleep 0.1
        done
    ) &
    _bg_pid=$!
else
    _start_reload="$JUMP_LIST sessions"
fi

_cleanup() {
    [[ -n "${_bg_pid:-}" ]] && kill "$_bg_pid" 2>/dev/null || true
    rm -f "$_sessions_tmp"
}
trap _cleanup EXIT

# When toggling back to sessions, serve the cached temp file (already sorted)
# rather than re-running SSH.
TOGGLE_ACTION="transform:case \"\$FZF_PROMPT\" in sessions*) echo \"change-prompt(panes ❯ )+reload($JUMP_LIST panes)\";; *) echo \"change-prompt(sessions ❯ )+reload(cat $_sessions_tmp 2>/dev/null || $JUMP_LIST sessions)\";; esac"

selected=$(
    fzf "${_fzf_opts[@]}" \
        --delimiter='|' \
        --with-nth=2.. \
        --layout=reverse \
        --highlight-line \
        --header 'ctrl-l: toggle sessions / panes' \
        --preview-window 'bottom,70%' \
        --preview-label ' Preview ' \
        --preview "$PREVIEW {1}" \
        --bind "start:reload($_start_reload)" \
        --bind "ctrl-l:$TOGGLE_ACTION" \
        < /dev/null
)

p_id="${selected%%|*}"

if [[ -z "$p_id" ]]; then
    (( STANDALONE )) && exec tmux attach-session -t "$FALLBACK_SESSION"
    exit 0
fi

if [[ "$p_id" == remote:* ]]; then
    rest="${p_id#remote:}"
    if (( STANDALONE )); then
        exec "$PLUGIN_DIR/scripts/connect-remote.sh" \
            "${rest%%:*}" "${rest#*:}" "$FALLBACK_SESSION" "$PLUGIN_DIR"
    else
        _remote_jump "${rest%%:*}" "${rest#*:}"
    fi
else
    if (( STANDALONE )); then
        target_sess=$(tmux list-panes -a \
            -F "#{pane_id}|#{session_name}" 2>/dev/null | \
            awk -F'|' -v id="$p_id" '$1==id{print $2;exit}')
        exec tmux attach-session -t "${target_sess:-$FALLBACK_SESSION}" \
            ';' select-pane -t "$p_id"
    else
        tmux switch-client -t "$p_id"
        tmux select-pane -t "$p_id"
    fi
fi
