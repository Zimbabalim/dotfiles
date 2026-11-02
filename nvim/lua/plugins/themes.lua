-- Extra dark colour schemes. They're lazy: each loads only when you preview or pick it.
-- Browse with live preview: <leader>fc (or "Colour schemes" in the <leader>p menu).
-- Your pick is remembered across restarts (see lua/plugins/theme.lua).
return {
  { "xiantang/darcula-dark.nvim", lazy = true }, -- WebStorm / IntelliJ Darcula
  { "Mofiqul/vscode.nvim", lazy = true }, -- VS Code Dark+ (colorscheme "vscode")
  { "folke/tokyonight.nvim", lazy = true }, -- tokyonight-night / -storm / -moon
  { "rebelot/kanagawa.nvim", lazy = true }, -- kanagawa-wave / -dragon
  { "rose-pine/neovim", name = "rose-pine", lazy = true }, -- rose-pine / -moon
  { "sainnhe/gruvbox-material", lazy = true },
  { "navarasu/onedark.nvim", lazy = true }, -- Atom One Dark
  { "EdenEast/nightfox.nvim", lazy = true }, -- nightfox / carbonfox / duskfox / nordfox / terafox
}
