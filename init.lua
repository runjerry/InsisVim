require("insis").setup({
  colorscheme = "moonfly",
  cmp = {
    -- 启用 copilot
    copilot = true,
  },
  python = {
    enable = true,
    -- can be pylsp or pyright
    lsp = "pylsp",
    -- pip install black
    -- asdf reshim python
    formatter = "black",
    format_on_save = false,
  },
})
