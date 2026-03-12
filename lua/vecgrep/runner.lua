local config = require("vecgrep.config")

local M = {}

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
---@param opts? table overrides for top_k, threshold, context, paths, args
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

	local paths = opts.paths or cfg.paths
	for _, p in ipairs(paths) do
		table.insert(cmd, p)
	end

	return cmd
end

--- Run a semantic search asynchronously.
---@param query string the search query
---@param opts? table overrides (top_k, threshold, context, paths, args)
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
