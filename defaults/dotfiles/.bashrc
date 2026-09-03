teal="\001$(tput setaf 14)\002"
blue="\001$(tput setaf 6)\002"
dim="\001$(tput setaf 1)\002"
reset="\001$(tput sgr0)\002"

PS1="$dim[\t] $teal\u@${TALKBOX_PROJECT_SLUG:-}.${TALKBOX_CONTAINER_TYPE:-} $blue\w$reset: "

export OPENCODE_ENABLE_EXA=1

export EDITOR=vi

alias l='ls -CF'
alias lt='ls -ltF'
alias la='ls -A'
alias ll='ls -lF'
alias lla='ls -lAF'

alias v='${EDITOR:-vi}'

cdl() {
  cd -P "${1:-.}" >/dev/null && pwd
}

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../../'
alias .....='cd ../../../../'
alias -- -='cd -'

alias grep='grep -RIn --color \
  --exclude-dir=.git \
  --exclude-dir=node_modules'

alias rme='find . -type d -empty -delete'

alias ga='git commit --amend'
alias gb='git branch -v'
alias gc='git commit --verbose'
alias gcu='git commit -m Update'
alias gch='git cherry-pick'
alias gd='git diff'
alias gdn='git diff --name-only'
alias gdw='git diff --word-diff'
alias ge="{ git diff --name-only; git ls-files --others --exclude-standard; } | xargs -r -d '\n' \${EDITOR:-vi}"
alias gf='git fetch'
alias ghu='git add -p'
alias gl='git log --oneline'
alias gla='git log --oneline --graph --decorate --all'
alias gpl='git pull'
alias gps='git push'
alias gr='git remote -v'
alias grb='git rebase -i'
alias gs='git status -s'
alias gsts='git stash'
alias gpop='git pop'
alias gsw='git switch'
alias gt='cd "$(git rev-parse --show-cdup)."'
alias gw='git add'

alias gre='git restore'
alias gun='git restore --source=HEAD' # undo to last commit
alias gus='git restore --staged'      # unstage
alias gcl='git clean -f'
alias gdd='git restore --source=HEAD -- . && git clean -fd'
