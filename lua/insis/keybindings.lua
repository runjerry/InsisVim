-- For common keybindings -------------------------------

-- Modes
--   normal_mode = "n",
--   insert_mode = "i",
--   visual_mode = "v",
--   visual_block_mode = "x",
--   term_mode = "t",
--   command_mode = "c",
---------------------------------------------------------

local cfg = require("insis").config
local keys = cfg.keys
if not keys then
  return
end

-- leader key
vim.g.mapleader = keys.leader_key
vim.g.maplocalleader = keys.leader_key

-- save && quit
keymap("n", keys.n_save, "<CMD>w<CR>")
keymap("n", keys.n_force_quit, "<CMD>qa!<CR>")
-- keymap("n", keys.n_save_quit, "<CMD>wq<CR>")
-- keymap("n", keys.n_save_all, "<CMD>wa<CR>")
-- keymap("n", keys.n_save_all_quit, "<CMD>wqa<CR>")

-- $ jump to the end without space (swap $ and g_)
keymap({ "v", "n" }, "$", "g_")
keymap({ "v", "n" }, "g_", "$")

keymap({ "n", "v" }, keys.n_v_5j, "5j")
keymap({ "n", "v" }, keys.n_v_5k, "5k")

keymap({ "n", "v" }, keys.n_v_10j, "10j")
keymap({ "n", "v" }, keys.n_v_10k, "10k")

-- very magic search mode
if cfg.enable_very_magic_search then
  keymap({ "n", "v" }, "/", "/\\v", {
    remap = false,
    silent = false,
  })
  keymap("c", "s/", "s/\\v", {
    remap = false,
    silent = false,
  })
end

-------------------- fix ------------------------------

local opts_expr = {
  expr = true,
  silent = true,
}
local opt = {
  noremap = true,
  silent = true,
}

-- fix :set wrap
keymap("n", "j", "v:count == 0 ? 'gj' : 'j'", opts_expr)
keymap("n", "k", "v:count == 0 ? 'gk' : 'k'", opts_expr)

-- visual模式下缩进代码
keymap("v", "<", "<gv")
keymap("v", ">", ">gv")

-- visual block move selection
keymap("n", "<C-g>", "<C-q>", opt)

-- 上下移动选中文本
keymap("x", "J", ":move '>+1<CR>gv-gv")
keymap("x", "K", ":move '<-2<CR>gv-gv")

-- 在visual mode 里粘贴不要复制
keymap("x", "p", '"_dP')

-- copy and paste between nvim and everything else
keymap("v", "<C-c>", '"+y', opt)
keymap("n", "<C-c>", '"+y', opt)
keymap("n", "<C-v>", '"+p', opt)

-- beter navigation
keymap("n", "<C-u>", "<C-d>", opt)
keymap("n", "<C-d>", "<C-y>", opt)
keymap("n", "<C-f>", "<C-e>", opt)
keymap("n", "<C-e>", "<C-u>", opt)

-- hide highlight
keymap("n", "cc", ":let @/ = ''<CR>", opt)

-- -- comment
-- keymap("v", "gcap", "gcip", { noremap = false })
-- keymap("n", "gcap", "gcip", { noremap = false })

-- better indenting in visual mode
keymap("v", "<TAB>", ">gv", opt)
keymap("v", "<S-TAB>", "<gv", opt)

-- for debug
keymap("i", "<F9>", "breakpoint()", opt)

--------------- super window -----------------------

if cfg.s_windows ~= nil and cfg.s_windows.enable then
  local skey = cfg.s_windows.keys
  keymap("n", "s", "")
  keymap("n", skey.split_vertically, ":vsp<CR>")
  keymap("n", skey.split_horizontally, ":sp<CR>")
  keymap("n", skey.close, "<C-w>c")
  keymap("n", skey.close_others, "<C-w>o") -- close others
  keymap("n", skey.jump_left, "<C-w>h")
  keymap("n", skey.jump_down, "<C-w>j")
  keymap("n", skey.jump_up, "<C-w>k")
  keymap("n", skey.jump_right, "<C-w>l")
  keymap("n", skey.width_decrease, ":vertical resize -10<CR>")
  keymap("n", skey.width_increase, ":vertical resize +10<CR>")
  keymap("n", skey.height_decrease, ":horizontal resize -10<CR>")
  keymap("n", skey.height_increase, ":horizontal resize +10<CR>")
  keymap("n", skey.size_equal, "<C-w>=")
end

-------------- super tab ---------------------------

if cfg.s_tab ~= nil and cfg.s_tab.enable then
  local tkey = cfg.s_tab.keys
  keymap("n", tkey.split, "<CMD>tab split<CR>")
  keymap("n", tkey.close, "<CMD>tabclose<CR>")
  keymap("n", tkey.next, "<CMD>tabnext<CR>")
  keymap("n", tkey.prev, "<CMD>tabprev<CR>")
  keymap("n", tkey.first, "<CMD>tabfirst<CR>")
  keymap("n", tkey.last, "<CMD>tablast<CR>")
end

-- Esc back to Normal mode
keymap("t", keys.terminal_to_normal, "<C-\\><C-n>")

-- DEPRECATED :Terminal kes

keymap("n", "t", ":terminal<CR>", opt)
keymap("n", "t-", ":sp | terminal<CR>", opt)
keymap("n", "t\\", ":vsp | terminal<CR>", opt)
keymap("t", "<C-h>", [[ <C-\><C-N><C-w>h ]], opt)
keymap("t", "<C-j>", [[ <C-\><C-N><C-w>j ]], opt)
keymap("t", "<C-k>", [[ <C-\><C-N><C-w>k ]], opt)
keymap("t", "<C-l>", [[ <C-\><C-N><C-w>l ]], opt)
keymap("t", "<leader>h", [[ <C-\><C-N><C-w>h ]], opt)
keymap("t", "<leader>j", [[ <C-\><C-N><C-w>j ]], opt)
keymap("t", "<leader>k", [[ <C-\><C-N><C-w>k ]], opt)
keymap("t", "<leader>l", [[ <C-\><C-N><C-w>l ]], opt)
