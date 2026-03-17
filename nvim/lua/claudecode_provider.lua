-- Multi-session terminal provider for claudecode.nvim
-- Each Neovim tab can hold multiple Claude Code sessions. Only the
-- active session is visible in the split; others run in the background.
-- Sessions persist across Neovim restarts by discovering conversations
-- from Claude Code's filesystem and resuming via --resume.

local M = {}

local uv = vim.uv or vim.loop
local PERSISTENCE_FILE = vim.fn.stdpath("data") .. "/claude_sessions.json"

local State = {
	tabs = {},       -- tab_id -> { sessions = [...], active = number }
	cmd_cache = nil, -- { cmd, env, config } from last open() call
	connecting = nil,-- tab_id awaiting connection
	next_count = 1,  -- unique Snacks terminal count
	patched = { on_connect = false, on_disconnect = false, broadcast = false },
}

----------------------------------------------------------------
--  Project directory helpers
----------------------------------------------------------------

local function get_project_dir()
	local cwd = vim.fn.getcwd()
	local encoded = cwd:gsub("[/.]", "-")
	return vim.fn.expand("~/.claude/projects/" .. encoded)
end

----------------------------------------------------------------
--  Persistence (name overrides for conversation IDs)
----------------------------------------------------------------

local function load_all_persisted()
	local f = io.open(PERSISTENCE_FILE, "r")
	if not f then return {} end
	local content = f:read("*a")
	f:close()
	if not content or content == "" then return {} end
	local ok, data = pcall(vim.json.decode, content)
	return ok and type(data) == "table" and data or {}
end

local function save_all_persisted(data)
	local f = io.open(PERSISTENCE_FILE, "w")
	if not f then return end
	f:write(vim.json.encode(data))
	f:close()
end

--- Returns { [conversation_id] = name } for current cwd
local function load_name_map()
	local all = load_all_persisted()
	return all[vim.fn.getcwd()] or {}
end

local function save_name_map(name_map)
	local all = load_all_persisted()
	all[vim.fn.getcwd()] = name_map
	save_all_persisted(all)
end

--- Load global defaults (model, effort)
local function load_defaults()
	local all = load_all_persisted()
	return all._defaults or {}
end

local function save_defaults(defaults)
	local all = load_all_persisted()
	all._defaults = defaults
	save_all_persisted(all)
end

--- Persist running sessions' names into the name map
local function persist_names()
	local name_map = load_name_map()
	for _, tab in pairs(State.tabs) do
		for _, s in ipairs(tab.sessions) do
			if s.session_id and s.name then
				name_map[s.session_id] = s.name
			end
		end
	end
	save_name_map(name_map)
end

----------------------------------------------------------------
--  Filesystem discovery
----------------------------------------------------------------

local function get_first_user_message(jsonl_path)
	local f = io.open(jsonl_path, "r")
	if not f then return nil end
	for line in f:lines() do
		local ok, data = pcall(vim.json.decode, line)
		if ok and data.type == "user" and data.message then
			f:close()
			local content = data.message.content
			if type(content) == "string" then
				local first_line = content:match("^[^\n]*")
				if first_line then
					first_line = vim.trim(first_line)
					if #first_line > 60 then
						return first_line:sub(1, 60) .. "..."
					end
					return first_line
				end
			end
			return nil
		end
	end
	f:close()
	return nil
end

--- Scan Claude's project dir for .jsonl conversation files.
--- Returns [{ session_id, name, mtime }] sorted newest-first.
local function discover_conversations()
	local project_dir = get_project_dir()
	local files = vim.fn.glob(project_dir .. "/*.jsonl", false, true)
	if #files == 0 then return {} end

	local name_map = load_name_map()
	local conversations = {}

	for _, filepath in ipairs(files) do
		local uuid = vim.fn.fnamemodify(filepath, ":t:r")
		local mtime = vim.fn.getftime(filepath)
		local name = name_map[uuid]
		if not name then
			name = get_first_user_message(filepath) or ("Session " .. uuid:sub(1, 8))
		end
		table.insert(conversations, {
			session_id = uuid,
			name = name,
			mtime = mtime,
		})
	end

	table.sort(conversations, function(a, b) return a.mtime > b.mtime end)
	return conversations
