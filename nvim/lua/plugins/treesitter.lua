-- nvim-treesitter `main` branch (the rewrite). It only installs parsers now;
-- highlighting/indent are enabled per-buffer via the FileType autocmd below.
-- Requires the `tree-sitter` CLI (brew install tree-sitter-cli) and a C compiler.
-- Incremental selection is built into Neovim 0.12: in visual mode press `an` to
-- expand to the parent node, `in` to shrink.
local languages = {
  -- Frontend (your primary stack)
  "javascript",
  "typescript",
  "tsx",
  "html",
  "css",
  "scss",
  "json",
  -- Occasional languages
  "rust",
  "c_sharp",
  -- Config / tooling
  "lua",
  "bash",
  "fish",
  "yaml",
  "toml",
  "markdown",
  "markdown_inline",
  "regex",
  "gitcommit",
  "gitignore",
  "diff",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false, -- main branch does not support lazy-loading
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install(languages)

    vim.api.nvim_create_autocmd("FileType", {
      callback = function(args)
        -- pcall: silently skip filetypes with no parser installed
        if pcall(vim.treesitter.start, args.buf) then
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
}
