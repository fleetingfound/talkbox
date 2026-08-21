# Set shell prompt
if [ -z "$PROJECT_NAME" ]; then
  PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
  PS1='\[\033]0;${PROJECT_NAME}-dev: \w\007\]\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi

export OPENCODE_ENABLE_EXA=1

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

export EDITOR=nvim

alias l='ls -CF'
alias ll='ls -lF'
alias la='ls -A'

alias v='nvim'
alias r='ranger --choosedir=$HOME/.rangerdir; LASTDIR=`cat $HOME/.rangerdir`; cd "$LASTDIR"'
alias vd='vidir'

cdl() {
  cd -P "${1:-.}" >/dev/null && pwd
}

rme='find . -type d -empty -delete'

alias g='grep -RIn --color \
  --exclude-dir=.git \
  --exclude-dir=node_modules'

alias ga='git commit --amend'
alias gb='git branch -v'
alias gc='git commit --verbose'
alias gcu='git commit -m Update'
alias gd='git diff'
alias ge="{ git diff --name-only; git ls-files --others --exclude-standard; } | xargs -d '\n' nvim"
alias gf='nvim -c Git -c only -c bd#' # vim-fugitive
alias gl='git log --oneline'
alias gla='git log --oneline --graph --decorate --all'
alias gsw='git switch'
alias gpl='git pull'
alias gps='git push'
alias gr='git remote -v'
alias gs='git status -s'
alias gt='cd "$(git rev-parse --show-cdup)."'
alias gw='git add'
alias gun='git restore --source=HEAD' # undo to last commit
alias gre='git restore'
alias gus='git restore --staged' # unstage

grb() {
  if [ -z "${1}" ]; then
    echo "Usage: `grb <number of commits>` or `grb 0` to rebase from root."
    return 1
  elif [ "${1}" = "0" ]; then
    git rebase -i --root
  else
    git rebase -i "HEAD~${1}"
  fi
}

# Enable fzf key bindings
eval "$(fzf --bash 2>/dev/null)"
