#!/usr/bin/env bash
set -euo pipefail

BASHRC="${HOME}/.bashrc"
BACKUP="${HOME}/.bashrc.bak.$(date +%Y%m%d_%H%M%S)"

GIT_PROMPT_DIR="${HOME}/.bash/git"
GIT_PROMPT_FILE="${GIT_PROMPT_DIR}/git-prompt.sh"
GIT_PROMPT_URL="https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh"

BEGIN_MARKER="# >>> POWERLINE_PROMPT_MANAGED (do not edit)"
END_MARKER="# <<< POWERLINE_PROMPT_MANAGED"

mkdir -p "$GIT_PROMPT_DIR"

# Backup ~/.bashrc
if [[ -f "$BASHRC" ]]; then
  cp "$BASHRC" "$BACKUP"
  echo "Backup created: $BACKUP"
else
  touch "$BASHRC"
fi

# Ensure git-prompt.sh exists
if [[ ! -f "$GIT_PROMPT_FILE" ]]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$GIT_PROMPT_URL" -o "$GIT_PROMPT_FILE"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$GIT_PROMPT_FILE" "$GIT_PROMPT_URL"
  else
    echo "ERROR: curl or wget required"
    exit 1
  fi
fi

# Remove existing managed block
tmp="$(mktemp)"
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  $0 == begin {inblock=1; next}
  $0 == end {inblock=0; next}
  !inblock {print}
' "$BASHRC" > "$tmp"
mv "$tmp" "$BASHRC"

# Append managed block
cat >> "$BASHRC" <<'EOF'
# >>> POWERLINE_PROMPT_MANAGED (do not edit)

# Terminal capabilities
export TERM=xterm-256color

# Truncate long paths: …/last/dirs
PROMPT_DIRTRIM=3

# ----- Color aliases -----
alias ls='ls --color=auto'
alias ll='ls -lh --color=auto'
alias la='ls -lha --color=auto'

alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

export LESS='-R'

if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b)"
fi

# Git prompt helper
if [ -f "$HOME/.bash/git/git-prompt.sh" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.bash/git/git-prompt.sh"
fi

# ----- Prompt color helpers (must stay in PS1) -----
RST='\[\e[0m\]'
U_GRN='\[\e[30;42m\]'
U_RED='\[\e[37;41m\]'
H_BLU='\[\e[30;44m\]'
P_BLU='\[\e[94m\]'
SEP_GB='\[\e[97;42;44m\]'
SEP_RB='\[\e[97;41;44m\]'
SEP_BD='\[\e[97;44;49m\]'

# ----- Git segment (raw ANSI, no \[ \]) -----
git_segment() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

  local branch
  branch=$(__git_ps1 "%s" 2>/dev/null) || return

  if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    # clean repo → green
    printf '\e[97;42m  %s \e[0m' "$branch"
  else
    # dirty repo → yellow
    printf '\e[30;43m  %s \e[0m' "$branch"
  fi
}

# ----- Prompt definition -----
if [ "$EUID" -eq 0 ]; then
  PS1="${U_RED} root ${SEP_RB}${H_BLU} \h ${SEP_BD}${P_BLU} \w "
  PS1+='$(git_segment)'
  PS1+="${RST}# "
else
  PS1="${U_GRN} \u ${SEP_GB}${H_BLU} \h ${SEP_BD}${P_BLU} \w "
  PS1+='$(git_segment)'
  PS1+="${RST}\$ "
fi

# <<< POWERLINE_PROMPT_MANAGED
EOF

echo "Powerline bash prompt installed."
echo "Reload with: source ~/.bashrc  (or reconnect SSH)"

