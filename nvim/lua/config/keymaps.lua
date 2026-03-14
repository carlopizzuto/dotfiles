---@diagnostic disable: undefined-global

--  ██╗  ██╗███████╗██╗   ██╗███╗   ███╗ █████╗ ██████╗ ███████╗
--  ██║ ██╔╝██╔════╝╚██╗ ██╔╝████╗ ████║██╔══██╗██╔══██╗██╔════╝
--  █████╔╝ █████╗   ╚████╔╝ ██╔████╔██║███████║██████╔╝███████╗
--  ██╔═██╗ ██╔══╝    ╚██╔╝  ██║╚██╔╝██║██╔══██║██╔═══╝ ╚════██║
--  ██║  ██╗███████╗   ██║   ██║ ╚═╝ ██║██║  ██║██║     ███████║
--  ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝
--
--  ❯  nvim keymaps

-- save
vim.keymap.set({ 'n', 'i' }, '<C-s>', '<CMD>w<CR>', { desc = "Save File", silent = true })

-- quit all (prompts to save unsaved changes)
vim.keymap.set('n', '<C-q>', '<CMD>qa<CR>', { desc = "Quit All", silent = true })

-- open Lazy
vim.keymap.set("n", "<leader>L", "<CMD>Lazy<CR>", { desc = "Open Lazy", noremap = true, silent = true })

-- open Telescope
vim.keymap.set("n", "<leader>T", "<CMD>Telescope<CR>", { desc = "Open Telescope", noremap = true, silent = true })

-- open file explorer
vim.keymap.set("n", "<leader>e", "<CMD>Neotree toggle<CR>", { desc = "Toggle File Explorer", noremap = true, silent = true })

-- telescope keymaps
vim.keymap.set("n", "<leader>ff", "<CMD>Telescope find_files<CR>", { desc = "Find Files", silent = true })
vim.keymap.set("n", "<leader>fg", "<CMD>Telescope live_grep<CR>", { desc = "Live Grep", silent = true })
vim.keymap.set("n", "<leader>fb", "<CMD>Telescope buffers<CR>", { desc = "Buffers" })
vim.keymap.set("n", "<leader>fh", "<CMD>Telescope help_tags<CR>", { desc = "Help Tags", silent = true })

-- files
vim.keymap.set('n', '<leader>bn', '<CMD>enew<CR>', { desc = "New Buffer", silent = true })
vim.keymap.set('n', '<leader>nf', function()
   vim.ui.input({ prompt = "New file: ", completion = "file" }, function(name)
      if name and name ~= '' then vim.cmd('edit ' .. name) end
   end)
end, { desc = "New File (prompt)" })
vim.keymap.set('n', '<leader>E', '<CMD>Neotree reveal<CR>', { desc = "Reveal File in Tree", silent = true })

-- buffers
vim.keymap.set('n', '<S-h>', '<CMD>bprevious<CR>', { desc = "Previous Buffer", silent = true })
vim.keymap.set('n', '<S-l>', '<CMD>bnext<CR>', { desc = "Next Buffer", silent = true })
vim.keymap.set('n', '<leader>x', '<CMD>bdelete<CR>', { desc = "Close Buffer", silent = true })
vim.keymap.set('n', '<leader>X', '<CMD>%bdelete|edit#|bdelete#<CR>', { desc = "Close All Other Buffers", silent = true })

-- navigate splits
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = "Focus Left Split", silent = true })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = "Focus Below Split", silent = true })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = "Focus Above Split", silent = true })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = "Focus Right Split", silent = true })

-- move lines in visual mode
vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv", { desc = "Move Lines Down", silent = true })
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { desc = "Move Lines Up", silent = true })

-- clear search highlight
vim.keymap.set('n', '<Esc>', '<CMD>nohlsearch<CR>', { desc = "Clear Search Highlight", silent = true })

-- open a terminal in bottom split with a height of 20
vim.keymap.set('n', '<leader>tt', "<CMD>belowright 20split | terminal<CR><C-w>J", { desc = "Open Terminal Below", silent = true })

-- reload config & sync plugins
vim.keymap.set('n', '<leader>R', '<CMD>source $MYVIMRC | Lazy sync<CR>', { desc = "Reload Config + Lazy Sync", silent = true })

-- exit terminal mode & go to editor above
vim.keymap.set('t', '<C-\\>', [[<C-\><C-n><C-w>k]], { desc = "Exit T-Mode + Focus Editor Above" })

vim.keymap.set('n', '<C-]>', [[<C-w>ja]], { desc = "Focus Terminal Below" })

-- restart nvim preserving session (requires tmux)
vim.keymap.set('n', '<leader>rr', function()
   local had_neotree = false
   -- close Neo-tree and terminal buffers (they can't be serialized)
   for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local bt = vim.bo[buf].buftype
      if ft == 'neo-tree' then
         had_neotree = true
         vim.api.nvim_win_close(win, true)
      elseif bt == 'terminal' then
         vim.api.nvim_win_close(win, true)
      end
   end
   -- wipe leftover terminal buffers
   for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == 'terminal' and vim.api.nvim_buf_is_valid(buf) then
         vim.api.nvim_buf_delete(buf, { force = true })
      end
   end

   local session_file = vim.fn.stdpath('state') .. '/restart_session.vim'
   vim.cmd('mksession! ' .. vim.fn.fnameescape(session_file))

   -- after restore: reopen Neo-tree if it was open
   local post_cmds = 'silent! call delete("' .. session_file:gsub('"', '\\"') .. '")'
   if had_neotree then
      post_cmds = post_cmds .. ' | Neotree show'
   end

   local cmd = string.format('nvim -S %s -c %s',
      vim.fn.shellescape(session_file),
      vim.fn.shellescape(post_cmds))
   vim.fn.system({ 'tmux', 'respawn-pane', '-k', cmd })
end, { desc = "Restart Neovim (tmux, preserve session)" })

-- resize panes
vim.keymap.set('n', '<C-Left>', '5<C-w><', { desc = "Decrease Width", silent = true })
vim.keymap.set('n', '<C-Right>', '5<C-w>>', { desc = "Increase Width", silent = true })
vim.keymap.set('n', '<C-Up>', '3<C-w>+', { desc = "Increase Height", silent = true })
vim.keymap.set('n', '<C-Down>', '3<C-w>-', { desc = "Decrease Height", silent = true })
