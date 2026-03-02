#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# helpers
# ----------------------------
ask_yn() {
  local prompt="${1:-Continue?}"
  local default="${2:-Y}" # Y or N
  local ans

  if [[ "$default" == "Y" ]]; then
    read -r -p "$prompt [Y/n] " ans || true
    ans="${ans:-Y}"
  else
    read -r -p "$prompt [y/N] " ans || true
    ans="${ans:-N}"
  fi

  case "$ans" in
    Y|y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------
# Privilege detection
# ----------------------------
if [[ $EUID -eq 0 ]]; then
  SUDO=""
  echo "Running as root; sudo not needed."
elif have_cmd sudo; then
  SUDO="sudo"
else
  echo "ERROR: Not running as root and 'sudo' is not available." >&2
  echo "Re-run as root, or install sudo first." >&2
  exit 1
fi

echo "=== Updating system ==="
$SUDO apt update

echo "=== Installing base packages ==="
$SUDO apt install -y \
  git curl unzip tar ca-certificates \
  build-essential cmake gettext ninja-build \
  ripgrep fd-find \
  xclip wl-clipboard \
  ncurses-term

# Ensure fd exists (Debian calls it fdfind)
if ! have_cmd fd && have_cmd fdfind; then
  $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd
fi

# ----------------------------
# Optional: tmux
# ----------------------------
INSTALL_TMUX=false
if ask_yn "Install tmux + apply tmux config tweaks?" "Y"; then
  INSTALL_TMUX=true
  echo "=== Installing tmux ==="
  $SUDO apt install -y tmux
fi

# ----------------------------
# Neovim install
# ----------------------------
# Override: NVIM_VERSION=v0.11.5 ./install_nvim_nvchad.sh
NVIM_VERSION="${NVIM_VERSION:-v0.11.5}"
SKIP_NVIM=false

if have_cmd nvim; then
  NVIM_EXISTING_PATH="$(command -v nvim)"
  NVIM_EXISTING_VER="$(nvim --version 2>/dev/null | head -n 1)"
  echo ""
  echo "=== Neovim already installed ==="
  echo "  Path:    $NVIM_EXISTING_PATH"
  echo "  Version: $NVIM_EXISTING_VER"
  echo "  Target:  $NVIM_VERSION"
  if ! ask_yn "Overwrite existing Neovim with $NVIM_VERSION?" "N"; then
    echo "Skipping Neovim install."
    SKIP_NVIM=true
  fi
fi

if ! $SKIP_NVIM; then
  echo "=== Removing Debian neovim (if installed) to avoid PATH override ==="
  $SUDO apt remove -y neovim || true

  echo "=== Installing Neovim (stable release tarball) ==="
  NVIM_TAR="nvim-linux-x86_64.tar.gz"
  NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TAR}"

  cd /tmp
  curl -fLO "$NVIM_URL"

  $SUDO rm -rf /opt/nvim
  $SUDO tar -C /opt -xzf "$NVIM_TAR"
  $SUDO mv /opt/nvim-linux-x86_64 /opt/nvim
  rm -f "$NVIM_TAR"

  # Make /usr/local/bin/nvim the canonical nvim
  $SUDO ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  hash -r

  echo "=== Neovim version ==="
  nvim --version | head -n 3
fi

# ----------------------------
# Optional: tmux config + TERM cleanup
# ----------------------------
if $INSTALL_TMUX; then
  echo "=== Removing TERM override from ~/.bashrc if present (tmux sets TERM itself) ==="
  if [[ -f ~/.bashrc ]]; then
    sed -i '/^[[:space:]]*export[[:space:]]\+TERM=xterm-256color[[:space:]]*$/d' ~/.bashrc
  fi

  echo "=== Writing tmux config (focus-events + truecolor + sane TERM) ==="
  TMUXCONF="$HOME/.tmux.conf"
  [[ -f "$TMUXCONF" ]] || touch "$TMUXCONF"

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
fi

# ----------------------------
# Optional: OpenCode CLI
# ----------------------------
INSTALL_OPENCODE=false
if ask_yn "Install OpenCode CLI (opencode)?" "Y"; then
  INSTALL_OPENCODE=true
  echo "=== Installing OpenCode CLI ==="
  # Official installer (Linux): curl -fsSL https://opencode.ai/install | bash
  curl -fsSL https://opencode.ai/install | bash

  # Try to ensure common install location is on PATH for new shells
  # (Installer usually handles this, but we add a safe fallback)
  if [[ -f ~/.bashrc ]]; then
    if ! grep -q 'HOME/.local/bin' ~/.bashrc; then
      echo '' >> ~/.bashrc
      echo '# OpenCode (fallback PATH)' >> ~/.bashrc
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
  fi

  # Current shell PATH refresh (best effort)
  export PATH="$HOME/.local/bin:$PATH"

  if have_cmd opencode; then
    echo "OpenCode: $(opencode --version 2>/dev/null || echo 'installed')"
  else
    echo "WARNING: opencode not found on PATH yet. Open a new shell, then run: opencode --version"
  fi
