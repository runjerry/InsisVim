local cfg = require("insis").config
local myAutoGroup = vim.api.nvim_create_augroup("myAutoGroup", {
  clear = true,
})

local autocmd = vim.api.nvim_create_autocmd

-- Option 1: Dim inactive windows (apply after colorscheme loads)
-- Use a lighter/grayer background for inactive windows to make active window pop
local function set_inactive_highlights()
  vim.api.nvim_set_hl(0, "NormalNC", { bg = "#181820" })
  vim.api.nvim_set_hl(0, "LineNrNC", { bg = "#181820", fg = "#3a3a4a" })
  vim.api.nvim_set_hl(0, "SignColumnNC", { bg = "#181820" })
end
autocmd("ColorScheme", {
  group = myAutoGroup,
  pattern = "*",
  callback = set_inactive_highlights,
})
-- Also apply immediately for initial load
set_inactive_highlights()

-- Apply winhighlight for inactive windows to affect line numbers
autocmd({ "WinLeave" }, {
  group = myAutoGroup,
  pattern = "*",
  callback = function()
    vim.wo.winhighlight = "Normal:NormalNC,LineNr:LineNrNC,SignColumn:SignColumnNC"
  end,
})
autocmd({ "WinEnter", "BufEnter" }, {
  group = myAutoGroup,
  pattern = "*",
  callback = function()
    vim.wo.winhighlight = ""
  end,
})

-- Option 2: Only show cursorline of the active window
autocmd({ "WinEnter", "BufEnter" }, {
  group = myAutoGroup,
  pattern = "*",
  callback = function()
    vim.wo.cursorline = true
  end,
})
autocmd({ "WinLeave" }, {
  group = myAutoGroup,
  pattern = "*",
  callback = function()
    vim.wo.cursorline = false
  end,
})

if cfg.enable_imselect then
  autocmd("InsertLeave", {
    group = myAutoGroup,
    callback = require("insis.utils.im-select").insertLeave,
  })

  autocmd("InsertEnter", {
    group = myAutoGroup,
    callback = require("insis.utils.im-select").insertEnter,
  })
end

-- auto insert mode when TermOpen
autocmd("TermOpen", {
  group = myAutoGroup,
  command = "startinsert",
})

-- format on save
autocmd("BufWritePre", {
  group = myAutoGroup,
  pattern = require("insis.env").getFormatOnSavePattern(),
  callback = function()
    vim.lsp.buf.format()
  end,
})

-- set *.mdx to filetype to markdown
autocmd({ "BufNewFile", "BufRead" }, {
  group = myAutoGroup,
  pattern = "*.mdx",
  command = "setfiletype markdown",
})

-- set wrap only in markdown
autocmd("FileType", {
  group = myAutoGroup,
  pattern = { "markdown" },
  callback = function()
    if cfg.markdown then
      vim.opt_local.wrap = cfg.markdown.wrap
      vim.wo.wrap = cfg.markdown.wrap
    end
  end,
})

-- highlight on yank
autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank()
  end,
  group = myAutoGroup,
  pattern = "*",
})

-- https://www.reddit.com/r/neovim/comments/zc720y/tip_to_manage_hlsearch/
vim.on_key(function(char)
  if vim.fn.mode() == "n" then
    vim.opt.hlsearch = vim.tbl_contains({ "<CR>", "n", "N", "*", "#", "?", "/" }, vim.fn.keytrans(char))
  end
end, vim.api.nvim_create_namespace("auto_hlsearch"))

-- do not continue comments when type o
autocmd("BufEnter", {
  group = myAutoGroup,
  pattern = "*",
  callback = function()
    vim.opt.formatoptions = vim.opt.formatoptions
      - "o" -- O and o, don't continue comments
      + "r" -- But do continue when pressing enter.
  end,
})

autocmd({ "FileType" }, {
  group = myAutoGroup,
  pattern = {
    "help",
    "man",
    "neotest-output",
  },
  callback = function()
    keymap({ "i", "n" }, { "q", "<esc>" }, "<esc>:close<CR>", { buffer = true })
  end,
})

-- -- save fold
-- autocmd("BufWinEnter", {
--   group = myAutoGroup,
--   pattern = "*",
--   command = "silent! loadview",
-- })
--
-- autocmd("BufWrite", {
--   group = myAutoGroup,
--   pattern = "*",
--   command = "mkview",
-- })