end

----------------------------------------------------------------
--  Session ID capture (for new sessions — polls for new .jsonl)
----------------------------------------------------------------

local function start_session_id_capture(session, existing_files)
	local project_dir = get_project_dir()
	local timer = uv.new_timer()
	local attempts = 0
	timer:start(2000, 2000, vim.schedule_wrap(function()
		attempts = attempts + 1
		if attempts > 30 or not session.bufnr or not vim.api.nvim_buf_is_valid(session.bufnr) then
			timer:stop()
			timer:close()
			return
		end
		for _, f in ipairs(vim.fn.glob(project_dir .. "/*.jsonl", false, true)) do
			if not existing_files[f] then
				session.session_id = vim.fn.fnamemodify(f, ":t:r")
				persist_names()
				timer:stop()
				timer:close()
				return
			end
		end
	end))
end

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

local function running_session_ids()
	local ids = {}
	for _, tab in pairs(State.tabs) do
		for _, s in ipairs(tab.sessions) do
			if s.session_id then ids[s.session_id] = true end
		end
	end
	return ids
end

----------------------------------------------------------------
--  Monkey-patches (applied once, route MCP events per-tab)
----------------------------------------------------------------

local function ensure_patches()
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
					end
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

local function create_session(tab_id, cmd_string, env_table, config, should_focus, name, resume_id)
	local tab = get_or_create_tab(tab_id)
	local count = State.next_count
	State.next_count = State.next_count + 1

	State.connecting = tab_id

	-- Snapshot existing .jsonl files BEFORE opening terminal (for new sessions)
	local existing_files = nil
	local session_id = nil

	-- Append model/effort defaults
	local defaults = load_defaults()
	if defaults.model then
		cmd_string = cmd_string .. " --model " .. defaults.model
	end
	if defaults.effort then
		cmd_string = cmd_string .. " --effort " .. defaults.effort
	end

	if resume_id then
		session_id = resume_id
		cmd_string = cmd_string .. " --resume " .. session_id
	else
		-- New session: snapshot files so we can detect the new .jsonl later
		existing_files = {}
		for _, f in ipairs(vim.fn.glob(get_project_dir() .. "/*.jsonl", false, true)) do
			existing_files[f] = true
		end
	end

	local session_name = name or ("Session " .. (#tab.sessions + 1))

	vim.notify(string.format("[claude] create_session: cmd=%s", cmd_string), vim.log.levels.DEBUG)

	local opts = build_opts(config, env_table, should_focus, count)
	local ok, term = pcall(Snacks.terminal.open, cmd_string, opts)
	if not ok or not term then
		vim.notify(string.format("[claude] create_session: Snacks.terminal.open failed (ok=%s)", tostring(ok)), vim.log.levels.ERROR)
		return
	end
	if not term:buf_valid() then
		vim.notify("[claude] create_session: terminal buffer not valid after open", vim.log.levels.ERROR)
		return
	end
	vim.notify(string.format("[claude] create_session: terminal opened, bufnr=%d", term.buf), vim.log.levels.DEBUG)

	local session = {
		instance = term,
		bufnr = term.buf,
		client_id = nil,
		name = session_name,
		session_id = session_id, -- nil for new sessions until captured
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

	-- For new sessions, poll to discover the conversation ID
	if existing_files then
		start_session_id_capture(session, existing_files)
	else
		persist_names()
	end
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
	local group = vim.api.nvim_create_augroup("ClaudeCodeProvider", { clear = true })

	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = cleanup_closed_tabs,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = persist_names,
	})
end

function M.open(cmd_string, env_table, config, do_focus)
	ensure_patches()
	State.cmd_cache = { cmd = cmd_string, env = env_table, config = config }
	local should_focus = do_focus ~= false
	local tab_id = vim.api.nvim_get_current_tabpage()

	-- If a resume was requested before cmd_cache was ready, handle it now
	local pending = State.pending_resume
	if pending then
		State.pending_resume = nil
		vim.notify(string.format("[claude] open: fulfilling pending resume id=%s", pending.id), vim.log.levels.DEBUG)
		create_session(tab_id, cmd_string, env_table, config, should_focus, pending.name, pending.id)
		return
	end

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

		if s and session_is_visible(s) then
			s.instance:toggle()
		end

		create_session(tab_id, cache.cmd, cache.env, cache.config, true, name)
	end)
