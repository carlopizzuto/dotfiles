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
			local function claude_session_name()
				local ok, provider = pcall(require, "claudecode_provider")
				if not ok then return "" end
				local tab_id = vim.api.nvim_get_current_tabpage()
				local info = provider.active_session_info and provider.active_session_info(tab_id)
				local name = info and info.name or ""
				-- Truncate based on window width, leaving room for the session count
				local max = math.floor(vim.api.nvim_win_get_width(0) * 0.7)
				if #name > max then name = name:sub(1, max) .. "..." end
				return name
			end

			local function claude_session_count()
				local ok, provider = pcall(require, "claudecode_provider")
				if not ok then return "" end
				local tab_id = vim.api.nvim_get_current_tabpage()
				local info = provider.tab_session_count and provider.tab_session_count(tab_id)
				if not info or info.total <= 1 then return "" end
				return info.active .. "/" .. info.total
			end

			local function claude_model_effort()
				local ok, provider = pcall(require, "claudecode_provider")
				if not ok then return "" end
				local defaults = provider.get_defaults and provider.get_defaults() or {}
				local parts = {}
				if defaults.model then table.insert(parts, defaults.model) end
				if defaults.effort then table.insert(parts, defaults.effort) end
				if #parts == 0 then return "" end
				return table.concat(parts, " | ")
			end

			local is_claude_terminal = function()
				return vim.bo.filetype == "snacks_terminal"
			end

			local claude_extension = {
				sections = {
					lualine_a = { "mode" },
					lualine_b = { claude_model_effort },
					lualine_c = {},
					lualine_x = {},
					lualine_y = {},
					lualine_z = {},
				},
				filetypes = { "snacks_terminal" },
			}

			require("lualine").setup({
				options = {
					icons_enabled        = true,
					theme                = "auto",
					component_separators = { left = "", right = "" },
					section_separators   = { left = "", right = "" },
					always_divide_middle = true,
					always_show_tabline  = true,
					globalstatus         = false,
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff", "diagnostics" },
					lualine_c = { "filename" },
					lualine_x = { "encoding", "fileformat", "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
				winbar = {
					lualine_a = { { claude_session_name, cond = is_claude_terminal } },
					lualine_b = {},
					lualine_c = {},
					lualine_x = {},
					lualine_y = {},
					lualine_z = { { claude_session_count, cond = is_claude_terminal } },
				},
				inactive_winbar = {
					lualine_a = { { claude_session_name, cond = is_claude_terminal } },
					lualine_b = {},
					lualine_c = {},
					lualine_x = {},
					lualine_y = {},
					lualine_z = { { claude_session_count, cond = is_claude_terminal } },
				},
				tabline = {},
				extensions = { claude_extension },
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
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
		opts = {
			cmdline = {
				view = "cmdline_popup",
				format = {
					cmdline =     { icon = ">" },
					search_down = { icon = "/" },
					search_up =   { icon = "?" },
					lua =         { icon = "" },
					help =        { icon = "?" },
					filter =      { icon = "$" },
				},
			},
			popupmenu = { backend = "nui" },
			views = {
				cmdline_popup = {
					size = { width = 60 },
				},
			},
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
				},
			},
			presets = {
				bottom_search = false,         -- floating search too
				command_palette = true,         -- group cmdline + popupmenu together
				long_message_to_split = true,   -- long messages go to a split
				inc_rename = true,              -- floating input for inc-rename.nvim
			},
		},
	},
	{
		"rcarriga/nvim-notify",
		opts = {
			stages = "fade_in_slide_out",
			timeout = 3000,
			top_down = true,
		},
	},
	{
		"mrjones2014/legendary.nvim",
		priority = 10000,
		lazy = false,
		dependencies = { "folke/which-key.nvim" },
		opts = {
			extensions = {
				lazy_nvim = true,
				which_key = { auto_register = true },
			},
		},
		keys = {
			{ "<C-p>", "<cmd>Legendary<cr>", desc = "Command Palette" },
		},
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
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-cmdline",
			"dmitmel/cmp-cmdline-history",
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

			-- ── CMDLINE SHARED ─────────────────────────────────────────
			local trigger = { require("cmp.types").cmp.TriggerEvent.TextChanged }

			local cmdline_width = 53  -- 60 (noice) - 2 border - 2 padding
			local cmdline_formatting = {
				fields = { "abbr" },
				format = function(_, vim_item)
					local abbr = vim_item.abbr or ""
					if #abbr < cmdline_width then
						vim_item.abbr = abbr .. string.rep(" ", cmdline_width - #abbr)
					elseif #abbr > cmdline_width then
						vim_item.abbr = abbr:sub(1, cmdline_width - 1) .. "…"
					end
					return vim_item
				end,
			}

			-- FloatBorder fg (colored border chars) + Normal bg (no padding strip)
			local fb = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
			local nr = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
			vim.api.nvim_set_hl(0, "CmpCmdBorder", { fg = fb.fg, bg = nr.bg })

			local cmdline_window = {
				completion = {
					border        = { "", "", "", "│", "╯", "─", "╰", "│" },
					side_padding  = 1,
					zindex        = 1001,
					max_height    = 15,
					winhighlight  = "Normal:Normal,FloatBorder:CmpCmdBorder,CursorLine:Visual,Search:None",
				},
			}

			-- ── CMDLINE : ──────────────────────────────────────────────
			cmp.setup.cmdline(":", {
				completion = { autocomplete = trigger },
				mapping = cmp.mapping.preset.cmdline(),
				formatting = cmdline_formatting,
				window = cmdline_window,
				sources = {
					{ name = "cmdline_history", max_item_count = 20 },
					{ name = "cmdline" },
				},
			})

			-- ── CMDLINE / ? ────────────────────────────────────────────
			cmp.setup.cmdline({ "/", "?" }, {
				completion = { autocomplete = trigger },
				mapping = cmp.mapping.preset.cmdline(),
				formatting = cmdline_formatting,
				window = cmdline_window,
				sources = {
					{ name = "cmdline_history", max_item_count = 20 },
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
