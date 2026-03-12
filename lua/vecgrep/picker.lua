local runner = require("vecgrep.runner")

local M = {}

local has_fzf_lua, _ = pcall(require, "fzf-lua")

local delimiter = "\x01"

--- Open a file at a specific line.
---@param file string
---@param line integer
---@param cmd? string edit command ("edit", "vsplit", "split", "tabedit")
local function open_file(file, line, cmd)
	vim.cmd((cmd or "edit") .. " +" .. line .. " " .. vim.fn.fnameescape(file))
end

--- Format a result for display (used by vim.ui.select fallback).
---@param r table {file, start_line, end_line, score}
---@return string
local function format_result(r)
	return string.format("[%.3f] %s:%d-%d", r.score, r.file, r.start_line, r.end_line)
end

--- Color a score string based on its value (matching vecgrep TUI).
---@param score number
---@param text string
---@return string
local function color_score(score, text)
	local ansi_codes = require("fzf-lua").utils.ansi_codes
	if score >= 0.7 then
		return ansi_codes.green(text)
	elseif score >= 0.5 then
		return ansi_codes.yellow(text)
	else
		return ansi_codes.red(text)
	end
end

--- Build a fzf entry string with embedded structured data.
---@param file string
---@param start_line integer
---@param end_line integer
---@param score number
---@return string
local function make_entry(file, start_line, end_line, score)
	local display = color_score(score, string.format("[%.3f]", score))
		.. " "
		.. string.format("%s:%d-%d", file, start_line, end_line)
	return table.concat({
		file,
		tostring(start_line),
		tostring(end_line),
		tostring(score),
		display,
	}, delimiter)
end

--- Parse structured fields from a delimiter-separated entry string.
---@param entry string
---@return string file
---@return integer start_line
---@return integer end_line
local function parse_entry_fields(entry)
	local parts = {}
	for part in entry:gmatch("([^" .. delimiter .. "]+)") do
		table.insert(parts, part)
	end
	return parts[1], tonumber(parts[2]), tonumber(parts[3])
end

--- Create the custom previewer extending buffer_or_file.
---@return table previewer_class
local function create_previewer()
	local builtin_previewer = require("fzf-lua.previewer.builtin")
	local previewer = builtin_previewer.buffer_or_file:extend()

	function previewer:new(o, opts, fzf_win)
		previewer.super.new(self, o, opts, fzf_win)
		setmetatable(self, previewer)
		return self
	end

	-- luacheck: ignore self
	function previewer:parse_entry(entry_str)
		local file, start_line = parse_entry_fields(entry_str)
		return {
			path = file,
			line = start_line or 1,
			col = 1,
		}
	end

	function previewer:populate_preview_buf(entry_str)
		previewer.super.populate_preview_buf(self, entry_str)
		local _, start_line, end_line = parse_entry_fields(entry_str)
		if self.preview_bufnr and vim.api.nvim_buf_is_valid(self.preview_bufnr) and start_line and end_line then
			for i = start_line, end_line do
				pcall(vim.api.nvim_buf_add_highlight, self.preview_bufnr, -1, "Search", i - 1, 0, -1)
			end
		end
	end

	return previewer
end

--- Build the actions table for fzf-lua.
---@return table actions
local function make_actions()
	return {
		["default"] = function(selected)
			local file, start_line = parse_entry_fields(selected[1])
			open_file(file, start_line)
		end,
		["ctrl-v"] = function(selected)
			local file, start_line = parse_entry_fields(selected[1])
			open_file(file, start_line, "vsplit")
		end,
		["ctrl-s"] = function(selected)
			local file, start_line = parse_entry_fields(selected[1])
			open_file(file, start_line, "split")
		end,
		["ctrl-t"] = function(selected)
			local file, start_line = parse_entry_fields(selected[1])
			open_file(file, start_line, "tabedit")
		end,
	}
end

--- Fallback picker using vim.ui.select.
---@param results table[]
local function ui_select(results)
	vim.ui.select(results, {
		prompt = "Vecgrep results",
		format_item = format_result,
	}, function(choice)
		if choice then
			open_file(choice.file, choice.start_line)
		end
	end)
end

--- Static search: run query once, show results in fzf-lua (or vim.ui.select).
---@param query string
---@param opts? table
function M.search(query, opts)
	opts = opts or {}

	runner.search(query, opts, function(results)
		if #results == 0 then
			vim.notify("vecgrep: no results", vim.log.levels.INFO)
			return
		end

		if not has_fzf_lua then
			ui_select(results)
			return
		end

		local fzf_exec = require("fzf-lua").fzf_exec

		fzf_exec(function(fzf_cb)
			for _, r in ipairs(results) do
				fzf_cb(make_entry(r.file, r.start_line, r.end_line, r.score))
			end
			fzf_cb()
		end, {
			prompt = "Vecgrep> ",
			previewer = create_previewer(),
			fzf_opts = {
				["--delimiter"] = delimiter,
				["--with-nth"] = "5",
				["--no-sort"] = "",
			},
			actions = make_actions(),
		})
	end)
end

--- Live interactive search: queries a warm vecgrep server on each keystroke.
--- Requires fzf-lua.
---@param opts? table
function M.live(opts)
	opts = opts or {}

	if not has_fzf_lua then
		vim.notify("vecgrep: live mode requires fzf-lua", vim.log.levels.ERROR)
		return
	end

	runner.ensure_server(opts, function()
		local fzf_live = require("fzf-lua").fzf_live

		fzf_live(function(query)
			if not query or query == "" then
				return "true" -- shell no-op
			end
			return runner.build_curl_cmd(query, opts)
		end, {
			prompt = "Vecgrep Live> ",
			previewer = create_previewer(),
			exec_empty_query = true,
			fn_transform = function(line)
				local ok, decoded = pcall(vim.json.decode, line)
				if ok and decoded then
					return make_entry(decoded.file, decoded.start_line, decoded.end_line, decoded.score)
				end
				return nil
			end,
			fzf_opts = {
				["--delimiter"] = delimiter,
				["--with-nth"] = "5",
				["--no-sort"] = "",
				["--disabled"] = "",
			},
			actions = make_actions(),
		})
	end)
end

return M
