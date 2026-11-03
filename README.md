# dotfiles

nvim (WebStorm-ish) + iTerm profile + Claude Code status line, for macOS.

## New machine

1. Copy this folder to `~/dotfiles`.
2. Run `cd ~/dotfiles && ./setup.sh`
   - installs anything missing via Homebrew: nvim (0.12+), tree-sitter, ripgrep, node, git, JetBrainsMono Nerd Font
   - links `~/.config/nvim` → `nvim/` and `~/.claude/statusline-tee.sh` → `claude/statusline-tee.sh`
   - points Claude Code's status line at that script (in `~/.claude/settings.json`)
   - adds the iTerm profile "Dotfiles"
   - installs nvim plugins at the versions pinned in `nvim/lazy-lock.json`
   Anything it replaces is kept as `<name>.bak-<timestamp>`.
3. In iTerm: Settings → Profiles → **Dotfiles** → Other Actions… → **Set as Default**.
4. Optional, for the full Claude status line, inside Claude Code:
   `/plugin marketplace add jarrodwatts/claude-hud` then `/plugin install claude-hud`.
5. Open nvim. The first launch finishes installing language parsers and servers.

## Keeping machines in step

`~/.config/nvim` is a link into this folder, so nvim changes land here automatically.
Copy the folder across again and re-run `./setup.sh --link-only` (safe to repeat).

If you change the iTerm profile, re-export it into `iterm/Dotfiles.json`
(iTerm → Settings → Profiles → Other Actions… → Save Profile as JSON; keep the `Name` and `Guid`).

## Keys (Space = leader)

| Key | What |
|---|---|
| `Space p` | Panel menu |
| `Space e` | File tree |
| `Space t` | Terminal column, open at startup (Ctrl-Space to leave typing mode) |
| `Space ai` | Claude context / usage / tasks / files card |
| `Space ac` | Claude conversation tab: your prompts on the left, the whole turn on the right (y = copy reply) |
| `Space gd` | Git changes |
| `Space b` | Beads tab: issues on the left, details of the one under the cursor on the right (Enter = into details, q = back; Space b again = previous tab) |
| `Space Space` | Find files |
| `Space fc` | Colour schemes (live preview) |
| `Space o` / `P` in tree | Quick Look (images, PDFs, video) |
| `:qa` / `:q` | Asks first if the terminal is still running (`:qa!` skips) |