fi

# ----------------------------
# Fresh NvChad install
# ----------------------------
echo "=== Removing old Neovim config/state (fresh NvChad install) ==="
rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim

echo "=== Installing NvChad ==="
git clone https://github.com/NvChad/starter ~/.config/nvim

# ----------------------------
# Add your NvChad customizations
# ----------------------------
echo "=== Writing NvChad custom files ==="
mkdir -p ~/.config/nvim/lua/custom

# Minimal chadrc (keep your runtimepath tweak, harmless)
cat > ~/.config/nvim/lua/custom/chadrc.lua <<'LUA'
---@type ChadrcConfig
local M = {}

-- Ensure Neovim can see stdpath("data") site dir if tools use it
local site = vim.fn.stdpath("data") .. "/site"
if not vim.tbl_contains(vim.opt.runtimepath:get(), site) then
  vim.opt.runtimepath:append(site)
end
if not vim.tbl_contains(vim.opt.packpath:get(), site) then
  vim.opt.packpath:append(site)
end

M.plugins = "custom.plugins"
M.mappings = require "custom.mappings"

return M
LUA

# Mappings: add terminal Esc to exit, keep your examples
cat > ~/.config/nvim/lua/custom/mappings.lua <<'LUA'
---@type MappingsTable
local M = {}

M.general = {
  n = {
    [";"] = { ":", "enter command mode", opts = { nowait = true } },
  },

  v = {
    [">"] = { ">gv", "indent" },
  },

  -- Terminal mode: make Esc exit terminal insert-mode (super useful for OpenCode)
  t = {
    ["<Esc>"] = { [[<C-\><C-n>]], "exit terminal mode" },
  },
}

return M
LUA

# Plugins: your overrides + opencode.nvim integration (only useful if opencode CLI is installed)
cat > ~/.config/nvim/lua/custom/plugins.lua <<'LUA'
local overrides = require("custom.configs.overrides")

---@type NvPluginSpec[]
local plugins = {

  -- Override plugin definition options
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      {
        "jose-elias-alvarez/null-ls.nvim",
        config = function()
          require "custom.configs.null-ls"
        end,
      },
    },
    config = function()
      require "plugins.configs.lspconfig"
      require "custom.configs.lspconfig"
    end,
  },

  -- Override plugin configs
  { "williamboman/mason.nvim", opts = overrides.mason },
  { "nvim-treesitter/nvim-treesitter", opts = overrides.treesitter },
  { "nvim-tree/nvim-tree.lua", opts = overrides.nvimtree },

  -- Install a plugin
  {
    "max397574/better-escape.nvim",
    event = "InsertEnter",
    config = function()
      require("better_escape").setup()
    end,
  },

  -- OpenCode (lazy-load on keypress)
  {
    "nickjvandyke/opencode.nvim",
    version = "*",
    keys = {
      { "<C-a>", mode = { "n", "x" }, desc = "Ask opencode…" },
      { "<C-x>", mode = { "n", "x" }, desc = "Opencode actions…" },
      -- Terminals often swallow Ctrl+.; keep it, but also provide a reliable leader map:
      { "<C-.>", mode = { "n", "t" }, desc = "Toggle opencode" },
      { "<leader>oc", mode = { "n" }, desc = "Toggle opencode" },
    },
    dependencies = {
      { "folke/snacks.nvim", optional = true },
    },
    config = function()
      vim.g.opencode_opts = {}
      vim.o.autoread = true

      vim.keymap.set({ "n", "x" }, "<C-a>", function()
        require("opencode").ask("@this: ", { submit = true })
      end, { desc = "Ask opencode…" })

      vim.keymap.set({ "n", "x" }, "<C-x>", function()
        require("opencode").select()
      end, { desc = "Opencode actions…" })

      vim.keymap.set({ "n", "t" }, "<C-.>", function()
        require("opencode").toggle()
      end, { desc = "Toggle opencode" })

      vim.keymap.set("n", "<leader>oc", function()
        require("opencode").toggle()
      end, { desc = "Toggle opencode" })
    end,
  },
}

return plugins
LUA

# Note: overrides/null-ls/lspconfig files are your existing custom files.
# If you don't have them yet, NvChad will error until you add them.
# (If you want, we can make the script create stubs automatically.)

echo "=== Done ==="
echo "Neovim: $(nvim --version | head -n 1)"
echo
echo "Next steps:"
echo "  1) Start a NEW shell (or: source ~/.bashrc)"
if $INSTALL_TMUX; then
  echo "  2) Restart tmux completely (recommended): tmux kill-server && tmux"
fi
echo "  3) Run: nvim   (let plugins install)"
if $INSTALL_OPENCODE; then
  echo "  4) In Neovim: <leader>oc toggles OpenCode (Space o c)"
  echo "     In OpenCode terminal: Esc exits terminal insert-mode"
else
  echo "  (OpenCode CLI not installed; opencode.nvim will still install but needs 'opencode' on PATH to work)"
fi
