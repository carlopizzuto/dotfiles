# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**IMPORTANT: Keep this file up to date. Whenever you add, remove, rename, or restructure configs in this repo, update CLAUDE.md to reflect the change in the same commit.**

## Overview

Personal dotfiles repo managing configs across two machines:
- **Arch Linux PC** (primary, sway/Wayland) — AMD 7600X, RTX 4070 Super
- **MacBook** (macOS, Aerospace WM) — Apple M3 Pro

Configs are symlinked from `~/.dotfiles/` into their expected locations (e.g., `~/.config/nvim`, `~/.config/kitty`, `~/.config/sway`).

## Architecture

### Zsh (split config)

The shell config is split into shared + platform-specific files:
- `.zshrc` — shared config sourced on all machines (PATH, aliases, plugins, prompt, keybinds)
- `zsh/zshrc.darwin` — macOS: Homebrew, pnpm, XQuartz paths
- `zsh/zshrc.linux` — Arch: miniconda, pyenv, vapi paths

Platform dispatch in `.zshrc` uses `uname -s`. Machine-local overrides go in `~/.zshrc.local` (gitignored).

Plugin manager: **Antidote** (sourced from `~/.antidote/antidote.zsh`). Plugins listed in `.zsh_plugins.txt`.

Shell startup auto-pulls this repo in the background (`git pull --ff-only`).

### Neovim

Standard lazy.nvim structure:
- `nvim/init.lua` → loads `config.lazy`
- `nvim/lua/config/` — `lazy.lua` (plugin manager bootstrap), `options.lua`, `keymaps.lua`
- `nvim/lua/plugins.lua` — plugin specs
- `nvim/lua/colorschemes/` — theme configs (gruvbox, kanagawa, nordic)

### Window Managers

- `sway/config` — sway (Wayland) config for Arch Linux
- `i3/config` — legacy i3wm config (migrated to sway)
- `i3blocks/` — i3blocks status bar configs (`config-main`, `config-portrait` for multi-monitor)
- `aerospace/aerospace.toml` — Aerospace WM config for macOS

### Polybar

- `polybar/config.ini` — Polybar bar config (Gruvbox Dark theme, two bars: `main` for DP-3, `portrait` for DP-2)
- `polybar/launch.sh` — launch script (kills existing instances, starts both bars)
- `polybar/scripts/` — status modules (cpu, gpu, memory, temp, disk) and power menu
  - `power-menu.sh` — rofi dropdown (Sound, Bluetooth, Restart, Shutdown, Logout)
  - `power-countdown.py` — GTK3 countdown popup (60s) for Restart/Shutdown/Logout with cancel support

### Terminal & Multiplexer

- `kitty/kitty.conf` — Kitty terminal config (with `themes/` subdir). Includes a `map shift+enter` that sends the CSI u sequence (`\x1b[13;2u`) so Shift+Enter works inside tmux (tmux doesn't support the kitty keyboard protocol natively).
- `tmux/tmux.conf` — tmux config (plugins dir is gitignored, managed by TPM). Uses `extended-keys always` and `allow-passthrough on` for better key/sequence forwarding.

## Symlink conventions

Configs are deployed via symlinks. Common pattern:
```bash
ln -sf ~/.dotfiles/nvim ~/.config/nvim
ln -sf ~/.dotfiles/kitty ~/.config/kitty
ln -sf ~/.dotfiles/polybar ~/.config/polybar
ln -sf ~/.dotfiles/sway ~/.config/sway
ln -sf ~/.dotfiles/tmux/tmux.conf ~/.config/tmux/tmux.conf
ln -sf ~/.dotfiles/.zshrc ~/.zshrc
```

## Gitignored files

- `.zshrc.local` — machine-local shell overrides
- `nvim/lazy-lock.json` — plugin lockfile
- `tmux/plugins/` — TPM-managed plugins
- `.zsh_plugins.zsh` — Antidote-generated file (regenerated from `.zsh_plugins.txt`)
