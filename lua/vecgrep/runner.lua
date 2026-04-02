local config = require("vecgrep.config")
local log = require("vecgrep.log").log

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
--- Validates that the resolved path is a real directory (handles special
--- buffers like ministarter, oil://, fugitive://, etc.).
---@return string
function M.buf_dir()
	local bufname = vim.api.nvim_buf_get_name(0)
	if bufname ~= "" then
		local dir = vim.fn.fnamemodify(bufname, ":p:h")
		if vim.fn.isdirectory(dir) == 1 then
			return dir
		end
	end
	return vim.fn.getcwd()
end

--- Check whether --no-scope should be used.
---@param from_root? boolean per-call override
---@return boolean
function M.use_no_scope(from_root)
	if from_root ~= nil then
		return from_root
	end
	return config.options.search_from_root
end

--- Parse JSONL output into a list of result tables.
--- Extracts the root field from the first result if present.
---@param stdout string raw stdout from vecgrep --json
---@return table[] results each with {file, start_line, end_line, score, text}
---@return string|nil root vecgrep's project root
local function parse_jsonl(stdout)
	local results = {}
	local root = nil
	for line in stdout:gmatch("[^\r\n]+") do
		local ok, decoded = pcall(vim.json.decode, line)
		if ok and decoded then
			if not root and decoded.root then
				root = decoded.root
			end
			table.insert(results, decoded)
		end
	end
	return results, root
end

--- Build the vecgrep command arguments for a search query.
---@param query string
---@param opts? table overrides for top_k, threshold, args
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
	if M.use_no_scope(opts.from_root) then
		table.insert(cmd, "--no-scope")
	end
	local k = opts.top_k or cfg.top_k
	if k then
		table.insert(cmd, "-k")
		table.insert(cmd, tostring(k))
	end
	local threshold = opts.threshold or cfg.threshold
	if threshold then
		table.insert(cmd, "--threshold")
		table.insert(cmd, tostring(threshold))
	end
	table.insert(cmd, query)

	return cmd
end

--- Run a semantic search asynchronously.
---@param query string the search query
---@param opts? table overrides (top_k, threshold, args)
---@param callback fun(results: table[], root: string|nil) called with parsed results and project root
---@return vim.SystemObj|nil handle the system process handle (for cancellation)
function M.search(query, opts, callback)
	if not query or query == "" then
		callback({}, nil)
		return nil
	end

	local cmd = build_search_cmd(query, opts)
	local cwd = M.buf_dir()
	log("search: cmd =", table.concat(cmd, " "))
	log("search: cwd =", cwd)

	return vim.system(cmd, { text = true, cwd = cwd }, function(result)
		local results = {}
		local root = nil
		if result.code == 0 and result.stdout and result.stdout ~= "" then
			results, root = parse_jsonl(result.stdout)
		end
		log("search: code =", result.code, "results =", #results, "root =", tostring(root))
		vim.schedule(function()
			callback(results, root)
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

	if M.use_no_scope(opts.from_root) then
		table.insert(cmd, "--no-scope")
	end
	local port = opts.port or cfg.server_port
	if port then
		table.insert(cmd, "--port")
		table.insert(cmd, tostring(port))
	end

	table.insert(cmd, path)

	local stderr_buf = ""
	local port_found = false

	log("start_server: cmd =", table.concat(cmd, " "))
	log("start_server: path =", path)
	M._server_path = path
	M._server_proc = vim.system(cmd, {
		text = true,
		cwd = path,
		stderr = function(_, data)
			if data then
				stderr_buf = stderr_buf .. data
			end
			if not port_found then
				local found_port = stderr_buf:match("Listening on http[s]?://[^:]+:(%d+)")
				if found_port then
					port_found = true
					M._server_port = tonumber(found_port)
					log("start_server: port =", M._server_port)
					vim.schedule(function()
						callback(M._server_port)
					end)
				end
			end
		end,
	}, function(result)
		-- Only clear state if this process is still the current server
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
		log("stop_server: killing server for path =", tostring(M._server_path))
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
	opts = opts or {}
	local path = M.buf_dir()
	log("ensure_server: buf_dir =", path, "server_path =", tostring(M._server_path), "port =", tostring(M._server_port))
	if M._server_port and M._server_proc and M._server_path == path then
		log("ensure_server: reusing existing server")
		callback(M._server_port)
		return
	end
	if M._server_proc then
		log("ensure_server: stopping old server (path mismatch)")
		M.stop_server()
	end
	M.start_server(path, opts, callback)
end

--- Build curl args table for querying the running server.
---@param query string the search query
---@param opts? table overrides (top_k, threshold)
---@return string[] args curl arguments (without the "curl" command itself)
function M.build_curl_args(query, opts)
	opts = opts or {}
	local cfg = config.options
	local k = opts.top_k or cfg.top_k
	local threshold = opts.threshold or cfg.threshold
	local url = string.format("http://127.0.0.1:%d/search?q=%s", M._server_port, url_encode(query))
	if k then
		url = url .. string.format("&k=%d", k)
	end
	if threshold then
		url = url .. string.format("&threshold=%s", tostring(threshold))
	end
	log("build_curl_args: url =", url)
	return { "-s", url }
end

--- Poll the /status endpoint until the server is ready (or timeout).
--- Calls progress_cb on each poll, then done_cb when ready.
---@param port integer
---@param progress_cb? fun(status: table) called with each status response
---@param done_cb fun(status: table) called when status is "ready"
function M.poll_status(port, progress_cb, done_cb)
	local url = string.format("http://127.0.0.1:%d/status", port)
	log("poll_status: url =", url)
	local timer = vim.uv.new_timer()
	timer:start(
		500,
		1000,
		vim.schedule_wrap(function()
			vim.system({ "curl", "-s", url }, { text = true }, function(result)
				vim.schedule(function()
					if result.code ~= 0 or not result.stdout or result.stdout == "" then
						log("poll_status: curl failed, code =", result.code)
						return
					end
					log("poll_status: response =", result.stdout)
					local ok, status = pcall(vim.json.decode, result.stdout)
					if not ok then
						log("poll_status: json decode failed")
						return
					end
					log("poll_status: status =", status.status)
					if progress_cb then
						progress_cb(status)
					end
					if status.status == "ready" then
						timer:stop()
						timer:close()
						done_cb(status)
					end
				end)
			end)
		end)
	)
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

	vim.system(cmd, { text = true, cwd = M.buf_dir() }, function(result)
		vim.schedule(function()
			callback(result.stdout or "", result.stderr or "", result.code)
		end)
	end)
end

return M
