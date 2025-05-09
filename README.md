#  ██████╗  ██████╗ ████████╗███████╗██╗██╗     ███████╗███████╗
#  ██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██║██║     ██╔════╝██╔════╝
#  ██║  ██║██║   ██║   ██║   █████╗  ██║██║     █████╗  ███████╗
#  ██║  ██║██║   ██║   ██║   ██╔══╝  ██║██║     ██╔══╝  ╚════██║
#  ██████╔╝╚██████╔╝   ██║   ██║     ██║███████╗███████╗███████║
#  ╚═════╝  ╚═════╝    ╚═╝   ╚═╝     ╚═╝╚══════╝╚══════╝╚══════╝
#
#  ❯  My personal configuration files for macOS

## What's Inside

This repo contains my personal configuration files for:

- **Neovim** (`nvim/`) - Text editor with supercharged productivity
- **Zsh** (`zshrc`) - Shell configuration with custom prompts and aliases
- **Kitty** (`kitty/`) - A fast, feature-rich terminal emulator

## Setup & Installation

### Prerequisites

- Linux / macOS
- Git
- Terminal access

### Quick Install

```bash
# Clone the repository
git clone https://github.com/yourusername/dotfiles.git ~/.dotfiles

# Create symlinks (example)
ln -sf ~/.dotfiles/nvim ~/.config/nvim
ln -sf ~/.dotfiles/zshrc ~/.zshrc
ln -sf ~/.dotfiles/kitty ~/.config/kitty
```

## Neovim Configuration

My Neovim setup uses lazy.nvim for plugin management and includes:

- Modern UI with statusline & icons
- Telescope for fuzzy finding
- Treesitter for better syntax highlighting
- LSP configuration for code intelligence
- GitHub Copilot integration

## Customization

Feel free to fork and adapt to your preferences. The best dotfiles are the ones tailored to your workflow!

## License

This project is open-sourced under the MIT license.

---

> "A programmer is a person who fixes a problem that you didn't know you had, in a way you don't understand."