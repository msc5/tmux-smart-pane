# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A tmux plugin (bash) that provides fzf-powered pane swapping and a session/pane jump picker. No build system, no test suite — changes are tested by reloading tmux.

## Development workflow

Reload the plugin after changes:
```
tmux source ~/.config/tmux/tmux.conf   # or your tmux.conf path
```

Test a script directly (must be run inside a tmux session):
```bash
bash scripts/jump-list.sh sessions
bash scripts/jump-list.sh panes
```

Requirements: tmux 3.2+, fzf, bash 4+ (macOS ships bash 3 — use `/opt/homebrew/bin/bash`).

## Architecture

**Entry point** — `tmux-smart-pane.tmux`  
Sets up the `pane-focus-in` hook (writes `@last_seen` unix timestamp as a pane option), reads config options, and registers all keybindings. Also configures the pass-through lock mode (`M-=` by default) that disables the outer prefix so keystrokes flow to a nested tmux session.

**`scripts/helpers.sh`** — sourced by all other scripts, never executed directly.  
Key functions:
- `_humanize_seconds` — formats a duration for display
- `_tmux_fg_cmd_lines` — single `ps` pass to map `tty → foreground command` for all panes
- `_remote_jump host session` — detaches local tmux client, hands the terminal to `connect-remote.sh` via `tmux detach-client -E`
- `_store_swap_pane src_pane` — reads target pane from stdin, persists swap to cache, executes `tmux swap-pane`

**`scripts/connect-remote.sh`** — runs outside tmux (in the bare terminal after `detach-client -E`).  
Establishes SSH with ControlMaster + reverse socket, sets `TMUX_LOCAL_SOCKET` and `TMUX_LOCAL_PLUGIN_DIR` in the remote tmux environment, waits for SSH to exit, then re-attaches to local tmux. If the remote signalled `TMSP_RETURN_PICKER=1` (set via back-channel when user pressed `C-b+s`), installs a one-shot `client-attached` hook to open the picker immediately on re-attach.

**Remote back-channel** — the reverse-forwarded Unix socket (`-R /tmp/tmsp-UID-HOST.sock:$local_tmux_sock`) lets the remote machine communicate with the local tmux server. Used minimally: remote `jump-pane.sh` calls `TMUX=$TMUX_LOCAL_SOCKET tmux set-environment TMSP_RETURN_PICKER 1` to signal that the picker should open on return. Requires `AllowStreamLocalForwarding yes` on the remote sshd (usually default) and `StreamLocalBindUnlink yes` for clean socket cleanup on disconnect.

**ControlMaster sockets** — stored at `~/.local/share/tmux-smart-pane/ctrl/<host>.sock` with `ControlPersist=60m`. Used by `connect-remote.sh`, `jump-list.sh` (fast remote session queries), and `preview.sh` (remote capture-pane).

**Recency tracking for remote sessions** — stored at `~/.local/share/tmux-smart-pane/ctrl/<host>:<session>.last` (unix timestamp written by `connect-remote.sh` on each connection). `jump-list.sh` reads these to sort remote sessions by when they were last visited locally.

**Cache** — a bash `declare -A CACHE` file at `~/.local/share/tmux-smart-pane/cache.sh` (overridable via `@smart-pane-cache-path`). Currently only stores `CACHE[swap-pane]="src:target"` for undo.

**Data flow through fzf pickers**  
`jump-list.sh` emits rows in the internal format `<sort_key>|<id>|<display>`, sorts on `k1`, then strips the sort key with `cut -d'|' -f2-` before handing rows to fzf. fzf is configured with `--delimiter='|' --with-nth=2..` so only the display column is visible. The selected line is split on `|` to recover the `pane_id`.

Remote session IDs use the prefix `remote:<host>:<session>` throughout the pipeline; `jump-pane.sh`, `preview.sh`, and `connect-remote.sh` all check for this prefix to route differently.

**Script responsibilities**

| Script | Role |
|---|---|
| `jump-list.sh sessions` | Local sessions + remote sessions via parallel SSH (ControlMaster) |
| `jump-list.sh panes` | All panes except current, sorted by `@last_seen` recency |
| `jump-pane.sh` | Full-screen fzf popup; `Ctrl-L` toggles sessions ↔ panes. If `$TMUX_LOCAL_SOCKET` is set and valid, signals local and exits SSH instead of showing fzf |
| `connect-remote.sh` | Runs outside tmux; manages SSH lifecycle and local re-attach |
| `pick-pane.sh` | Thin fzf wrapper — reads `id\|display` from stdin, prints selected id |
| `swap-pane.sh` | Pipes `jump-list panes → pick-pane → _store_swap_pane` |
| `undo-swap-pane.sh` | Reads cache, reverses the stored swap pair |
| `preview.sh` | `tmux capture-pane` for local panes; SSH capture via ControlMaster for remote |