end

function M.resume_session(session_id, name)
	vim.notify(string.format("[claude] resume_session: id=%s name=%s", session_id or "nil", name or "nil"), vim.log.levels.DEBUG)
	local cache = State.cmd_cache
	if not cache then
		-- cmd_cache not populated yet — stash the resume request and
		-- trigger ClaudeCode, which calls provider.open() and gives us
		-- the cmd/env/config we need. open() will pick up pending_resume.
		vim.notify("[claude] resume_session: bootstrapping via ClaudeCode", vim.log.levels.DEBUG)
		State.pending_resume = { id = session_id, name = name }
		vim.cmd("ClaudeCode")
		return
	end

	vim.notify(string.format("[claude] resume_session: cmd_cache.cmd=%s", cache.cmd or "nil"), vim.log.levels.DEBUG)
	ensure_patches()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local s = active_session(tab_id)

	if s and session_is_visible(s) then
		s.instance:toggle()
	end

	create_session(tab_id, cache.cmd, cache.env, cache.config, true, name, session_id)
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
	local running = tab and tab.sessions or {}
	local conversations = discover_conversations()
	local running_ids = running_session_ids()

	-- Build unified entry list
	local entries = {}

	-- Running sessions first
	for i, s in ipairs(running) do
		local marker = (tab and i == tab.active) and " (active)" or ""
		table.insert(entries, {
			display = string.format("%s [running]%s", s.name, marker),
			type = "running",
			index = i,
			ordinal = s.name .. " running",
			session_id = s.session_id,
			name = s.name,
		})
	end

	-- Discovered conversations (skip any already running)
	for _, c in ipairs(conversations) do
		if not running_ids[c.session_id] then
			local age = os.difftime(os.time(), c.mtime)
			local age_str
			if age < 3600 then
				age_str = string.format("%dm ago", math.floor(age / 60))
			elseif age < 86400 then
				age_str = string.format("%dh ago", math.floor(age / 3600))
			else
				age_str = string.format("%dd ago", math.floor(age / 86400))
			end
			table.insert(entries, {
				display = string.format("%s [saved · %s]", c.name, age_str),
				type = "saved",
				ordinal = c.name .. " saved",
				session_id = c.session_id,
				name = c.name,
			})
		end
	end

	if #entries == 0 then
		vim.notify("No Claude sessions", vim.log.levels.INFO)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	--- Extract display text from a message's content (string or content blocks).
	--- Skips tool_use and tool_result blocks (they are not chat content).
	local function extract_content_lines(content)
		local result = {}
		if type(content) == "string" then
			if vim.trim(content) ~= "" then
				for _, sub_line in ipairs(vim.split(content, "\n", { plain = true })) do
					table.insert(result, (sub_line:gsub("\r", "")))
				end
			end
		elseif type(content) == "table" then
			for _, block in ipairs(content) do
				if block.type == "text" and block.text then
					for _, sub_line in ipairs(vim.split(block.text, "\n", { plain = true })) do
						table.insert(result, (sub_line:gsub("\r", "")))
					end
				end
			end
		end
		return result
	end

	local session_previewer = previewers.new_buffer_previewer({
		title = "Chat Preview",
		define_preview = function(self, entry, _status)
			local sid = entry.value.session_id
			if not sid then
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No preview available" })
				return
			end

			local filepath = get_project_dir() .. "/" .. sid .. ".jsonl"
			local f = io.open(filepath, "r")
			if not f then
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Conversation file not found" })
				return
			end

			local lines = {}
			local highlights = {} -- { line_idx, hl_group }
			local last_role = nil
			for raw_line in f:lines() do
				local ok, data = pcall(vim.json.decode, raw_line)
				if ok and data.message and data.message.content then
					local role = data.type
					-- Only show user and assistant; skip user messages that
					-- are purely tool_result blocks (no text content).
					if role == "user" or role == "assistant" then
						local content_lines = extract_content_lines(data.message.content)
						if #content_lines > 0 then
							-- Collapse consecutive messages from the same role
							if role ~= last_role then
								if #lines > 0 then
									table.insert(lines, "")
								end
								local header = string.format("── %s ──", role:upper())
								table.insert(highlights, {
									line = #lines,
									hl = role == "user" and "Function" or "Keyword",
								})
								table.insert(lines, header)
							end
							vim.list_extend(lines, content_lines)
							last_role = role
						end
					end
				end
			end
			f:close()

			if #lines == 0 then
				lines = { "No messages found" }
			end

			-- Sanitize: nvim_buf_set_lines rejects any string containing \n
			local clean = {}
			for _, l in ipairs(lines) do
				for _, part in ipairs(vim.split(l, "\n", { plain = true })) do
					table.insert(clean, (part:gsub("\r", "")))
				end
			end

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, clean)
			vim.bo[self.state.bufnr].filetype = "markdown"
			vim.wo[self.state.winid].wrap = true
			vim.wo[self.state.winid].linebreak = true
			vim.wo[self.state.winid].sidescrolloff = 0
			vim.wo[self.state.winid].scrolloff = 0

			for _, hl in ipairs(highlights) do
				vim.api.nvim_buf_add_highlight(self.state.bufnr, -1, hl.hl, hl.line, 0, -1)
			end

			-- Auto-scroll to the bottom (deferred so Telescope's window is ready)
			local winid = self.state.winid
			local bufnr = self.state.bufnr
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_buf_is_valid(bufnr) then
					local line_count = vim.api.nvim_buf_line_count(bufnr)
					if line_count > 0 then
						vim.api.nvim_win_set_cursor(winid, { line_count, 0 })
					end
				end
			end)
		end,
	})

	local function make_finder()
		return finders.new_table({
			results = entries,
			entry_maker = function(entry)
				return { value = entry, display = entry.display, ordinal = entry.ordinal }
			end,
		})
	end

	pickers.new({}, {
		prompt_title = "Claude Sessions (CR: switch/resume, C-r: rename, q: close)",
		finder = make_finder(),
		previewer = session_previewer,
		sorter = conf.generic_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				if not selection then return end

				local entry = selection.value
				if entry.type == "running" then
					M.goto_session(entry.index)
				elseif entry.type == "saved" then
					M.resume_session(entry.session_id, entry.name)
				end
			end)

			map("n", "q", function()
				actions.close(prompt_bufnr)
			end)

			map({ "i", "n" }, "<C-r>", function()
				local selection = action_state.get_selected_entry()
				if not selection then return end
				local entry = selection.value

				actions.close(prompt_bufnr)
				vim.ui.input({ prompt = "Rename session: ", default = entry.name }, function(input)
					if input and input ~= "" then
						if entry.type == "running" then
							local s = tab and tab.sessions[entry.index]
							if s then s.name = input end
						end
						-- Persist the name for this conversation ID
						local name_map = load_name_map()
						if entry.session_id then
							name_map[entry.session_id] = input
						end
						save_name_map(name_map)
						persist_names()
					end
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
			persist_names()
		end
	end)
end

function M.set_defaults()
	local models = { "opus", "sonnet", "haiku" }
	local efforts = { "max", "high", "medium", "low" }
	local defaults = load_defaults()

	vim.ui.select(models, {
		prompt = "Model (current: " .. (defaults.model or "default") .. ")",
	}, function(model)
		if not model then return end
		vim.ui.select(efforts, {
			prompt = "Effort (current: " .. (defaults.effort or "default") .. ")",
		}, function(effort)
			if not effort then return end
			save_defaults({ model = model, effort = effort })
			vim.notify(string.format("Claude defaults: model=%s, effort=%s", model, effort))
		end)
	end)
end

return M
