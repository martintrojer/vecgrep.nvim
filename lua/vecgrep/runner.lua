local config = require("vecgrep.config")

local M = {}

-- Server state
M._server_proc = nil
M._server_port = nil
M._server_path = nil

--- URL-encode a string for use in query parameters.
---@param str string
---@return string
local function url_encode(str)
	return str:gsub("([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

--- Get the directory of the current buffer (falls back to cwd).
---@return string
local function buf_dir()
	local bufname = vim.api.nvim_buf_get_name(0)
	if bufname ~= "" then
		return vim.fn.fnamemodify(bufname, ":p:h")
	end
	return vim.fn.getcwd()
end

--- Parse JSONL output into a list of result tables.
---@param stdout string raw stdout from vecgrep --json
---@return table[] results each with {file, start_line, end_line, score, text}
local function parse_jsonl(stdout)
	local results = {}
	for line in stdout:gmatch("[^\r\n]+") do
		local ok, decoded = pcall(vim.json.decode, line)
		if ok and decoded then
			table.insert(results, decoded)
		end
	end
	return results
end

--- Build the vecgrep command arguments for a search query.
---@param query string
---@param opts? table overrides for top_k, threshold, context, args
---@return string[] cmd full command with arguments
local function build_search_cmd(query, opts)
	opts = opts or {}
	local cfg = config.options
	local cmd = { cfg.cmd }

	-- extra default args
	for _, a in ipairs(cfg.args) do
		table.insert(cmd, a)
	end
	-- extra per-call args
	for _, a in ipairs(opts.args or {}) do
		table.insert(cmd, a)
	end

	table.insert(cmd, "--json")
	table.insert(cmd, "-k")
	table.insert(cmd, tostring(opts.top_k or cfg.top_k))
	table.insert(cmd, "--threshold")
	table.insert(cmd, tostring(opts.threshold or cfg.threshold))
	table.insert(cmd, "-C")
	table.insert(cmd, tostring(opts.context or cfg.context))
	table.insert(cmd, query)
	table.insert(cmd, buf_dir())

	return cmd
end

--- Run a semantic search asynchronously.
---@param query string the search query
---@param opts? table overrides (top_k, threshold, context, args)
---@param callback fun(results: table[]) called with parsed results
---@return vim.SystemObj|nil handle the system process handle (for cancellation)
function M.search(query, opts, callback)
	if not query or query == "" then
		callback({})
		return nil
	end

	local cmd = build_search_cmd(query, opts)

	return vim.system(cmd, { text = true }, function(result)
		local results = {}
		if result.code == 0 and result.stdout and result.stdout ~= "" then
			results = parse_jsonl(result.stdout)
		end
		vim.schedule(function()
			callback(results)
		end)
	end)
end

--- Start the vecgrep HTTP server (loads model + index once).
---@param path string directory to serve
---@param opts? table overrides (args)
---@param callback fun(port: integer) called when the server is ready
function M.start_server(path, opts, callback)
	opts = opts or {}
	local cfg = config.options
	local cmd = { cfg.cmd, "--serve" }

	for _, a in ipairs(cfg.args) do
		table.insert(cmd, a)
	end
	for _, a in ipairs(opts.args or {}) do
		table.insert(cmd, a)
	end

	local port = opts.port or cfg.server_port
	if port then
		table.insert(cmd, "--port")
		table.insert(cmd, tostring(port))
	end

	table.insert(cmd, path)

	local stderr_buf = ""
	local port_found = false

	M._server_path = path
	M._server_proc = vim.system(cmd, {
		text = true,
		stderr = function(_, data)
			if data then
				stderr_buf = stderr_buf .. data
			end
			if not port_found then
				local found_port = stderr_buf:match(":(%d+)")
				if found_port then
					port_found = true
					M._server_port = tonumber(found_port)
					vim.schedule(function()
						callback(M._server_port)
					end)
				end
			end
		end,
	}, function(result)
		-- Server process exited
		M._server_proc = nil
		M._server_port = nil
		M._server_path = nil
		if result.code ~= 0 then
			vim.schedule(function()
				vim.notify("vecgrep: server exited (code " .. result.code .. ")", vim.log.levels.WARN)
			end)
		end
	end)
end

--- Stop the vecgrep server if running.
function M.stop_server()
	if M._server_proc then
		M._server_proc:kill()
		M._server_proc = nil
		M._server_port = nil
		M._server_path = nil
	end
end

--- Ensure the server is running for the current buffer's directory.
--- Restarts if the buffer dir has changed.
---@param opts? table overrides (args)
---@param callback fun(port: integer) called when the server is ready
function M.ensure_server(opts, callback)
	local path = buf_dir()
	if M._server_port and M._server_proc and M._server_path == path then
		callback(M._server_port)
		return
	end
	if M._server_proc then
		M.stop_server()
	end
	M.start_server(path, opts, callback)
end

--- Build curl args table for querying the running server.
---@param query string the search query
---@param opts? table overrides (top_k, threshold, context)
---@return string[] args curl arguments (without the "curl" command itself)
function M.build_curl_args(query, opts)
	opts = opts or {}
	local cfg = config.options
	local k = opts.top_k or cfg.top_k
	local threshold = opts.threshold or cfg.threshold
	local context = opts.context or cfg.context
	local url = string.format(
		"http://127.0.0.1:%d/search?q=%s&k=%d&threshold=%s&context=%d",
		M._server_port,
		url_encode(query),
		k,
		tostring(threshold),
		context
	)
	return { "-s", url }
end

--- Run an arbitrary vecgrep command asynchronously.
---@param args string[] arguments to pass to vecgrep
---@param callback fun(stdout: string, stderr: string, code: integer)
function M.run_command(args, callback)
	local cfg = config.options
	local cmd = { cfg.cmd }
	for _, a in ipairs(args) do
		table.insert(cmd, a)
	end

	vim.system(cmd, { text = true }, function(result)
		vim.schedule(function()
			callback(result.stdout or "", result.stderr or "", result.code)
		end)
	end)
end

return M
