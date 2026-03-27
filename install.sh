#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Dotfiles installer
# Detects platform, installs dependencies, symlinks configs.
# Safe to re-run (idempotent).
#
# Usage:
#   ./install.sh              Auto-detect (headless = core only)
#   ./install.sh --all        Full install (core + desktop)
#   ./install.sh --core       Core CLI tools only
#   ./install.sh --desktop    Desktop/GUI packages only
#   ./install.sh --symlinks   Just redo symlinks
#   ./install.sh --no-fonts   Skip font installation
# ============================================================================

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Colors & logging
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERR]${NC}   %s\n" "$*" >&2; }

command_exists() { command -v "$1" &>/dev/null; }

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
detect_platform() {
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  DISTRO="unknown"
  HAS_DISPLAY=false
  ARCH="$(uname -m)"

  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
  esac

  if [[ "$OS" == "darwin" ]]; then
    DISTRO="macos"
    HAS_DISPLAY=true
  elif [[ "$OS" == "linux" ]]; then
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      case "${ID:-}" in
        arch|endeavouros|manjaro) DISTRO="arch" ;;
        ubuntu|pop|linuxmint)    DISTRO="ubuntu" ;;
        debian)                  DISTRO="debian" ;;
        fedora)                  DISTRO="fedora" ;;
        *)
          case "${ID_LIKE:-}" in
            *arch*)   DISTRO="arch" ;;
            *ubuntu*|*debian*) DISTRO="ubuntu" ;;
          esac
          ;;
      esac
    fi
    [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" || "${XDG_SESSION_TYPE:-}" == "wayland" || "${XDG_SESSION_TYPE:-}" == "x11" ]] && HAS_DISPLAY=true
  fi

  info "Platform: ${BOLD}$DISTRO${NC} ($OS, $ARCH)"
  info "Display:  ${BOLD}$HAS_DISPLAY${NC}"
}

# ---------------------------------------------------------------------------
# Symlink helper
# ---------------------------------------------------------------------------
make_symlink() {
  local src="$1" dst="$2"

  mkdir -p "$(dirname "$dst")"

  if [[ -L "$dst" ]]; then
    local current
    current="$(readlink "$dst")"
    if [[ "$current" == "$src" ]]; then
      ok "Already linked: $dst"
      return
    fi
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    local bak="${dst}.bak.$(date +%s)"
    warn "Backing up $dst -> $bak"
    mv "$dst" "$bak"
  fi

  ln -sf "$src" "$dst"
  ok "Linked: $dst -> $src"
}

# ---------------------------------------------------------------------------
# Package managers
# ---------------------------------------------------------------------------
APT_UPDATED=false

pkg_arch() {
  sudo pacman -S --needed --noconfirm "$@"
}

pkg_ubuntu() {
  if [[ "$APT_UPDATED" == false ]]; then
    info "Updating apt cache..."
    sudo apt-get update -qq
    APT_UPDATED=true
  fi
  sudo apt-get install -y "$@"
}

pkg_macos() {
  if ! command_exists brew; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
  fi
  brew install "$@"
}

pkg_install() {
  case "$DISTRO" in
    arch)   pkg_arch "$@" ;;
    ubuntu|debian) pkg_ubuntu "$@" ;;
    macos)  pkg_macos "$@" ;;
    *) warn "Unknown distro '$DISTRO' — install manually: $*" ;;
  esac
}

# ---------------------------------------------------------------------------
# Core CLI packages
# ---------------------------------------------------------------------------
install_core() {
  info "Installing core CLI packages..."

  case "$DISTRO" in
    arch)
      pkg_arch zsh tmux neovim git fzf zoxide jq curl unzip btop
      ;;
    ubuntu|debian)
      pkg_ubuntu zsh tmux git fzf jq curl unzip btop

      # Neovim: apt version is ancient, use PPA for 0.9+
      if ! command_exists nvim || [[ "$(nvim --version | head -1 | grep -oP '\d+\.\d+')" < "0.9" ]]; then
        info "Adding Neovim PPA for a recent version..."
        sudo apt-get install -y software-properties-common
        sudo add-apt-repository -y ppa:neovim-ppa/unstable
        sudo apt-get update -qq
        sudo apt-get install -y neovim
      else
        ok "Neovim already up to date"
      fi

      # Zoxide: not in older apt repos
      if ! command_exists zoxide; then
        info "Installing zoxide..."
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
      else
        ok "zoxide already installed"
      fi
      ;;
    macos)
      pkg_macos zsh tmux neovim git fzf zoxide jq curl btop
      ;;
  esac

  ok "Core packages done"
}

