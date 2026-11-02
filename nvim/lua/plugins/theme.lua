return {
  "marko-cerovac/material.nvim",
  lazy = false,
  priority = 1000, -- load before everything else
  config = function()
    require("material").setup({
      contrast = {
        terminal = true,
        sidebars = true,
        floating_windows = true,
      },
      plugins = {
        "gitsigns",
        "neo-tree",
        "telescope",
        "nvim-cmp",
        "indent-blankline",
      },
      high_visibility = {
        lighter = false,
        darker = true,
      },
    })
    vim.g.material_style = "deep ocean"

    -- Remember the last colour scheme you picked (e.g. from <leader>fc); default to material.
    local saved_file = vim.fn.stdpath("data") .. "/colorscheme.txt"
    local saved = vim.fn.filereadable(saved_file) == 1 and vim.fn.readfile(saved_file)[1] or nil
    if not (saved and pcall(vim.cmd.colorscheme, saved)) then
      vim.cmd.colorscheme("material")
    end
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function(args)
        if args.match ~= "" then vim.fn.writefile({ args.match }, saved_file) end
      end,
    })
  end,
}
