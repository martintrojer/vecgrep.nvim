-- vecgrep picker.lua — fzf-lua backend

local runner = require("vecgrep.runner")
local log = require("vecgrep.log").log

local M = {}

--- Lazy-load fzf-lua (may be an opt plugin not yet loaded at require time).
---@return boolean, table|nil
local function get_fzf_lua()
	local ok, mod = pcall(require, "fzf-lua")
	if ok then
		return true, mod
	end
	return false, nil
end

--- Format a result for display (fallback only).
---@param r table {file, start_line, end_line, score}
---@return string
local function format_result(r)
	return string.format("[%.3f] %s:%d-%d", r.score, r.file, r.start_line, r.end_line)
end

--- Fallback picker using vim.ui.select.
---@param results table[]
---@param root string|nil project root for resolving paths
local function ui_select(results, root)
	vim.ui.select(results, {
		prompt = "Vecgrep results",
		format_item = format_result,
	}, function(choice)
		if choice then
			local path = choice.file
			if root and not vim.startswith(path, "/") then
				path = root .. "/" .. path
			end
			vim.cmd("edit +" .. choice.start_line .. " " .. vim.fn.fnameescape(path))
		end
	end)
end

--- Build a display line with ANSI color for fzf.
--- Format: "[score] file:start_line-end_line"
---@param r table result with score, file, start_line, end_line
---@return string
local function fzf_entry(r)
	local score = r.score or 0
	local color
	if score >= 0.7 then
		color = "\27[32m" -- green
	elseif score >= 0.5 then
		color = "\27[33m" -- yellow
	else
		color = "\27[31m" -- red
	end
	return string.format("%s[%.3f]\27[0m %s:%d-%d", color, score, r.file, r.start_line, r.end_line)
end

--- Parse a fzf entry back to file, start_line, and end_line.
---@param entry string
---@return string|nil file, integer|nil start_line, integer|nil end_line
local function parse_fzf_entry(entry)
	-- Strip ANSI codes first
	local clean = entry:gsub("\27%[[%d;]*m", "")
	local file, sl, el = clean:match("%[%d%.%d+%]%s+(.+):(%d+)%-(%d+)")
	return file, tonumber(sl), tonumber(el)
end

--- Open a file at a given line, resolving relative paths against cwd.
---@param selected string[] fzf selected entries
---@param cwd string working directory for resolving relative paths
local function open_result(selected, cwd)
	if not selected or #selected == 0 then
		return
	end
	local file, line = parse_fzf_entry(selected[1])
	if file and line then
		local path = file
		if not vim.startswith(file, "/") then
			path = cwd .. "/" .. file
		end
		vim.cmd("edit +" .. line .. " " .. vim.fn.fnameescape(path))
	end
end

--- Create a fzf-lua previewer that highlights the matched chunk region.
--- @param get_cwd fun(): string callback returning the current project root for path resolution
---@return table previewer_class
local function make_previewer(get_cwd)
	local builtin = require("fzf-lua.previewer.builtin")
	local ChunkPreviewer = builtin.buffer_or_file:extend()

	function ChunkPreviewer:new(o, fzf_opts, fzf_win)
		ChunkPreviewer.super.new(self, o, fzf_opts, fzf_win)
		setmetatable(self, ChunkPreviewer)
		return self
	end

	--- Override parse_entry to handle our "[score] file:start-end" format.
	--- fzf-lua calls this with the raw entry string from fzf.
	---@param entry_str string
	---@return table entry with path, line, col, _start_line, _end_line
	function ChunkPreviewer:parse_entry(entry_str)
		local file, sl, el = parse_fzf_entry(entry_str)
		if not file then
			return {}
		end
		local path = file
		if not vim.startswith(file, "/") then
			local cwd = get_cwd()
			path = cwd .. "/" .. file
		end
		return {
			path = path,
			line = sl,
			col = 1,
			_start_line = sl,
			_end_line = el,
		}
	end

	--- Override preview_buf_post to add Search highlights on the chunk region.
	--- Called after the file is loaded into the preview buffer.
	---@param entry table parsed entry from parse_entry
	---@param min_winopts boolean|nil
	function ChunkPreviewer:preview_buf_post(entry, min_winopts)
		ChunkPreviewer.super.preview_buf_post(self, entry, min_winopts)
		local buf = self.preview_bufnr
		if not buf or not vim.api.nvim_buf_is_valid(buf) or not entry._start_line then
			return
		end
		local ns = vim.api.nvim_create_namespace("vecgrep_chunk")
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		local line_count = vim.api.nvim_buf_line_count(buf)
		local sl = math.max(0, entry._start_line - 1)
		local el = math.min(line_count, entry._end_line)
		for i = sl, el - 1 do
			vim.api.nvim_buf_add_highlight(buf, ns, "Search", i, 0, -1)
		end
	end

	return ChunkPreviewer
