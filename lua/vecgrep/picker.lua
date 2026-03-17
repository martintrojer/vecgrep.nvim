local runner = require("vecgrep.runner")
local log = require("vecgrep.log").log

local M = {}

local has_snacks, Snacks = pcall(require, "snacks")

--- Highlight group for a score value (matching vecgrep TUI).
---@param score number
---@return string highlight group name
local function score_hl(score)
	if score >= 0.7 then
		return "DiagnosticOk"
	elseif score >= 0.5 then
		return "DiagnosticWarn"
	else
		return "DiagnosticError"
	end
end

--- Format a result for display (used by vim.ui.select fallback).
---@param r table {file, start_line, end_line, score}
---@return string
local function format_result(r)
	return string.format("[%.3f] %s:%d-%d", r.score, r.file, r.start_line, r.end_line)
end

--- Fallback picker using vim.ui.select.
---@param results table[]
local function ui_select(results)
	vim.ui.select(results, {
		prompt = "Vecgrep results",
		format_item = format_result,
	}, function(choice)
		if choice then
			vim.cmd("edit +" .. choice.start_line .. " " .. vim.fn.fnameescape(choice.file))
		end
	end)
end

--- Format function for snacks.picker items.
---@param item snacks.picker.Item
---@param picker snacks.Picker
---@return snacks.picker.Highlight[]
local function format_item(item, picker)
	local ret = {} ---@type snacks.picker.Highlight[]
	local score_text = string.format("[%.3f] ", item.vecgrep_score or 0)
	table.insert(ret, { score_text, score_hl(item.vecgrep_score or 0) })

	-- Use snacks filename formatter for the rest
	local file_parts = Snacks.picker.format.filename(item, picker)
	for _, part in ipairs(file_parts) do
		table.insert(ret, part)
	end

	-- Append line range
	if item.start_line and item.end_line then
		table.insert(ret, { string.format(":%d-%d", item.start_line, item.end_line), "Comment" })
	end

	return ret
end

--- Preview function: file preview with chunk region highlighted.
---@param ctx snacks.picker.preview.ctx
local function preview_item(ctx)
	-- Use the built-in file previewer for file loading + syntax
	Snacks.picker.preview.file(ctx)

	-- Add Search highlights for the matched chunk region
	local item = ctx.item
	local start_line = item.start_line
	local end_line = item.end_line
	if ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) and start_line and end_line then
		local ns = vim.api.nvim_create_namespace("vecgrep_preview")
		for i = start_line, end_line do
			pcall(vim.api.nvim_buf_set_extmark, ctx.buf, ns, i - 1, 0, {
				end_row = i - 1,
				end_col = 0,
				line_hl_group = "Search",
			})
		end
	end
end

--- Transform a JSONL item from proc source into a snacks.picker item.
--- The item arrives with item.text set to the raw JSONL line.
---@param item snacks.picker.finder.Item
---@return false|nil
local function transform_jsonl(item)
	log("transform_jsonl: raw =", item.text)
	local ok, decoded = pcall(vim.json.decode, item.text)
	if not ok or not decoded then
		return false
	end
	log("transform_jsonl: file =", decoded.file, "root =", tostring(decoded.root))
	item.text = string.format("[%.3f] %s:%d-%d", decoded.score, decoded.file, decoded.start_line, decoded.end_line)
	item.file = decoded.file
	item.pos = { decoded.start_line, 0 }
	item.start_line = decoded.start_line
	item.end_line = decoded.end_line
	item.vecgrep_score = decoded.score
	if decoded.root then
		item.cwd = decoded.root
	end
end

--- Static search: run query once, show results in snacks.picker (or vim.ui.select).
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

		if not has_snacks then
			ui_select(results)
			return
		end

		local items = {}
		local item_cwd = root or fallback_cwd
		for i, r in ipairs(results) do
			table.insert(items, {
				text = string.format("[%.3f] %s:%d-%d", r.score, r.file, r.start_line, r.end_line),
				file = r.file,
				cwd = item_cwd,
				pos = { r.start_line, 0 },
				start_line = r.start_line,
				end_line = r.end_line,
				vecgrep_score = r.score,
				idx = i,
			})
		end

		Snacks.picker({
			title = "Vecgrep",
			items = items,
			format = format_item,
			preview = preview_item,
			sort = { fields = { "idx" } },
			cwd = root or fallback_cwd,
		})
	end)
end

--- Live interactive search: queries a warm vecgrep server on each keystroke.
--- Requires snacks.nvim.
---@param opts? table
function M.live(opts)
	opts = opts or {}

	if not has_snacks then
		vim.notify("vecgrep: live mode requires snacks.nvim", vim.log.levels.ERROR)
		return
	end

	local cwd = runner.buf_dir()
	log("live: buf_dir =", cwd)

	runner.ensure_server(opts, function(port)
		log("live: server ready, picker cwd =", cwd)

		local picker_ref = nil

		-- Poll /status to update picker title with indexing progress
		runner.poll_status(port, function(status)
			if picker_ref and status.status == "indexing" then
				local total = status.total and tostring(status.total) or "??"
				picker_ref.title = string.format("Vecgrep Live (indexing %d/%s)", status.indexed, total)
				picker_ref:update_titles()
			end
			if picker_ref and status.scope and #status.scope > 0 then
				picker_ref.opts.cwd = status.scope[1]
			end
		end, function(status)
			if picker_ref then
				if status.files and status.chunks then
					picker_ref.title = string.format("Vecgrep Live (%d files, %d chunks)", status.files, status.chunks)
				else
					picker_ref.title = "Vecgrep Live"
				end
				picker_ref:update_titles()
			end
		end)

		picker_ref = Snacks.picker({
			title = "Vecgrep Live (indexing...)",
			live = true,
			cwd = cwd,
			matcher = { fuzzy = false },
			sort = { fields = { "idx" } },
			format = format_item,
			preview = preview_item,
			finder = function(_, ctx)
				local query = ctx.filter.search
				if not query or query == "" then
					return function() end
				end

				local curl_args = runner.build_curl_args(query, opts)
				return require("snacks.picker.source.proc").proc(
					ctx:opts({
						cmd = "curl",
						args = curl_args,
						notify = false,
						transform = transform_jsonl,
					}),
					ctx
				)
			end,
		})
	end)
end

return M