# ---------------------------------------------------------------------------
# Desktop/GUI packages
# ---------------------------------------------------------------------------
install_desktop() {
  if [[ "$HAS_DISPLAY" == false ]]; then
    warn "No display detected — skipping desktop packages"
    return
  fi

  info "Installing desktop packages..."

  case "$DISTRO" in
    arch)
      pkg_arch kitty sway waybar mako rofi swayidle wl-clipboard cliphist \
               hyprpicker playerctl wireplumber \
               python-gobject gtk3 gtk-layer-shell thunar

      # AUR packages via paru
      if command_exists paru; then
        paru -S --needed --noconfirm ripdrag swappy satty 2>/dev/null || warn "Some AUR packages failed — install manually"
      else
        warn "paru not found — install ripdrag, swappy, satty from AUR manually"
      fi
      ;;
    ubuntu|debian)
      pkg_ubuntu kitty sway waybar mako-notifier rofi swayidle wl-clipboard \
                 playerctl wireplumber python3-gi gir1.2-gtk-3.0 \
                 gtk-layer-shell thunar 2>/dev/null || warn "Some desktop packages unavailable — install manually"
      ;;
    macos)
      brew install --cask kitty
      brew tap nikitabobko/tap 2>/dev/null || true
      brew install --cask nikitabobko/tap/aerospace
      ;;
  esac

  ok "Desktop packages done"
}

# ---------------------------------------------------------------------------
# Antidote (zsh plugin manager)
# ---------------------------------------------------------------------------
setup_antidote() {
  local antidote_dir="$HOME/.antidote"

  if [[ -d "$antidote_dir" ]]; then
    info "Updating antidote..."
    git -C "$antidote_dir" pull --ff-only 2>/dev/null || warn "antidote update failed"
    ok "antidote up to date"
  else
    info "Installing antidote..."
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$antidote_dir"
    ok "antidote installed"
  fi
}

# ---------------------------------------------------------------------------
# TPM (tmux plugin manager)
# ---------------------------------------------------------------------------
setup_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"

  if [[ -d "$tpm_dir" ]]; then
    info "Updating TPM..."
    git -C "$tpm_dir" pull --ff-only 2>/dev/null || warn "TPM update failed"
    ok "TPM up to date"
  else
    info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
    ok "TPM installed — run prefix + I inside tmux to install plugins"
  fi
}

# ---------------------------------------------------------------------------
# gitmux (git status in tmux statusline)
# ---------------------------------------------------------------------------
setup_gitmux() {
  if command_exists gitmux; then
    ok "gitmux already installed"
    return
  fi

  info "Installing gitmux..."
  local os_name
  case "$OS" in
    darwin) os_name="macOS" ;;
    linux)  os_name="linux" ;;
    *) warn "Unsupported OS for gitmux"; return ;;
  esac

  local latest
  latest=$(curl -sSf https://api.github.com/repos/arl/gitmux/releases/latest | jq -r '.tag_name') || {
    warn "Failed to fetch gitmux release — skipping"
    return
  }

  local url="https://github.com/arl/gitmux/releases/download/${latest}/gitmux_${latest#v}_${os_name}_${ARCH}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"

  if curl -sSfL "$url" | tar -xz -C "$tmp"; then
    mkdir -p "$HOME/.local/bin"
    mv "$tmp/gitmux" "$HOME/.local/bin/gitmux"
    chmod +x "$HOME/.local/bin/gitmux"
    ok "gitmux ${latest} installed to ~/.local/bin/gitmux"
  else
    warn "Failed to download gitmux — skipping"
  fi

  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Nerd Fonts
# ---------------------------------------------------------------------------
setup_fonts() {
  info "Setting up Iosevka Nerd Font..."

  case "$DISTRO" in
    arch)
      pkg_arch ttf-iosevka-nerd
      ;;
    macos)
      brew install --cask font-iosevka-nerd-font
      ;;
    ubuntu|debian)
      if fc-list 2>/dev/null | grep -qi "Iosevka.*Nerd"; then
        ok "Iosevka Nerd Font already installed"
        return
      fi

      local font_dir="$HOME/.local/share/fonts"
      mkdir -p "$font_dir"

      local latest
      latest=$(curl -sSf https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | jq -r '.tag_name') || {
        warn "Failed to fetch nerd-fonts release — install manually"
        return
      }

      local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${latest}/Iosevka.zip"
      local tmp
      tmp="$(mktemp -d)"

      info "Downloading Iosevka Nerd Font ${latest}..."
      if curl -sSfL -o "$tmp/Iosevka.zip" "$url"; then
        unzip -qo "$tmp/Iosevka.zip" -d "$font_dir"
        fc-cache -f 2>/dev/null
        ok "Iosevka Nerd Font installed"
      else
        warn "Failed to download font — install manually from nerdfonts.com"
      fi

      rm -rf "$tmp"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Symlinks
