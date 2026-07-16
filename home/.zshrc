# Author: z1rov

export ZSH_DISABLE_COMPFIX=true

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"

autoload -Uz vcs_info

zstyle ':vcs_info:*' enable git

zstyle ':vcs_info:git:*' formats '%F{220}-[%F{220} %b%F{220}]%f'
zstyle ':vcs_info:git:*' actionformats '%F{220}-[%F{220} %b%F{202}*%F{220}]%f'

precmd_functions+=(vcs_info)

PS1="%{$fg[blue]%}%B[%b%{$fg[blue]%}%n %F{blue}✘%f%{$fg[blue]%} %m%{$fg[blue]%}%B]-%B[%b%{$fg[white]%}%~%{$fg[blue]%}%B]%b\${vcs_info_msg_0_}
%{$fg[blue]%}%B$%b%{$reset_color%} "

LS_COLORS="di=38;2;129;161;193:fi=38;2;216;222;233:ex=38;2;163;190;140:ln=38;2;208;135;112:so=38;2;235;203;139:pi=38;2;180;142;173:bd=38;2;191;97;106:cd=38;2;143;188;187:or=38;2;255;85;85:mi=38;2;255;0;0"
export LS_COLORS

alias cat="bat --theme='Solarized (dark)'"
alias ls='eza --icons=always --color=always'
alias ll='eza --icons=always --color=always -la'

ZSH_HIGHLIGHT_STYLES[command]='fg=71,bold'

ZSH_HIGHLIGHT_STYLES[builtin]='fg=117,bold'

ZSH_HIGHLIGHT_STYLES[function]='fg=179,bold'

ZSH_HIGHLIGHT_STYLES[alias]='fg=176,bold'

ZSH_HIGHLIGHT_STYLES[external]='fg=111,bold'

ZSH_HIGHLIGHT_STYLES[precommand]='fg=203,bold'

ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=109,bold'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=109,bold'

ZSH_HIGHLIGHT_STYLES[arg]='fg=251,bold'

ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=210,bold'

export PATH="$HOME/.local/bin:$PATH"

