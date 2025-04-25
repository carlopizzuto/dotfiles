# === Plugin manager (Antidote) ===
source ~/.antidote/antidote.zsh

antidote load

# === Source Plugins ===
# source ~/.zsh_plugins.zsh

# === Tab Completions Menu ===
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select

# === UX Plugins ===
# Autosuggestions
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# === History ===
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY

# === Minimal Prompt (with Git branch support) ===
autoload -Uz vcs_info
precmd() { vcs_info }
setopt PROMPT_SUBST
PROMPT='%F{blue}%n@%m%f %F{green}%~%f ${vcs_info_msg_0_}%# '
zstyle ':vcs_info:git:*' formats '(%b)'

# === Dev Environment ===

# Conda
__conda_setup="$('/opt/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/opt/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup

# Node Version Manager (NVM)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Google Cloud SDK
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then
  source "$HOME/google-cloud-sdk/path.zsh.inc"
fi
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then
  source "$HOME/google-cloud-sdk/completion.zsh.inc"
fi

# MySQL
export PATH="/usr/local/mysql/bin:$PATH"

# === Common Aliases ===
# --- git
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph'

# -- ls
alias ls='ls --color=auto'
alias ll='ls -Alh --color=auto'
alias grep='grep --color=auto'

# -- movement
alias ..='cd ..'
alias ...='cd ../..'


# === Keybinds ===
# Accept autosuggestion with Tab
bindkey '^I' autosuggest-accept

# Use Ctrl+Space to manually trigger completion
bindkey '^ ' expand-or-complete

# Disable auto menu complete
unsetopt MENU_COMPLETE

# ── Ctrl-L / clear  (kitty) ────────────────────────────────────────────
# kitty’s private sequence 22J = "scroll visible -> history, then clear"
function __kitty_clear() {
	# 1) pretty marker — tweak colours / glyphs if you like
	local ts=$(date '+%Y-%m-%d %H:%M:%S')
	print -P "\n\n%F{244}─« cleared - $ts »─────────────────────────────────────────%f\n"
	
	# 2) blank the display but keep everything in history
	if [[ $TERM == xterm-kitty ]]; then
		#  ␍        carriage-return      (start of line)
		#  CSI 0 J  clear from cursor to bottom so we don't copy prompt twice
		#  CSI H    home cursor (row 0 col 0)
		#  CSI 22 J kitty-extension: scroll + clear, keeps scrollback intact
		printf '\r\e[0J\e[H\e[22J' >"$TTY"
  	else
    		# Portable fallback for other terminals (ncurses ≥ 6.2)
		command clear -x
	fi

  	zle reset-prompt     # redraw prompt at row 1
	zle -R               # refresh
}

zle -N __kitty_clear
bindkey '^L' __kitty_clear        # Ctrl-L
alias clear='__kitty_clear'       # the command

