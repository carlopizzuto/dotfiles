---@diagnostic disable: undefined-global

--  ██╗  ██╗███████╗██╗   ██╗███╗   ███╗ █████╗ ██████╗ ███████╗
--  ██║ ██╔╝██╔════╝╚██╗ ██╔╝████╗ ████║██╔══██╗██╔══██╗██╔════╝
--  █████╔╝ █████╗   ╚████╔╝ ██╔████╔██║███████║██████╔╝███████╗
--  ██╔═██╗ ██╔══╝    ╚██╔╝  ██║╚██╔╝██║██╔══██║██╔═══╝ ╚════██║
--  ██║  ██╗███████╗   ██║   ██║ ╚═╝ ██║██║  ██║██║     ███████║
--  ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝
--
--  ❯  nvim keymaps

-- open Lazy
vim.keymap.set("n", "<leader>L", "<CMD>Lazy<CR>", { desc = "Open Lazy", noremap = true, silent = true })

-- open Telescope
vim.keymap.set("n", "<leader>T", "<CMD>Telescope<CR>", { desc = "Open Telescope", noremap = true, silent = true })


-- open nvim-tree file explorer 
vim.keymap.set("n", "<leader>e", "<CMD>NvimTreeToggle<CR>", { desc = "Toggle Nvim Tree File Explorer", noremap = true, silent = true })

-- telescope keymaps
vim.keymap.set("n", "<leader>ff", "<CMD>Telescope find_files<CR>", { desc = "Find Files", silent = true })
vim.keymap.set("n", "<leader>fb", "<CMD>Telescope buffers<CR>", { desc = "Buffers" })

-- open a terminal in bottom split with a height of 20
vim.keymap.set('n', '<leader>tt', "<CMD>belowright 20split | terminal<CR><C-w>J", { desc = "Open Terminal Below", silent = true })

-- reload nvim & Lazy
vim.keymap.set('n', '<leader>R', "<CMD>Lazy sync<CR>", { desc = "Sync plugins with Lazy", silent = true })

-- exit terminal mode & go to editor above
vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n><C-w>k]], { desc = "Exit T-Mode + Focus Editor Above" })

vim.keymap.set('n', '<C-]>', [[<C-w>ja]], { desc = "Focus Terminal Below" })


