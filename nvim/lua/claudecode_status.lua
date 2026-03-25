-- Reads Claude Code statusline cache files from /tmp and exposes
-- formatted strings for lualine components.

local M = {}

local uv = vim.uv or vim.loop
local cache = {} -- session_id -> parsed data

local function read_cache(session_id)
	local path = "/tmp/claude_status_" .. session_id .. ".json"
	local f = io.open(path, "r")
	if not f then return nil end
	local content = f:read("*a")
	f:close()
	local ok, data = pcall(vim.json.decode, content)
	if ok and type(data) == "table" then
		cache[session_id] = data
		return data
	end
	return cache[session_id]
end

local function get_active_data()
	local ok, provider = pcall(require, "claudecode_provider")
	if not ok then return nil end
	local tab_id = vim.api.nvim_get_current_tabpage()
	local info = provider.active_session_info and provider.active_session_info(tab_id)
	if not info or not info.session_id then return nil end
	return read_cache(info.session_id)
end

local function format_tokens(n)
	if n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%.1fk", n / 1000)
	end
	return tostring(n)
end

-- Escape bare % for vim statusline format (% must be %%)
local function stl_escape(s)
	return s:gsub("%%", "%%%%")
end

function M.context_usage()
	local data = get_active_data()
	if not data then return "" end
	local pct = data.context_pct or 0
	local tokens = data.total_tokens or 0
	if pct == 0 and tokens == 0 then return "" end
	return stl_escape(string.format("%.0f%% · %s", pct, format_tokens(tokens)))
end

function M.rate_usage()
	local data = get_active_data()
	if not data then return "" end
	local pct = data.rate_pct or 0
	local resets = data.resets_at or 0
	if pct == 0 and resets == 0 then return "" end
	local reset_str = ""
	if resets > 0 then
		reset_str = " · " .. os.date("%-m-%d", resets)
	end
	return stl_escape(string.format("%.0f%%%s", pct, reset_str))
end

function M.start_polling()
	local timer = uv.new_timer()
	timer:start(0, 3000, vim.schedule_wrap(function()
		local ok, provider = pcall(require, "claudecode_provider")
		if not ok then return end
		for _, tab_id in ipairs(vim.api.nvim_list_tabpages()) do
			local info = provider.active_session_info and provider.active_session_info(tab_id)
			if info and info.session_id then
				read_cache(info.session_id)
			end
		end
	end))
end

return M
