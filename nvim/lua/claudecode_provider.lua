-- Multi-session terminal provider for claudecode.nvim
-- Each Neovim tab can hold multiple Claude Code sessions. Only the
-- active session is visible in the split; others run in the background.
-- Patches claudecode.nvim's broadcast so MCP events are routed to the
-- current tab's active session client.

local M = {}

local State = {
	tabs = {},       -- tab_id -> { sessions = [...], active = number }
	cmd_cache = nil, -- { cmd, env, config } from last open() call
	connecting = nil,-- tab_id awaiting connection
	next_count = 1,  -- unique Snacks terminal count
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
--  Tab / session helpers
----------------------------------------------------------------

local function get_tab(tab_id)
	return State.tabs[tab_id]
end

local function get_or_create_tab(tab_id)
	if not State.tabs[tab_id] then
		State.tabs[tab_id] = { sessions = {}, active = 0 }
	end
	return State.tabs[tab_id]
end

local function active_session(tab_id)
	local tab = get_tab(tab_id)
	if tab and tab.active > 0 and tab.active <= #tab.sessions then
		return tab.sessions[tab.active]
	end
end

local function session_is_valid(s)
	return s and s.instance and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr)
end

local function session_is_visible(s)
	return s and s.instance and s.instance.win and vim.api.nvim_win_is_valid(s.instance.win)
end

local function session_focus(s)
	if s.instance.win and vim.api.nvim_win_is_valid(s.instance.win) then
		vim.api.nvim_set_current_win(s.instance.win)
		vim.cmd("startinsert")
	end
end

local function remove_session_by_buf(tab_id, bufnr)
	local tab = get_tab(tab_id)
	if not tab then return end
	for i, s in ipairs(tab.sessions) do
		if s.bufnr == bufnr then
			table.remove(tab.sessions, i)
			if #tab.sessions == 0 then
				State.tabs[tab_id] = nil
			elseif tab.active > #tab.sessions then
				tab.active = #tab.sessions
			elseif tab.active > i then
				tab.active = tab.active - 1
			end
			return
		end
	end
end

----------------------------------------------------------------
--  Monkey-patches (applied once, route MCP events per-tab)
----------------------------------------------------------------

local function ensure_patches()
	-- on_connect: track which client belongs to which tab's active session
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
					if tab_id then
						local s = active_session(tab_id)
						if s and not s.client_id then
							s.client_id = client.id
							State.connecting = nil
						end
					end
				end)
			end
			State.patched.on_connect = true
		end
	end

	-- on_disconnect: find and clear the session's client mapping
	if not State.patched.on_disconnect then
		local tcp = get_tcp_server()
		if tcp then
			local orig = tcp.on_disconnect
			tcp.on_disconnect = function(client, code, reason)
				orig(client, code, reason)
				for _, tab in pairs(State.tabs) do
					for _, s in ipairs(tab.sessions) do
						if s.client_id == client.id then
							s.client_id = nil
							return
						end
					end
				end
			end
			State.patched.on_disconnect = true
		end
	end

	-- broadcast: scope events to current tab's active session client
	if not State.patched.broadcast then
		local server = get_root_server()
		if server and server.broadcast then
			server.broadcast = function(event, data)
				local tab_id = vim.api.nvim_get_current_tabpage()
				local s = active_session(tab_id)
				if not s or not s.client_id then
					return false
				end
				if server.state and server.state.clients then
					local client = server.state.clients[s.client_id]
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
--  Terminal creation
----------------------------------------------------------------

