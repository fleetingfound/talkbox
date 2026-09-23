black='\[\e[30m\]'
red='\[\e[31m\]'
green='\[\e[32m\]'
yellow='\[\e[33m\]'
blue='\[\e[34m\]'
magenta='\[\e[35m\]'
cyan='\[\e[36m\]'
white='\[\e[37m\]'
dim='\[\e[2m\]'

bold='\[\e[1m\]'
reset='\[\e[0m\]'

parse_git_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

PS1="\n${yellow}[\t]${reset} ${bold}${magenta}\u@${TALKBOX_PROJECT_SLUG:-}.${TALKBOX_CONTAINER_TYPE:-}${reset} ${bold}${blue}\w${reset} ${bold}${green}\$(parse_git_branch)${reset}${red}\n❯${reset} "

PROMPT_COMMAND='echo -ne "\033]0;${TALKBOX_PROJECT_SLUG:-}.${TALKBOX_CONTAINER_TYPE:-}: ${PWD##*/}\007"'

export OPENCODE_ENABLE_EXA=1

export EDITOR=vi

HISTSIZE=-1
HISTFILESIZE=-1
HISTCONTROL=ignoredups:erasedups
shopt -s histappend

shopt -s checkwinsize
shopt -s globstar

export LESS='-R'
export LESSHISTFILE=-

alias l='ls -CF --color=auto'
alias lt='ls -ltF --color=auto'
alias la='ls -A --color=auto'
alias ll='ls -lF --color=auto'
alias lla='ls -lAF --color=auto'

alias v='${EDITOR:-vi}'

cdl() {
  cd -P "${1:-.}" >/dev/null && pwd
}

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../../'
alias .....='cd ../../../../'
alias -- -='cd -'

alias grep='grep -In --color=auto --exclude-dir={.git,node_modules,.hg,.svn,dist,build,.venv,venv,__pycache__,.next,target,.cache}'

alias rme='find . -type d -empty -delete'

alias reload='source ~/.bashrc'

alias ga='git add'
alias gb='git branch -v'
alias gc='git commit --verbose'
alias gca='git commit --amend'
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
alias gpop='git stash pop'
alias gsw='git switch'
alias gt='cd "$(git rev-parse --show-cdup)."'

alias gre='git restore'
alias gun='git restore --source=HEAD'                       # undo to last commit
alias gus='git restore --staged'                            # unstage
alias gcl='git clean -f'                                    # remove untracked files
alias gdd='git restore --source=HEAD -- . && git clean -fd' # gun && gcl

alias cc='claude'
alias oc='opencode'
