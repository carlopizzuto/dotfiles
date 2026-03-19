---@diagnostic disable: undefined-global

--   ██████╗ ██████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
--  ██╔═══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
--  ██║   ██║██████╔╝   ██║   ██║██║   ██║██╔██╗ ██║███████╗
--  ██║   ██║██╔═══╝    ██║   ██║██║   ██║██║╚██╗██║╚════██║
--  ╚██████╔╝██║        ██║   ██║╚██████╔╝██║ ╚████║███████║
--   ╚═════╝ ╚═╝        ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
--
--  ❯  nvim options

-- setting leaders
vim.g.mapleader		= " "
vim.g.maplocalleader 	= "\\"

-- sync with system clipboard
vim.opt.clipboard = vim.env.SSH_TTY and "" or "unnamedplus" 

-- enable line numbers
vim.opt.number = true

-- make each shift 5 spaces long
vim.opt.shiftwidth = 5
-- make each tab 5 spaces long
vim.opt.tabstop = 5

-- open horizontal split on the right
vim.opt.splitright = true

-- hide cmdline when not in use (noice.nvim handles display)
vim.opt.cmdheight = 0

-- live preview for substitutions (:s/foo/bar)
vim.opt.inccommand = "split"


-- diagnostics
vim.diagnostic.config({
  virtual_text  = true,   -- show the little inline messages
  signs         = true,   -- the W / E icons in the sign column
  underline     = true,
  severity_sort = true,
  update_in_insert = true, -- update diagnostics in insert mode
})