end

--- Static search: run query once, show results in fzf-lua (or vim.ui.select).
---@param query string
---@param opts? table
function M.search(query, opts)
	opts = opts or {}
	local fallback_cwd = runner.buf_dir()

	runner.search(query, opts, function(results, root)
		if #results == 0 then
			vim.notify("vecgrep: no results", vim.log.levels.INFO)
			return
		end

		local has_fzf, fzf = get_fzf_lua()
		if not has_fzf then
			ui_select(results, root)
			return
		end

		local cwd = root or fallback_cwd

		local entries = {}
		for _, r in ipairs(results) do
			table.insert(entries, fzf_entry(r))
		end

		fzf.fzf_exec(entries, {
			prompt = "Vecgrep> ",
			fzf_opts = {
				["--ansi"] = "",
				["--no-sort"] = "",
			},
			previewer = make_previewer(function()
				return cwd
			end),
			cwd = cwd,
			actions = {
				["default"] = function(selected)
					open_result(selected, cwd)
				end,
			},
		})
	end)
end

--- Live interactive search: queries a warm vecgrep server on each keystroke.
--- Requires fzf-lua.
---@param opts? table
function M.live(opts)
	opts = opts or {}

	local has_fzf, fzf = get_fzf_lua()
	if not has_fzf then
		vim.notify("vecgrep: live mode requires fzf-lua", vim.log.levels.ERROR)
		return
	end

	local cwd = runner.buf_dir()
	log("live: buf_dir =", cwd)

	runner.ensure_server(opts, function(port)
		log("live: server ready on port", port)

		-- Track server root once known from first query response
		local server_root = cwd

		-- Poll status and show notifications for indexing progress
		runner.poll_status(port, function(status)
			if status.status == "indexing" then
				local total = status.total and tostring(status.total) or "??"
				vim.notify(string.format("vecgrep: indexing %d/%s", status.indexed, total), vim.log.levels.INFO)
			end
		end, function(status)
			if status.root then
				server_root = status.root
			end
			if status.files and status.chunks then
				vim.notify(
					string.format("vecgrep: ready (%d files, %d chunks)", status.files, status.chunks),
					vim.log.levels.INFO
				)
			end
		end)

		fzf.fzf_live(function(query)
			-- fzf-lua passes query as a table (selection array) via RPC
			if type(query) == "table" then
				query = query[1]
			end
			if type(query) ~= "string" or query == "" then
				return {}
			end
			log("live query:", query)
			local curl_args = runner.build_curl_args(query, opts)
			local result = vim.system({ "curl", unpack(curl_args) }, { text = true }):wait()
			if result.code ~= 0 or not result.stdout or result.stdout == "" then
				log("live query: curl failed, code =", result.code)
				return {}
			end
			local entries = {}
			for line in result.stdout:gmatch("[^\r\n]+") do
				local ok, decoded = pcall(vim.json.decode, line)
				if ok and decoded then
					if decoded.root then
						server_root = decoded.root
					end
					table.insert(entries, fzf_entry(decoded))
				end
			end
			log("live query: results =", #entries, "root =", server_root)
			return entries
		end, {
			prompt = "Vecgrep Live> ",
			exec_empty_query = false,
			fzf_opts = {
				["--ansi"] = "",
				["--no-sort"] = "",
			},
			previewer = make_previewer(function()
				return server_root
			end),
			cwd = server_root,
			actions = {
				["default"] = function(selected)
					open_result(selected, server_root)
				end,
			},
		})
	end)
end

return M
