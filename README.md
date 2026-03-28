#      ███████╗██╗██╗     ███████╗███████╗
#      ██╔════╝██║██║     ██╔════╝██╔════╝
#      █████╗  ██║██║     █████╗  ███████╗
#      ██╔══╝  ██║██║     ██╔══╝  ╚════██║
#  ██╗ ██║     ██║███████╗███████╗███████║
#  ╚═╝ ╚═╝     ╚═╝╚══════╝╚══════╝╚══════╝

Personal dotfiles managing configs across two machines:
- **Arch Linux PC** (sway/Wayland) — AMD 7600X, RTX 4070 Super
- **MacBook** (macOS, Aerospace WM) — Apple M3 Pro

<!-- TODO: Add a screenshot here -->

## What's Inside

| Config | Directory | Description |
|--------|-----------|-------------|
| **Neovim** | `nvim/` | lazy.nvim, Treesitter, LSP, Telescope, Claude Code integration |
| **Zsh** | `.zshrc`, `zsh/` | Shared config + platform-specific splits (macOS / Arch) |
| **Kitty** | `kitty/` | Terminal emulator with Gruvbox/Nord themes |
| **Sway** | `sway/` | Wayland compositor config + screenshot & volume OSD scripts |
| **Waybar** | `waybar/` | Status bar with Gruvbox theme, dual-monitor, power menu |
| **tmux** | `tmux/` | Multiplexer config with TPM + gitmux |
| **Aerospace** | `aerospace/` | macOS tiling window manager |
| **i3** | `i3/`, `i3blocks/` | Legacy i3wm config (migrated to sway) |

## Features

- **macOS-style screenshot tool** — GTK3 + layer-shell script with 5 modes (region, window, screen, all outputs, toolbar menu), floating thumbnail preview, click-to-edit with Satty, drag-to-drop with ripdrag, and timer countdown
- **Volume OSD** — GTK3 layer-shell overlay triggered by PulseAudio events, macOS-style
- **Power menu with countdown** — Waybar popup with transparent backdrop, 60-second countdown for restart/shutdown/logout with cancel support
- **Claude Code integration** — custom Neovim terminal provider for multi-session Claude Code, lualine statusline showing context window %, token count, and API usage
- **Dual-machine architecture** — shared zsh config with platform-specific splits, one repo for both Arch and macOS
- **Auto-pull on shell startup** — background `git pull --ff-only` every time a shell spawns, dotfiles stay in sync without thinking about it
- **Auto-tmux** — shell auto-attaches to an existing tmux session or creates a new one

## Keybindings

### Sway (Arch Linux)

Modifier: `Super`

#### Apps & Launchers

| Key | Action |
|-----|--------|
| `Super+Return` | Terminal (Kitty) |
| `Super+w` | Zen Browser |
| `Super+e` | Thunar file manager |
| `Super+Space` | Rofi launcher |
| `Super+c` | Rofi calculator |

#### Window Management

| Key | Action |
|-----|--------|
| `Super+h/j/k/l` | Focus left/down/up/right |
| `Super+Shift+h/j/k/l` | Move window left/down/up/right |
| `Super+n` | Split horizontal |
| `Super+b` | Split vertical |
| `Super+f` | Fullscreen |
| `Super+Shift+Space` | Toggle floating |
| `Super+Shift+q` | Close window |
| `Super+r` | Enter resize mode (then h/j/k/l) |

#### Workspaces

| Key | Action |
|-----|--------|
| `Super+1-0` | Workspace 1–10 (DP-3) |
| `Super+Alt+1-0` | Workspace 11–20 (DP-2) |
| `Super+Shift+1-0` | Move window to workspace 1–10 |
| `Super+Tab / Shift+Tab` | Cycle workspaces on current monitor |

#### Screenshots & Utilities

| Key | Action |
|-----|--------|
| `Super+s` | Region screenshot |
| `Super+Ctrl+s` | Screenshot toolbar (all modes) |
| `Print` | Fullscreen screenshot |
| `Super+z` | Color picker (hyprpicker) |
| `Super+Shift+v` | Clipboard history |
| `Super+Shift+a` | Cava audio visualizer |

#### Media

| Key | Action |
|-----|--------|
| `XF86Audio{Raise,Lower}Volume` | Volume up/down 5% |
| `XF86AudioMute` | Toggle mute |
| `XF86Audio{Play,Next,Prev}` | Playback controls |

### Aerospace (macOS)

Modifier: `Alt`

Same vim-style philosophy — `Alt` replaces `Super`, `Cmd` replaces `Alt` for secondary workspaces.

| Key | Action |
|-----|--------|
| `Alt+Return` | Terminal (Kitty) |
| `Alt+h/j/k/l` | Focus left/down/up/right |
| `Alt+Shift+h/j/k/l` | Move window |
| `Alt+f` | Fullscreen |
| `Alt+s` | Vertical accordion (stacking) |
| `Alt+w` | Horizontal accordion (tabbed) |
| `Alt+e` | Toggle split |
| `Alt+Shift+Space` | Toggle floating |
| `Alt+Shift+q` | Close window |
| `Alt+1-0` | Workspace 1–10 |
| `Alt+Cmd+1-0` | Workspace 11–20 |
| `Alt+Tab / Shift+Tab` | Cycle workspaces |
| `Alt+r` | Resize mode |