local function build_opts(config, env_table, should_focus, count)
	return {
		count = count,
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

local function create_session(tab_id, cmd_string, env_table, config, should_focus, name)
	local tab = get_or_create_tab(tab_id)
	local count = State.next_count
	State.next_count = State.next_count + 1

	State.connecting = tab_id

	local opts = build_opts(config, env_table, should_focus, count)
	local ok, term = pcall(Snacks.terminal.open, cmd_string, opts)
	if not ok or not term or not term:buf_valid() then
		return
	end

	local session = {
		instance = term,
		bufnr = term.buf,
		client_id = nil,
		name = name or ("Session " .. #tab.sessions + 1),
	}
	table.insert(tab.sessions, session)
	tab.active = #tab.sessions

	-- Disable horizontal trackpad scrolling inside the Claude terminal
	for _, mode in ipairs({ "t", "n" }) do
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<ScrollWheelLeft>", "", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<ScrollWheelRight>", "", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<S-ScrollWheelLeft>", "", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(term.buf, mode, "<S-ScrollWheelRight>", "", { noremap = true, silent = true })
	end

	if config.auto_close then
		term:on("TermClose", function()
			remove_session_by_buf(tab_id, term.buf)
			vim.schedule(function()
				term:close({ buf = true })
				vim.cmd.checktime()
			end)
		end, { buf = true })
	end

	term:on("BufWipeout", function()
		remove_session_by_buf(tab_id, term.buf)
	end, { buf = true })
end

----------------------------------------------------------------
--  Cleanup
----------------------------------------------------------------

local function cleanup_closed_tabs()
	local active = {}
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		active[tab] = true
	end
	for tab_id, tab in pairs(State.tabs) do
		if not active[tab_id] then
			for _, s in ipairs(tab.sessions) do
				if s.instance then
					pcall(function() s.instance:close({ buf = true }) end)
				end
			end
			State.tabs[tab_id] = nil
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
	State.cmd_cache = { cmd = cmd_string, env = env_table, config = config }
	local should_focus = do_focus ~= false
	local tab_id = vim.api.nvim_get_current_tabpage()
	local s = active_session(tab_id)

	if s and session_is_valid(s) then
		if not session_is_visible(s) then
			s.instance:toggle()
		end
		if should_focus then
			session_focus(s)
		end
		return
	end

	create_session(tab_id, cmd_string, env_table, config, should_focus)
end

function M.close()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local tab = get_tab(tab_id)
	if not tab then return end
	for _, s in ipairs(tab.sessions) do
		if s.instance and s.instance:buf_valid() then
			s.instance:close()
		end
	end
	State.tabs[tab_id] = nil
end

function M.simple_toggle(cmd_string, env_table, config)
	local tab_id = vim.api.nvim_get_current_tabpage()
	local s = active_session(tab_id)

	if s and session_is_valid(s) then
		s.instance:toggle()
	else
		M.open(cmd_string, env_table, config)
	end
end

function M.focus_toggle(cmd_string, env_table, config)
	local tab_id = vim.api.nvim_get_current_tabpage()
	local s = active_session(tab_id)

	if not s or not session_is_valid(s) then
		M.open(cmd_string, env_table, config)
		return
	end

	if not session_is_visible(s) then
		s.instance:toggle()
		return
	end

	-- Visible: hide if focused, focus if not
	if vim.api.nvim_get_current_win() == s.instance.win then
		s.instance:toggle()
	else
		session_focus(s)
	end
end

function M.get_active_bufnr()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local s = active_session(tab_id)
	if s and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
		return s.bufnr
	end
end

function M.is_available()
	local ok, snacks = pcall(require, "snacks")
	return ok and snacks ~= nil and snacks.terminal ~= nil
end

----------------------------------------------------------------
--  Multi-session controls
----------------------------------------------------------------

function M.new_session()
	local cache = State.cmd_cache
	if not cache then
		vim.cmd("ClaudeCode")
		return
	end

	vim.ui.input({ prompt = "Session name (empty for default): " }, function(input)
		local name = (input and input ~= "") and input or nil
		ensure_patches()
		local tab_id = vim.api.nvim_get_current_tabpage()
		local s = active_session(tab_id)

		-- Hide current session (keep it running in background)
		if s and session_is_visible(s) then
			s.instance:toggle()
		end

		create_session(tab_id, cache.cmd, cache.env, cache.config, true, name)
	end)
end

function M.cycle_session()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local tab = get_tab(tab_id)
	if not tab or #tab.sessions <= 1 then return end

	local current = tab.sessions[tab.active]
	if current and session_is_visible(current) then
		current.instance:toggle()
	end

	tab.active = (tab.active % #tab.sessions) + 1

	local next_s = tab.sessions[tab.active]
	if next_s and session_is_valid(next_s) then
		next_s.instance:toggle()
		session_focus(next_s)
	end
end

function M.goto_session(n)
	local tab_id = vim.api.nvim_get_current_tabpage()
	local tab = get_tab(tab_id)
	if not tab or not tab.sessions[n] or n == tab.active then return end

	local current = tab.sessions[tab.active]
	if current and session_is_visible(current) then
		current.instance:toggle()
	end

	tab.active = n

	local target = tab.sessions[n]
	if target and session_is_valid(target) then
		target.instance:toggle()
		session_focus(target)
	end
end

function M.list_sessions()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local tab = get_tab(tab_id)
	if not tab or #tab.sessions == 0 then
		vim.notify("No Claude sessions", vim.log.levels.INFO)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local entries = {}
	for i, s in ipairs(tab.sessions) do
		local status = session_is_valid(s) and "running" or "dead"
		local marker = i == tab.active and " (active)" or ""
		table.insert(entries, {
			display = string.format("%d: %s [%s]%s", i, s.name, status, marker),
			index = i,
			ordinal = s.name,
		})
	end

	local function make_finder(t)
		local items = {}
		for i, s in ipairs(t.sessions) do
			local status = session_is_valid(s) and "running" or "dead"
			local marker = i == t.active and " (active)" or ""
			table.insert(items, {
				display = string.format("%d: %s [%s]%s", i, s.name, status, marker),
				index = i,
				ordinal = s.name,
			})
		end
		return finders.new_table({
			results = items,
			entry_maker = function(entry)
				return { value = entry, display = entry.display, ordinal = entry.ordinal }
			end,
		})
	end

	pickers.new({}, {
		prompt_title = "Claude Sessions (CR: switch, C-r: rename, q: close)",
		finder = make_finder(tab),
		sorter = conf.generic_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				if selection then
					M.goto_session(selection.value.index)
				end
			end)

			map("n", "q", function()
				actions.close(prompt_bufnr)
			end)

			map({ "i", "n" }, "<C-r>", function()
				local selection = action_state.get_selected_entry()
				if not selection then return end
				local idx = selection.value.index
				local s = tab.sessions[idx]
				if not s then return end

				actions.close(prompt_bufnr)
				vim.ui.input({ prompt = "Rename session: ", default = s.name }, function(input)
					if input and input ~= "" then
						s.name = input
					end
					-- Reopen the picker after rename
					vim.schedule(function() M.list_sessions() end)
				end)
			end)

			return true
		end,
	}):find()
end

function M.rename_session()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local s = active_session(tab_id)
	if not s then
		vim.notify("No active Claude session", vim.log.levels.INFO)
		return
	end

	vim.ui.input({ prompt = "Rename session: ", default = s.name }, function(input)
		if input and input ~= "" then
			s.name = input
		end
	end)
end

return M
