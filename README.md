# tmux-smart-pane

fzf-powered pane navigation and **remote session management** for tmux. Jump to any local or remote session, swap panes by recency, and connect to SSH hosts without ever leaving your terminal workflow.

## Demo
https://github.com/user-attachments/assets/b66c4c9c-c056-4cd0-b7ab-998d68678479

## Why this plugin?

Managing remote tmux sessions normally means nesting tmux inside tmux — with all the keybinding conflicts and visual overhead that implies. tmux-smart-pane makes remote sessions first-class citizens: the same fzf picker you use for local sessions lists every tmux session on every configured SSH host. Pick one, and you're there; press `prefix + s` again and you're back home.

## Features

- **Session jump** (`prefix + s`) — fzf picker showing local and remote sessions sorted by recency; remote sessions appear alongside local ones and connect via SSH automatically
- **Pane jump / swap** (`prefix + p`) — fzf picker showing all panes sorted by `@last_seen`; press `Enter` to jump, `Tab` to swap the current pane with the selection
- **Undo swap** (`prefix + P`) — reverses the last pane swap (acts as a toggle)
- **Nested-tmux passthrough** (`M-=`) — toggle key-forwarding mode so keystrokes flow through to a nested session without prefix conflicts

## Requirements

- tmux 3.2+
- fzf
- bash 4+ (macOS ships bash 3; install via `brew install bash`)

## Installation

### With TPM

```
set -g @plugin 'msc5/tmux-smart-pane'
```

Run `<prefix> I` to install.

### Manual

```bash
git clone https://github.com/msc5/tmux-smart-pane ~/.config/tmux/plugins/tmux-smart-pane
```

Add to `tmux.conf` **before** the TPM `run` line:

```
run "~/.config/tmux/plugins/tmux-smart-pane/tmux-smart-pane.tmux"
```

Reload: `tmux source ~/.config/tmux/tmux.conf`

## Configuration

Set options in `tmux.conf` **before** the `run` line:

| Option | Default | Description |
|---|---|---|
| `@smart-pane-jump-session-key` | `s` | Open session / remote-session picker |
| `@smart-pane-jump-pane-key` | `p` | Open pane jump / swap picker |
| `@smart-pane-undo-swap-key` | `P` | Undo last pane swap |
| `@smart-pane-lock-key` | `M-=` | Toggle nested-tmux passthrough |
| `@smart-pane-cache-path` | `~/.local/share/tmux-smart-pane/cache.sh` | Swap-history cache file |
| `@smart-pane-ssh-hosts` | _(auto)_ | Space-separated list of SSH hosts to query for remote sessions; if unset, hosts are read from `~/.ssh/config` |

Example:

```
set -g @smart-pane-jump-session-key "w"
run "~/.config/tmux/plugins/tmux-smart-pane/tmux-smart-pane.tmux"
```

## Keybindings

### Session picker (`prefix + s`)

| Key | Action |
|---|---|
| `Enter` | Switch to session / connect to remote session |
| `Esc` / `Ctrl-C` | Cancel |

### Pane picker (`prefix + p`)

| Key | Action |
|---|---|
| `Enter` | Jump to pane |
| `Tab` | Swap current pane with selection and record to undo cache |
| `Esc` / `Ctrl-C` | Cancel |

### Passthrough mode

`M-=` (no prefix needed) toggles key-forwarding for nested tmux sessions. All keys — including your tmux prefix — pass through to the inner session. Press `M-=` again to restore normal keybindings.

## SSH Setup

These are suggested settings for target hosts in order to improve connection speed and cold-startup time. The most important is to configure SSH ControlMaster so that picker queries and session connections reuse an existing authenticated channel rather than opening a new one each time. These settings should be added to `~/.ssh/config`:

```
Host *
    ControlMaster auto
    ControlPath ~/.ssh/ssh-%r@%h:%p
    ControlPersist 60m
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

**Explanation of SSH config options:**

- `ControlMaster auto` + `ControlPath` — multiplexes subsequent connections over an existing socket; connecting to a remote session is near-instant after the first open
- `ControlPersist 60m` — keeps the socket alive for 60 minutes after the last session ends, so re-connecting stays fast
- `ServerAliveInterval` / `ServerAliveCountMax` — sends keepalives and drops the connection after 90 seconds of silence, preventing stale sockets from blocking future connects

**Remote sshd (`/etc/ssh/sshd_config`):**

```
AllowStreamLocalForwarding yes
StreamLocalBindUnlink yes
```

`AllowStreamLocalForwarding yes` is the default on most distros. `StreamLocalBindUnlink yes` lets SSH automatically remove a stale reverse-socket file on reconnect, avoiding `Address already in use` errors if a previous session exited uncleanly.

## Remote sessions in the picker

Remote sessions are discovered by querying `tmux list-panes` over SSH for every `Host` entry in `~/.ssh/config` (excluding wildcards and `github`). Results are fetched in parallel and cached for the duration of the picker. Sessions are sorted alongside local sessions by recency — the last time you visited a remote session is tracked locally in `~/.local/share/tmux-smart-pane/`.

If a host is unreachable, it is silently skipped (3-second connect timeout, `BatchMode yes`).