## Shell Architecture

```
.zshrc (shared entry point)
│
├── Auto-pull dotfiles repo (background)
├── Auto-attach tmux session
├── PATH setup (deduplication)
│
├── Platform dispatch (uname -s)
│   ├── zsh/zshrc.darwin ── Homebrew, pnpm, XQuartz, conda, pyenv
│   └── zsh/zshrc.linux  ── conda, pyenv, vapi
│
├── Antidote plugin manager
│   └── .zsh_plugins.txt
│       ├── zsh-completions
│       ├── zsh-autosuggestions
│       └── zsh-syntax-highlighting
│
├── Prompt (user@host dir (branch))
├── Aliases (git, ls, navigation, tmux)
├── Keybinds (Ctrl+Space expand, Ctrl+L clear)
├── Dev tools (NVM, Google Cloud SDK)
│
└── ~/.zshrc.local (machine-local overrides, gitignored)
```

## Dependencies

### Arch Linux

```
# Core
sway waybar kitty tmux zsh rofi

# Sway ecosystem
swayidle grim satty swappy wl-clipboard cliphist hyprpicker ripdrag

# Audio & media
pipewire pulseaudio-utils pavucontrol playerctl blueman cava

# System
networkmanager dex lm_sensors btop nvidia-utils

# CLI tools
fzf zoxide jq gitmux starship

# Python (for GTK scripts)
python python-gobject gtk-layer-shell python-cairo

# Fonts
ttf-iosevka-nerd

# Apps
zen-browser thunar
```

### macOS (Homebrew)

```
kitty tmux zsh

# CLI tools
fzf zoxide jq starship

# Dev
nvm pyenv miniconda pnpm libpq

# Window manager
aerospace

# Fonts
font-iosevka-nerd-font
```

## Per-Module Details

### Neovim

lazy.nvim plugin management with a flat structure: `nvim/lua/plugins.lua` for all specs, `nvim/lua/config/` for options, keymaps, and bootstrap. Three colorscheme configs (Gruvbox, Kanagawa, Nordic) under `nvim/lua/colorschemes/`.

The Claude Code integration has two custom modules:
- `claudecode_provider.lua` — multi-session terminal provider for claudecode.nvim handling session lifecycle, persistence, and MCP routing
- `claudecode_status.lua` — reads statusline cache files from `/tmp` and exposes lualine components for context window %, token count, API usage %, and reset date

### Kitty

GPU-accelerated terminal with four themes (1984, Gruvbox, Nord, Nordic). Custom `Shift+Enter` mapping sends the CSI u sequence (`\x1b[13;2u`) so it works inside tmux, which doesn't support the Kitty keyboard protocol natively.

### Sway

Wayland compositor config for dual-monitor setup (DP-3 main, DP-2 portrait). Workspaces 1–10 on main, 11–20 on portrait. Two custom GTK3 layer-shell scripts:

- **screenshot.py** — macOS-inspired screenshot with region/window/screen/all/menu modes, auto-save to `~/Pictures/Screenshots/`, clipboard copy, floating thumbnail preview with click-to-edit (Satty) and drag-to-drop (ripdrag), optional timer countdown
- **volume-osd.py** — floating volume indicator triggered by PulseAudio events

### Waybar

Gruvbox Dark themed status bar with two bar configs (`main` for DP-3, `portrait` for DP-2). Status modules for CPU, GPU (nvidia-smi), memory, and temperature — each with a detailed and simple variant. Power menu uses a GTK3 layer-shell popup with transparent backdrop for click-outside dismiss and a 60-second countdown timer for destructive actions.

### tmux

TPM-managed plugins (resurrect, continuum, sensible). Uses `extended-keys always` and `allow-passthrough on` for proper key forwarding. Gitmux integration for git status in the statusline.

### Zsh

Split config architecture — see [Shell Architecture](#shell-architecture) above. Plugin manager is Antidote with three plugins (completions, autosuggestions, syntax highlighting). Prompt is minimal: `user@host dir (gitbranch)`.

## Setup

```bash
git clone https://github.com/yourusername/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh          # auto-detects platform and headless vs desktop
```

The installer handles everything: packages, plugin managers (Antidote, TPM), gitmux, Nerd Fonts, symlinks, and default shell.

| Flag | What it does |
|------|-------------|
| `--all` | Full install (core + desktop + fonts) |
| `--core` | Core CLI only (zsh, tmux, nvim — good for servers) |
| `--desktop` | Desktop/GUI packages only |
| `--symlinks` | Just redo symlinks, skip package installs |
| `--no-fonts` | Skip Nerd Font installation |

No flags = auto-detect. Headless server gets `--core`, machine with a display gets `--all`.

Machine-local overrides go in `~/.zshrc.local` (gitignored).

## Credits

Shoutout Claude Code (https://claude.ai/code)

## License

This project is open-sourced under the MIT license.
