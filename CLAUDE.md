# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**IMPORTANT: Keep this file up to date. Whenever you add, remove, rename, or restructure configs in this repo, update CLAUDE.md to reflect the change in the same commit.**

## Overview

Personal dotfiles repo managing configs across two machines:
- **Arch Linux PC** (primary, sway/Wayland) — AMD 7600X, RTX 4070 Super
- **MacBook** (macOS, Aerospace WM) — Apple M3 Pro

Configs are symlinked from `~/.dotfiles/` into their expected locations (e.g., `~/.config/nvim`, `~/.config/kitty`, `~/.config/sway`).

### Install Script

`install.sh` — cross-platform installer (Arch, Ubuntu/Debian, macOS). Auto-detects platform and headless vs desktop. Handles package installation, plugin manager bootstrapping (Antidote, TPM), gitmux binary download, Nerd Font setup, symlinks, and default shell change. Flags: `--all`, `--core`, `--desktop`, `--symlinks`, `--no-fonts`. Idempotent — safe to re-run.

## Architecture

### Zsh (split config)

The shell config is split into shared + platform-specific files:
- `.zshrc` — shared config sourced on all machines (PATH, aliases, plugins, prompt, keybinds)
- `zsh/zshrc.darwin` — macOS: Homebrew, pnpm, XQuartz paths
- `zsh/zshrc.linux` — Arch: miniconda, pyenv, vapi paths

Platform dispatch in `.zshrc` uses `uname -s`. Machine-local overrides go in `~/.zshrc.local` (gitignored).

Plugin manager: **Antidote** (sourced from `~/.antidote/antidote.zsh`). Plugins listed in `.zsh_plugins.txt`.

Shell startup auto-pulls this repo in the background (`git pull --ff-only`).

`precmd` sets the terminal title (OSC 2) to the cwd for tmux `pane_title` display (works through SSH). An `ssh()` wrapper function auto-labels tmux windows and the `@pane_host` pane option with the SSH target hostname; on exit, it restores `automatic-rename` and the local hostname. First tmux session is named after the hostname; subsequent sessions auto-number.

### Neovim

Standard lazy.nvim structure:
- `nvim/init.lua` → loads `config.lazy`
- `nvim/lua/config/` — `lazy.lua` (plugin manager bootstrap), `options.lua`, `keymaps.lua`
- `nvim/lua/plugins.lua` — plugin specs
- `nvim/lua/colorschemes/` — theme configs (gruvbox, kanagawa, nordic)
- `nvim/lua/claudecode_provider.lua` — multi-session terminal provider for claudecode.nvim (session lifecycle, persistence, MCP routing)
- `nvim/lua/claudecode_status.lua` — reads Claude Code statusline cache files from `/tmp` and exposes lualine components (context window %, token count, API usage %, reset date)

### Window Managers

- `sway/config` — sway (Wayland) config for Arch Linux
- `sway/scripts/screenshot.py` — macOS-inspired screenshot tool (GTK3 + layer-shell). Modes: region, window, screen, all, menu (toolbar). Features: auto-save to `~/Pictures/Screenshots/`, clipboard copy, floating thumbnail preview, click-to-edit (swappy), drag-to-drop (ripdrag), timer countdown. Keybinds: `$mod+s` region, `$mod+Ctrl+s` toolbar, `Print` fullscreen.
- `sway/scripts/volume-osd.py` — GTK3 layer-shell volume OSD triggered by PulseAudio events
- `i3/config` — legacy i3wm config (migrated to sway)
- `i3blocks/` — i3blocks status bar configs (`config-main`, `config-portrait` for multi-monitor)
- `aerospace/aerospace.toml` — Aerospace WM config for macOS

### Waybar

- `waybar/config.jsonc` — Waybar config (Gruvbox Dark theme, two bars: `main` for DP-3, `portrait` for DP-2)
- `waybar/style.css` — Waybar styling (Gruvbox Dark colors, per-module accents)
- `waybar/scripts/` — status modules (cpu, gpu, memory, temp — each with a `-simple.sh` variant) and power menu
  - `power-menu.sh` — GTK popup menu (Sound, Bluetooth, Restart, Shutdown, Logout)
  - `power-popup.py` — GTK3 layer-shell popup with transparent backdrop for click-outside dismiss
  - `power-countdown.py` — GTK3 countdown popup (60s) for Restart/Shutdown/Logout with cancel support

### Scripts

- `scripts/claude-statusline.sh` — Claude Code statusline command. Receives session JSON on stdin, extracts context/usage data via `jq`, writes to `/tmp/claude_status_<session_id>.json`. Referenced by `~/.claude/settings.json` `statusLine.command`. Requires `jq` on both machines.

### Terminal & Multiplexer

- `kitty/kitty.conf` — Kitty terminal config (with `themes/` subdir). Includes a `map shift+enter` that sends the CSI u sequence (`\x1b[13;2u`) so Shift+Enter works inside tmux (tmux doesn't support the kitty keyboard protocol natively).
- `tmux/tmux.conf` — tmux config (plugins dir is gitignored, managed by TPM). Uses `extended-keys always` and `allow-passthrough on` for better key/sequence forwarding. Per-host Gruvbox accent via `if-shell` (`uname -s`): macOS = blue (`#83a598`), Arch = yellow (`#fabd2f`). OSC 52 clipboard enabled (`set-clipboard on`) for copy-through-SSH. Status bar right shows `#{@pane_host}` (hostname) and `#{pane_title}` (cwd), both set by the shell's `precmd`/SSH wrapper. Nested tmux: F12 toggles outer passthrough (collapses bar to red `NESTED` indicator, all keys forward to inner session); inner tmux (detected via `SSH_CONNECTION`) uses bottom bar with Gruvbox purple (`#d3869b`) accent and simplified status.
- `tmux/gitmux.conf` — gitmux config (git status symbols for tmux statusline)

## Symlink conventions

Configs are deployed via symlinks. Common pattern:
```bash
ln -sf ~/.dotfiles/nvim ~/.config/nvim
ln -sf ~/.dotfiles/kitty ~/.config/kitty
ln -sf ~/.dotfiles/waybar ~/.config/waybar
ln -sf ~/.dotfiles/sway ~/.config/sway
ln -sf ~/.dotfiles/tmux/tmux.conf ~/.config/tmux/tmux.conf
ln -sf ~/.dotfiles/.zshrc ~/.zshrc
```

### Other

- `.Xresources` — X11 cursor size config

## Gitignored files

- `.zshrc.local` — machine-local shell overrides
- `nvim/lazy-lock.json` — plugin lockfile
- `tmux/plugins/` — TPM-managed plugins
- `.zsh_plugins.zsh` — Antidote-generated file (regenerated from `.zsh_plugins.txt`)
- `sway/config.bak` — sway config backup
