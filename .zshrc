# ---------------------------------------------------------------------------
# 0.  Clean, deterministic PATH (remove duplicates, predictable order)
# ---------------------------------------------------------------------------
#  • $path is a zsh array → easier to reason about
#  • typeset -U eliminates later duplicates automatically
#  • You can append project‑local dirs later; FIRST win stays
# ---------------------------------------------------------------------------
typeset -U path PATH
path=(
  # personal scripts
  $HOME/.local/bin

  # Homebrew (Apple‑silicon)
  /opt/homebrew/bin
  /opt/homebrew/sbin

  # language & env managers
  /opt/miniconda3/bin            
  $HOME/.nvm/versions/node/v21.6.1/bin

  # toolchains you actually use
  $HOME/google-cloud-sdk/bin
  /usr/local/mysql/bin           

  # system fallbacks
  /usr/local/bin
  /usr/bin
  /bin
  /usr/sbin
  /sbin

  # XQuartz 
  /opt/X11/bin
)
export PATH

# helper: show PATH as numbered list (path:ls)
function path:ls() {
  for i in {1..${#path[@]}}; print -r -- "$i  $path[$i]"
}

# ---------------------------------------------------------------------------
# 1.  Plugin manager — Antidote
# ---------------------------------------------------------------------------
source ~/.antidote/antidote.zsh
antidote load

# ---------------------------------------------------------------------------
# 2.  Completion menu tweaks
# ---------------------------------------------------------------------------
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select

# ---------------------------------------------------------------------------
# 3.  History settings
# ---------------------------------------------------------------------------
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS HIST_FIND_NO_DUPS SHARE_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY

# ---------------------------------------------------------------------------
# 4.  Minimal prompt with Git branch
# ---------------------------------------------------------------------------
autoload -Uz vcs_info
precmd() { vcs_info }
setopt PROMPT_SUBST
PROMPT='%F{blue}%n@%m%f %F{green}%~%f ${vcs_info_msg_0_}%# '
zstyle ':vcs_info:git:*' formats '(%b)'

# ---------------------------------------------------------------------------
# 5.  Dev environment hooks
# ---------------------------------------------------------------------------

# ---- Conda (manual) --------------------------------------------------------
__conda_setup="$(/opt/miniconda3/bin/conda shell.zsh hook 2> /dev/null)"
if [[ $? -eq 0 ]]; then
  eval "$__conda_setup"
else
  [[ -f /opt/miniconda3/etc/profile.d/conda.sh ]] && source /opt/miniconda3/etc/profile.d/conda.sh
fi
unset __conda_setup

# ---- Node Version Manager --------------------------------------------------
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]]         && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# ---- Google Cloud SDK ------------------------------------------------------
[[ -f "$HOME/google-cloud-sdk/path.zsh.inc"       ]] && source "$HOME/google-cloud-sdk/path.zsh.inc"
[[ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]] && source "$HOME/google-cloud-sdk/completion.zsh.inc"

# ---------------------------------------------------------------------------
# 6.  Aliases
# ---------------------------------------------------------------------------
# -- git
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph'
# -- ls & grep
alias ls='ls --color=auto'
alias ll='ls -Alh --color=auto'
alias grep='grep --color=auto'
# -- directory shortcuts
alias ..='cd ..'
alias ...='cd ../..'

# ---------------------------------------------------------------------------
# 7.  Keybinds & Kitty clear
# ---------------------------------------------------------------------------
# Accept autosuggestion with Tab
# Manually trigger completion with Ctrl‑Space
bindkey '^ ' expand-or-complete
# Disable automatic menu completion (prefer manual)
unsetopt MENU_COMPLETE

# Kitty‑specific clear (keeps scrollback)
function __kitty_clear() {
  local ts=$(date '+%Y-%m-%d %H:%M:%S')
  print -P "\n\n%F{244}─« cleared - $ts »─────────────────────────────────────────%f\n"
  if [[ $TERM == xterm-kitty ]]; then
    printf '\r\e[0J\e[H\e[22J' >"$TTY"
  else
    command clear -x
  fi
  zle reset-prompt
  zle -R
}
zle -N __kitty_clear
bindkey '^L' __kitty_clear
alias clear='__kitty_clear'

# ---------------------------------------------------------------------------
# 8.  Misc. environment vars
# ---------------------------------------------------------------------------
export JUNIT_HOME="$HOME/CS/JUNIT"
export CLASSPATH="$JUNIT_HOME/junit-4.13.2.jar:$JUNIT_HOME/hamcrest-core-1.3.jar"

# ---------------------------------------------------------------------------
# 9.  Zsh plugins
# ---------------------------------------------------------------------------
source <(fzf --zsh)
eval "$(zoxide init zsh --cmd cd)"

# Restore Tab to accept autosuggestion after plugins
bindkey '^I' autosuggest-accept

# End of file ---------------------------------------------------------------

