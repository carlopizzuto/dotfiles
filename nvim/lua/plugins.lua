--  ██████╗ ██╗      ██████╗  ██████╗ ██╗   ██╗███╗   ██╗███████╗
--  ██╔══██╗██║     ██╔═══██╗██╔════╝ ██║   ██║████╗  ██║██╔════╝
--  ██████╔╝██║     ██║   ██║██║  ███╗██║   ██║██╔██╗ ██║███████╗
--  ██╔══██╗██║     ██║   ██║██║   ██║██║   ██║██║╚██╗██║╚════██║
--  ██████╔╝███████╗╚██████╔╝╚██████╔╝╚██████╔╝██║ ╚████║███████║
--  ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚══════╝
--
--  ❯  plugins.lua  (single‑file spec for lazy.nvim)

return {

	------------------------------------------------------------------
	--  0. UI
	------------------------------------------------------------------
	{ "nvim-tree/nvim-web-devicons", lazy = true },
	{
		"nvim-lualine/lualine.nvim",
		dependencies = "nvim-tree/nvim-web-devicons",
		event = "VeryLazy",
		config = function()
			require("lualine").setup({
				options = {
					icons_enabled        = true,
					theme                = "auto",
					component_separators = { left = "", right = "" },
					section_separators   = { left = "", right = "" },
					always_divide_middle = true,
					always_show_tabline  = true,
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff", "diagnostics" },
					lualine_c = { "filename" },
					lualine_x = { "encoding", "fileformat", "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
				tabline = {},
			})
		end,
	},
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		event = "VeryLazy",
		opts = {
			options = {
				diagnostics = "nvim_lsp",
				offsets = {
					{ filetype = "neo-tree", text = "File Explorer", highlight = "Directory", separator = true },
				},
				show_close_icon = false,
				separator_style = "slant",
			},
		},
	},
	{ "folke/which-key.nvim", event = "VeryLazy", opts = {} },
	{
		"gelguy/wilder.nvim",
		event = "CmdlineEnter",
		build = ":UpdateRemotePlugins",
		config = function()
			local wilder = require("wilder")
			wilder.setup({
				modes = { ":", "/", "?" },
				next_key      = "<Down>",
				previous_key  = "<Up>",
				accept_key    = "<S-CR>",
			})
			wilder.set_option("pipeline", {
				wilder.branch(
					wilder.cmdline_pipeline(),
					wilder.search_pipeline()
				),
			})
			wilder.set_option("renderer", wilder.popupmenu_renderer({
				highlighter = wilder.basic_highlighter(),
				left        = { " ", wilder.popupmenu_devicons() },
				right       = { " ", wilder.popupmenu_scrollbar() },
			}))
		end,
	},

	------------------------------------------------------------------
	--  1.  NAVIGATION / SEARCH
	------------------------------------------------------------------
	{
		"nvim-telescope/telescope.nvim",
		cmd = "Telescope",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			defaults = {
				layout_strategy      = "flex",
				file_ignore_patterns = {
					"/venv/", "/env/", "/node_modules/", "/__pycache__/", "/%.egg%-info/",
				},
				hidden = true,  -- Show dotfiles by default
			},
		},
	},
	{
		"polirritmico/telescope-lazy-plugins.nvim",
		dependencies = "nvim-telescope/telescope.nvim",
		config = function() require("telescope").load_extension("lazy_plugins") end,
	},
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
		},
		cmd = "Neotree",
		opts = {
			filesystem = {
				filtered_items = {
					visible = true,
					hide_dotfiles = false,
					hide_gitignored = false,
				},
				follow_current_file = { enabled = true },
				use_libuv_file_watcher = true,
			},
			window = {
				position = "left",
				width = 35,
			},
		},
	},

	------------------------------------------------------------------
	--  2.  EDITING AIDS
	------------------------------------------------------------------
	{ "smjonas/inc-rename.nvim", cmd = "IncRename", config = true },
	{
		"echasnovski/mini.bracketed",
		event = "BufReadPost",
		config = function()
			require("mini.bracketed").setup({
				file       = { suffix = "" },
				window     = { suffix = "" },
				quickfix   = { suffix = "" },
				yank       = { suffix = "" },
				treesitter = { suffix = "n" },
			})
		end,
	},

	------------------------------------------------------------------
	--  3.  TREESITTER & SYNTAX
	------------------------------------------------------------------
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			highlight = { enable = true },
			indent    = { enable = true },
			ensure_installed = {
				"bash", "c", "cpp", "html", "javascript", "json", "lua", "markdown",
				"markdown_inline", "python", "query", "regex", "tsx", "typescript",
				"vim", "yaml",
			},
		},
		config = function(_, opts) require("nvim-treesitter.configs").setup(opts) end,
	},


	------------------------------------------------------------------
	--  4.  LSP  +  COMPLETION +  AI
	------------------------------------------------------------------
	{
		"williamboman/mason.nvim",
		build = ":MasonUpdate",
		opts = {},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		dependencies = { "williamboman/mason.nvim" },
		opts = {
			ensure_installed        = { "lua_ls", "pyright", "rust_analyzer", "clangd" },
			automatic_installation  = true,
			automatic_enable        = true,
		},
		config = function(_, opts)
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						telemetry   = { enable = false },
					},
				},
			})

			require("mason-lspconfig").setup(opts)
		end,
	},

	{
		"github/copilot.vim",
		event = "InsertEnter",
	},
	{
		"coder/claudecode.nvim",
		dependencies = { "folke/snacks.nvim" },
		opts = {
			diff_opts = {
				open_in_new_tab = true,
				hide_terminal_in_new_tab = true,
				keep_terminal_focus = true,
			},
			terminal = {
				provider = require("claudecode_provider"),
			},
		},
		keys = {
			{ "<leader>ac", "<cmd>ClaudeCode<cr>",         desc = "Toggle Claude Code" },
			{ "<leader>an", function() require("claudecode_provider").new_session() end, desc = "New Claude session" },
			{ "<leader>a<Tab>", function() require("claudecode_provider").cycle_session() end, desc = "Cycle Claude session" },
			{ "<leader>a1", function() require("claudecode_provider").goto_session(1) end, desc = "Claude session 1" },
			{ "<leader>a2", function() require("claudecode_provider").goto_session(2) end, desc = "Claude session 2" },
			{ "<leader>a3", function() require("claudecode_provider").goto_session(3) end, desc = "Claude session 3" },
			{ "<leader>a4", function() require("claudecode_provider").goto_session(4) end, desc = "Claude session 4" },
			{ "<leader>a5", function() require("claudecode_provider").goto_session(5) end, desc = "Claude session 5" },
			{ "<leader>al", function() require("claudecode_provider").list_sessions() end, desc = "List Claude sessions" },
			{ "<leader>aR", function() require("claudecode_provider").rename_session() end, desc = "Rename Claude session" },
			{ "<leader>am", function() require("claudecode_provider").set_defaults() end, desc = "Claude model/effort" },
			{ "<leader>af", "<cmd>ClaudeCodeFocus<cr>",    desc = "Focus Claude Code" },
			{ "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude Chat" },
			{ "<leader>as", "<cmd>ClaudeCodeSend<cr>",     desc = "Send to Claude", mode = "v" },
		},
	},

	------------------------------------------------------------------
	--  4-b. nvim-cmp 
	------------------------------------------------------------------
	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter",
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			"L3MON4D3/LuaSnip",
		},
		config = function()
			local cmp = require("cmp")

			cmp.setup({
				completion = { autocomplete = false },

				snippet = {
					expand = function(args) require("luasnip").lsp_expand(args.body) end,
				},

				-- ── KEYMAPS ─────────────────────────────────────────────────
				mapping = {
					-- open the menu manually
					["<C-Space>"] = cmp.mapping.complete(),

					-- navigate with ⬆ / ⬇
					["<Up>"]      = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
					["<Down>"]    = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),

					-- ⇧ Enter  → confirm the highlighted item
					["<S-CR>"]    = cmp.mapping.confirm({ select = true }),

					-- keep <CR>, <Tab>, <S-Tab> totally free
					["<CR>"]      = cmp.config.disable,
					["<Tab>"]     = cmp.config.disable,
					["<S-Tab>"]   = cmp.config.disable,
				},
				-- SOURCES (AI first so it's preferred)
				sources = {
					{ name = "nvim_lsp" },
					{ name = "luasnip" },
				},

				-- INLINE GHOST TEXT
				experimental = {
					ghost_text = { hl_group = "Comment" },
				},
			})
		end,
	},


	------------------------------------------------------------------
	--  5.  SUPPORT LIBS
	------------------------------------------------------------------
	{ "nvim-lua/plenary.nvim", lazy = true },
	{
		"folke/snacks.nvim",
		opts = {
			terminal = {
				win = {
					keys = {
						term_normal = false,
					},
				},
			},
		},
	},
}
