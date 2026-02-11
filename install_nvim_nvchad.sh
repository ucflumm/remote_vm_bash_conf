#!/usr/bin/env bash
set -euo pipefail

echo "=== Updating system ==="
sudo apt update

echo "=== Installing packages ==="
sudo apt install -y \
  git curl unzip tar ca-certificates \
  build-essential cmake gettext ninja-build \
  tmux luarocks \
  ripgrep fd-find \
  xclip wl-clipboard \
  ncurses-term

# Ensure fd exists (Debian calls it fdfind)
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
fi

echo "=== Removing Debian neovim (if installed) to avoid PATH override ==="
sudo apt remove -y neovim || true

echo "=== Installing Neovim (stable release) ==="
# You can override by running: NVIM_VERSION=v0.11.5 ./install_nvim_nvchad.sh
NVIM_VERSION="${NVIM_VERSION:-v0.11.5}"
NVIM_TAR="nvim-linux-x86_64.tar.gz"
NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TAR}"

cd /tmp
curl -fLO "$NVIM_URL"

sudo rm -rf /opt/nvim
sudo tar -C /opt -xzf "$NVIM_TAR"
sudo mv /opt/nvim-linux-x86_64 /opt/nvim
rm -f "$NVIM_TAR"

# Make /usr/local/bin/nvim the canonical nvim (wins over /usr/bin and /bin)
sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim

echo "=== Ensuring PATH includes /usr/local/bin first (normally already does) ==="
if ! grep -q 'export PATH="/usr/local/bin' ~/.bashrc 2>/dev/null; then
  # Don't clobber existing PATH logic; just ensure /usr/local/bin is present early on login shells
  :
fi
hash -r

echo "=== Removing TERM override from ~/.bashrc if present (tmux sets TERM itself) ==="
# This line caused your tmux TERM mismatch:
#   export TERM=xterm-256color
# Remove it if it exists.
if [[ -f ~/.bashrc ]]; then
  sed -i '/^[[:space:]]*export[[:space:]]\+TERM=xterm-256color[[:space:]]*$/d' ~/.bashrc
fi

echo "=== Writing tmux config (focus-events + truecolor + sane TERM) ==="
TMUXCONF="$HOME/.tmux.conf"
if [[ ! -f "$TMUXCONF" ]]; then
  touch "$TMUXCONF"
fi

# Add our managed block (idempotent)
BEGIN="# >>> NVIM_NVCHAD_TMUX_MANAGED (do not edit)"
END="# <<< NVIM_NVCHAD_TMUX_MANAGED"
tmp="$(mktemp)"
awk -v begin="$BEGIN" -v end="$END" '
  $0 == begin {inblock=1; next}
  $0 == end {inblock=0; next}
  !inblock {print}
' "$TMUXCONF" > "$tmp"
mv "$tmp" "$TMUXCONF"

cat >> "$TMUXCONF" <<'EOF'
# >>> NVIM_NVCHAD_TMUX_MANAGED (do not edit)

# Make Neovim happy: TERM inside tmux should match tmux default-terminal
set -g default-terminal "tmux-256color"

# Better file autoread behavior
set -g focus-events on

# Truecolor support for modern terminals
set -ga terminal-overrides ",tmux-256color:Tc"
set -ga terminal-overrides ",xterm-256color:Tc"
set -ga terminal-overrides ",screen-256color:Tc"

# <<< NVIM_NVCHAD_TMUX_MANAGED
EOF

echo "=== Removing old Neovim config/state (fresh NvChad install) ==="
rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim

echo "=== Installing NvChad ==="
git clone https://github.com/NvChad/starter ~/.config/nvim

echo "=== Optional: add Treesitter runtimepath fix (harmless) ==="
CUSTOM_CHADRC="$HOME/.config/nvim/lua/custom/chadrc.lua"
mkdir -p "$(dirname "$CUSTOM_CHADRC")"
if [[ ! -f "$CUSTOM_CHADRC" ]]; then
  cat > "$CUSTOM_CHADRC" <<'LUA'
---@type ChadrcConfig
local M = {}

-- Ensure Neovim can see the stdpath("data") site dir if tools use it
local site = vim.fn.stdpath("data") .. "/site"
if not vim.tbl_contains(vim.opt.runtimepath:get(), site) then
  vim.opt.runtimepath:append(site)
end
if not vim.tbl_contains(vim.opt.packpath:get(), site) then
  vim.opt.packpath:append(site)
end

return M
LUA
fi

echo "=== Done ==="
echo "Neovim: $(nvim --version | head -n 1)"
echo
echo "Next steps:"
echo "  1) Start a NEW shell (or: source ~/.bashrc)"
echo "  2) Restart tmux completely (recommended): tmux kill-server && tmux"
echo "  3) Run: nvim  (let plugins install)"

