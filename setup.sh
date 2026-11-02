#!/bin/bash
# Set up this Mac with the nvim + iTerm + Claude Code workspace from this folder.
#
#   ./setup.sh              install missing tools (Homebrew), link configs, add the iTerm profile
#   ./setup.sh --link-only  only link configs (no installs, no iTerm profile)
#
# Safe to re-run. Anything it replaces is moved aside with a .bak-<timestamp> suffix.

set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)
LINK_ONLY=false
[ "${1:-}" = "--link-only" ] && LINK_ONLY=true

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }

# Move an existing file/dir/link out of the way (unless it's already the right symlink), then link.
link() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    note "already linked: $dest"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mv "$dest" "$dest.bak-$STAMP"
    note "backed up: $dest -> $dest.bak-$STAMP"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  note "linked: $dest -> $src"
}

# ── 1. Tools ────────────────────────────────────────────────────────────────
if ! $LINK_ONLY; then
  say "Checking tools"

  if ! xcode-select -p >/dev/null 2>&1; then
    warn "Xcode command line tools are missing (needed to build plugins)."
    xcode-select --install || true
    warn "Finish that installer, then run ./setup.sh again."
    exit 1
  fi
  note "Xcode command line tools: ok"

  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew isn't installed. Install it from https://brew.sh, then run ./setup.sh again."
    exit 1
  fi

  formulae=()
  nvim_ok=false
  if command -v nvim >/dev/null 2>&1; then
    v=$(nvim --version | head -1 | sed -E 's/^NVIM v([0-9]+)\.([0-9]+).*/\1 \2/')
    read -r major minor <<<"$v"
    [ "$major" -gt 0 ] || [ "$minor" -ge 12 ] && nvim_ok=true
  fi
  $nvim_ok || formulae+=(neovim)
  command -v tree-sitter >/dev/null 2>&1 || formulae+=(tree-sitter-cli)
  command -v rg >/dev/null 2>&1 || formulae+=(ripgrep)
  command -v node >/dev/null 2>&1 || formulae+=(node)
  command -v git >/dev/null 2>&1 || formulae+=(git)

  if [ ${#formulae[@]} -gt 0 ]; then
    note "installing: ${formulae[*]}"
    brew install "${formulae[@]}"
  else
    note "nvim, tree-sitter, ripgrep, node, git: ok"
  fi

  if ! ls ~/Library/Fonts/JetBrainsMonoNerdFont* /Library/Fonts/JetBrainsMonoNerdFont* >/dev/null 2>&1; then
    note "installing JetBrainsMono Nerd Font"
    brew install --cask font-jetbrains-mono-nerd-font
  else
    note "JetBrainsMono Nerd Font: ok"
  fi

  v=$(nvim --version | head -1)
  case "$v" in
    "NVIM v0.1"[2-9]* | "NVIM v0.[2-9]"* | "NVIM v"[1-9]*) note "$v" ;;
    *) warn "$v: this config needs nvim 0.12 or newer. Update with: brew upgrade neovim" ;;
  esac
fi

# ── 2. nvim config ──────────────────────────────────────────────────────────
say "Linking nvim config"
link "$DOTFILES/nvim" "$HOME/.config/nvim"

# ── 3. Claude Code status line (feeds the nvim context card) ────────────────
say "Claude Code status line"
link "$DOTFILES/claude/statusline-tee.sh" "$HOME/.claude/statusline-tee.sh"
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak-$STAMP"
if /usr/bin/python3 -I - "$settings" "$HOME/.claude/statusline-tee.sh" <<'EOF'
import json, sys
path, script = sys.argv[1], sys.argv[2]
d = json.load(open(path))
if (d.get("statusLine") or {}).get("command") == script:
    sys.exit(1)  # already set
d["statusLine"] = {"type": "command", "command": script}
json.dump(d, open(path, "w"), indent=2)
EOF
then
  note "set statusLine in $settings (previous copy: $settings.bak-$STAMP)"
else
  rm -f "$settings.bak-$STAMP"
  note "statusLine already set in $settings"
fi
if ! ls -d "$HOME"/.claude/plugins/cache/*/claude-hud/*/ >/dev/null 2>&1; then
  warn "claude-hud isn't installed, so the status line will be a simple one-liner."
  warn "To get it, run these inside Claude Code:"
  warn "  /plugin marketplace add jarrodwatts/claude-hud"
  warn "  /plugin install claude-hud"
fi

# ── 4. iTerm profile ────────────────────────────────────────────────────────
if ! $LINK_ONLY; then
  say "iTerm profile"
  dyn="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  mkdir -p "$dyn"
  cp "$DOTFILES/iterm/Dotfiles.json" "$dyn/Dotfiles.json"
  note "added profile \"Dotfiles\" (iTerm picks it up straight away)."
  note "Make it the default: iTerm > Settings > Profiles > select Dotfiles > Other Actions… > Set as Default"
fi

# ── 5. nvim plugins ─────────────────────────────────────────────────────────
if ! $LINK_ONLY; then
  say "Installing nvim plugins (pinned versions from lazy-lock.json)"
  nvim --headless "+Lazy! restore" +qa
  note "Language parsers and language servers finish installing the first time you open nvim."
fi

say "Done"
