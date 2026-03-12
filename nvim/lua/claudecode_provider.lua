-- Multi-session terminal provider for claudecode.nvim
-- Each Neovim tab gets its own independent Claude Code session.
-- Patches claudecode.nvim's broadcast so MCP events (file mentions,
-- diffs, selections) are routed only to the current tab's client.

local M = {}

local State = {
	terminals = {}, -- tab_id -> { instance: snacks.win, bufnr: number }
	clients = {}, -- tab_id -> client_id
	connecting = nil, -- tab_id awaiting connection
	patched = { on_connect = false, on_disconnect = false, broadcast = false },
}

----------------------------------------------------------------
--  Access claudecode.nvim internals
----------------------------------------------------------------

local function get_root_server()
	local ok, cc = pcall(require, "claudecode")
	if ok and cc.state and cc.state.server then
		return cc.state.server
	end
end

local function get_tcp_server()
	local ok, cc = pcall(require, "claudecode")
	if ok and cc.state and cc.state.server and cc.state.server.state and cc.state.server.state.server then
		return cc.state.server.state.server
	end
end

local function get_tcp_client_ids()
	local srv = get_tcp_server()
	return srv and srv.clients and vim.tbl_keys(srv.clients) or {}
end

----------------------------------------------------------------
--  Terminal helpers
----------------------------------------------------------------

local function term_is_valid(t)
	return t and t.instance and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr)
end

local function term_is_visible(t)
	return t and t.instance and t.instance.win and vim.api.nvim_win_is_valid(t.instance.win)
end

local function term_focus(t)
	if t.instance.win and vim.api.nvim_win_is_valid(t.instance.win) then
		vim.api.nvim_set_current_win(t.instance.win)
		vim.cmd("startinsert")
	end
end

----------------------------------------------------------------
--  Monkey-patches (applied once, route MCP events per-tab)
----------------------------------------------------------------

local function ensure_patches()
	-- on_connect: track which client belongs to which tab
	if not State.patched.on_connect then
		local tcp = get_tcp_server()
		if tcp then
			local orig = tcp.on_connect
			tcp.on_connect = function(client)
				orig(client)
				vim.schedule(function()
					local tcp_set = {}
					for _, id in ipairs(get_tcp_client_ids()) do
						tcp_set[id] = true
					end
					if not tcp_set[client.id] then
						return
					end -- ghost client
					local tab_id = State.connecting
					if tab_id and State.terminals[tab_id] and not State.clients[tab_id] then
						State.clients[tab_id] = client.id
						State.connecting = nil
					end
				end)
			end
			State.patched.on_connect = true
		end
	end

	-- on_disconnect: remove client mapping
	if not State.patched.on_disconnect then
		local tcp = get_tcp_server()
		if tcp then
			local orig = tcp.on_disconnect
			tcp.on_disconnect = function(client, code, reason)
				orig(client, code, reason)
				for tab_id, cid in pairs(State.clients) do
					if cid == client.id then
						State.clients[tab_id] = nil
						break
					end
				end
			end
			State.patched.on_disconnect = true
		end
	end

	-- broadcast: scope events to current tab's client only
	if not State.patched.broadcast then
		local server = get_root_server()
		if server and server.broadcast then
			server.broadcast = function(event, data)
				local tab_id = vim.api.nvim_get_current_tabpage()
				local client_id = State.clients[tab_id]
				if not client_id then
					return false
				end
				if server.state and server.state.clients then
					local client = server.state.clients[client_id]
					if client then
						return server.send(client, event, data)
					end
				end
				return false
			end
			State.patched.broadcast = true
		end
	end
end

----------------------------------------------------------------
--  Terminal lifecycle
----------------------------------------------------------------

local function build_opts(config, env_table, should_focus, tab_id)
	return {
		count = tab_id,
		env = env_table,
		cwd = config.cwd,
		start_insert = should_focus,
		auto_insert = should_focus,
		auto_close = false,
		win = vim.tbl_deep_extend("force", {
			position = config.split_side,
			width = config.split_width_percentage,
			height = 0,
			relative = "editor",
			wo = { winfixwidth = true, wrap = true },
			keys = {
				term_normal = false,
				claude_new_line = {
					"<S-CR>",
					function()
						vim.api.nvim_feedkeys("\\", "t", true)
						vim.defer_fn(function()
							vim.api.nvim_feedkeys("\r", "t", true)
						end, 10)
					end,
					mode = "t",
					desc = "New line",
				},
			},
		}, config.snacks_win_opts or {}),
	}