# ---------------------------------------------------------------------------
setup_symlinks() {
  info "Setting up symlinks..."

  # -- Always (all platforms) --
  make_symlink "$DOTFILES_DIR/.zshrc"             "$HOME/.zshrc"
  make_symlink "$DOTFILES_DIR/.zsh_plugins.txt"   "$HOME/.zsh_plugins.txt"
  make_symlink "$DOTFILES_DIR/nvim"               "$HOME/.config/nvim"
  make_symlink "$DOTFILES_DIR/tmux/tmux.conf"     "$HOME/.config/tmux/tmux.conf"

  # -- Linux desktop --
  if [[ "$OS" == "linux" && "$HAS_DISPLAY" == true ]]; then
    make_symlink "$DOTFILES_DIR/kitty"            "$HOME/.config/kitty"
    make_symlink "$DOTFILES_DIR/sway"             "$HOME/.config/sway"
    make_symlink "$DOTFILES_DIR/waybar"           "$HOME/.config/waybar"
    make_symlink "$DOTFILES_DIR/.Xresources"      "$HOME/.Xresources"
  fi

  # -- macOS --
  if [[ "$OS" == "darwin" ]]; then
    make_symlink "$DOTFILES_DIR/kitty"                       "$HOME/.config/kitty"
    make_symlink "$DOTFILES_DIR/aerospace/aerospace.toml"    "$HOME/.aerospace.toml"
  fi

  ok "Symlinks done"
}

# ---------------------------------------------------------------------------
# Default shell
# ---------------------------------------------------------------------------
setup_shell() {
  local zsh_path
  zsh_path="$(which zsh 2>/dev/null)" || { warn "zsh not found — skipping shell change"; return; }

  if [[ "$SHELL" == *zsh ]]; then
    ok "Default shell is already zsh"
    return
  fi

  # Ensure zsh is in /etc/shells
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    warn "Adding $zsh_path to /etc/shells"
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  fi

  printf "\n"
  read -rp "Change default shell to zsh? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    chsh -s "$zsh_path"
    ok "Default shell changed to zsh — log out and back in to take effect"
  else
    info "Skipped — run 'chsh -s $zsh_path' to change later"
  fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Options:
  --all        Full install (core + desktop + fonts)
  --core       Core CLI tools only (zsh, tmux, nvim, ...)
  --desktop    Desktop/GUI packages only
  --symlinks   Just redo symlinks, no package installs
  --no-fonts   Skip font installation
  -h, --help   Show this help

No flags: auto-detects headless vs desktop and installs accordingly.
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local mode="auto"
  local skip_fonts=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)      mode="all" ;;
      --core)     mode="core" ;;
      --desktop)  mode="desktop" ;;
      --symlinks) mode="symlinks" ;;
      --no-fonts) skip_fonts=true ;;
      -h|--help)  usage; exit 0 ;;
      *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done

  printf "\n${BOLD}Dotfiles Installer${NC}\n"
  printf "%s\n\n" "──────────────────"

  detect_platform

  # Auto mode: headless = core, display = all
  if [[ "$mode" == "auto" ]]; then
    if [[ "$HAS_DISPLAY" == true ]]; then
      mode="all"
    else
      mode="core"
    fi
    info "Auto-detected mode: ${BOLD}$mode${NC}"
  fi

  printf "\n"

  case "$mode" in
    symlinks)
      setup_symlinks
      ;;
    core)
      install_core
      setup_antidote
      setup_tpm
      setup_gitmux
      setup_symlinks
      setup_shell
      ;;
    desktop)
      install_desktop
      [[ "$skip_fonts" == false ]] && setup_fonts
      setup_symlinks
      ;;
    all)
      install_core
      install_desktop
      setup_antidote
      setup_tpm
      setup_gitmux
      [[ "$skip_fonts" == false ]] && setup_fonts
      setup_symlinks
      setup_shell
      ;;
  esac

  printf "\n${GREEN}${BOLD}All done!${NC}\n"
  printf "Open a new shell or run: ${BOLD}exec zsh${NC}\n\n"
}

main "$@"