end

local function create_terminal(cmd_string, env_table, config, should_focus, tab_id)
	local opts = build_opts(config, env_table, should_focus, tab_id)
	local ok, term = pcall(Snacks.terminal.open, cmd_string, opts)
	if not ok or not term or not term:buf_valid() then
		return
	end

	State.terminals[tab_id] = { instance = term, bufnr = term.buf }

	-- Disable horizontal trackpad scrolling inside the Claude terminal
	for _, mode in ipairs({ "t", "n" }) do
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<ScrollWheelLeft>", "", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<ScrollWheelRight>", "", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<S-ScrollWheelLeft>", "", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<S-ScrollWheelRight>", "", { noremap = true, silent = true })
	end

	if config.auto_close then
		term:on("TermClose", function()
			State.terminals[tab_id] = nil
			State.clients[tab_id] = nil
			vim.schedule(function()
				term:close({ buf = true })
				vim.cmd.checktime()
			end)
		end, { buf = true })
	end

	term:on("BufWipeout", function()
		State.terminals[tab_id] = nil
		State.clients[tab_id] = nil
	end, { buf = true })
end

local function cleanup_closed_tabs()
	local active = {}
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		active[tab] = true
	end
	for tab_id, t in pairs(State.terminals) do
		if not active[tab_id] then
			if t.instance then
				pcall(function()
					t.instance:close()
				end)
			end
			State.clients[tab_id] = nil
			State.terminals[tab_id] = nil
		end
	end
end

----------------------------------------------------------------
--  Provider interface (required by claudecode.nvim)
----------------------------------------------------------------

function M.setup(_config)
	vim.api.nvim_create_autocmd("TabClosed", {
		group = vim.api.nvim_create_augroup("ClaudeCodeProvider", { clear = true }),
		callback = cleanup_closed_tabs,
	})
end

function M.open(cmd_string, env_table, config, do_focus)
	ensure_patches()
	local should_focus = do_focus ~= false
	local tab_id = vim.api.nvim_get_current_tabpage()
	local t = State.terminals[tab_id]

	if t and term_is_valid(t) then
		if not term_is_visible(t) then
			t.instance:toggle()
		end
		if should_focus then
			term_focus(t)
		end
		return
	end

	if not State.clients[tab_id] then
		State.connecting = tab_id
	end
	create_terminal(cmd_string, env_table, config, should_focus, tab_id)
end

function M.close()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local t = State.terminals[tab_id]
	if not t then
		return
	end
	if t.instance and t.instance:buf_valid() then
		t.instance:close()
	end
	State.clients[tab_id] = nil
	State.terminals[tab_id] = nil
end

function M.simple_toggle(cmd_string, env_table, config)
	local tab_id = vim.api.nvim_get_current_tabpage()
	local t = State.terminals[tab_id]

	if t and term_is_valid(t) then
		t.instance:toggle()
	else
		M.open(cmd_string, env_table, config)
	end
end

function M.focus_toggle(cmd_string, env_table, config)
	local tab_id = vim.api.nvim_get_current_tabpage()
	local t = State.terminals[tab_id]

	if not t or not term_is_valid(t) then
		M.open(cmd_string, env_table, config)
		return
	end

	if not term_is_visible(t) then
		t.instance:toggle()
		return
	end

	-- Visible: hide if focused, focus if not
	if vim.api.nvim_get_current_win() == t.instance.win then
		t.instance:toggle()
	else
		term_focus(t)
	end
end

function M.get_active_bufnr()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local t = State.terminals[tab_id]
	if t and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then
		return t.bufnr
	end
end

function M.is_available()
	local ok, snacks = pcall(require, "snacks")
	return ok and snacks ~= nil and snacks.terminal ~= nil
end

return M
