local runner = require("vecgrep.runner")
local config = require("vecgrep.config")

local M = {}

local has_telescope, _ = pcall(require, "telescope")

--- Open a file at a specific line.
---@param file string
---@param line integer
---@param cmd? string edit command ("edit", "vsplit", "split")
local function open_file(file, line, cmd)
	vim.cmd((cmd or "edit") .. " +" .. line .. " " .. vim.fn.fnameescape(file))
end

--- Format a result for display.
---@param r table {file, start_line, end_line, score}
---@return string
local function format_result(r)
	return string.format("[%.3f] %s:%d:%d", r.score, r.file, r.start_line, r.end_line)
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

--- Static search: run query once, show results in Telescope (or vim.ui.select).
---@param query string
---@param opts? table
function M.search(query, opts)
	opts = opts or {}

	runner.search(query, opts, function(results)
		if #results == 0 then
			vim.notify("vecgrep: no results", vim.log.levels.INFO)
			return
		end

		if not has_telescope then
			ui_select(results)
			return
		end

		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")
		local previewers = require("telescope.previewers")

		pickers
			.new(opts.telescope or {}, {
				prompt_title = "Vecgrep: " .. query,
				finder = finders.new_table({
					results = results,
					entry_maker = function(r)
						return {
							value = r,
							display = format_result(r),
							ordinal = r.file,
							filename = r.file,
							lnum = r.start_line,
						}
					end,
				}),
				sorter = conf.generic_sorter(opts),
				previewer = previewers.new_buffer_previewer({
					title = "Vecgrep Preview",
					define_preview = function(self, entry)
						local r = entry.value
						conf.buffer_previewer_maker(r.file, self.state.bufnr, {
							bufname = r.file,
							winid = self.state.winid,
							callback = function(bufnr)
								-- highlight the matched chunk region
								pcall(function()
									for i = r.start_line, r.end_line do
										vim.api.nvim_buf_add_highlight(bufnr, -1, "Search", i - 1, 0, -1)
									end
								end)
							end,
						})
					end,
				}),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if entry then
							open_file(entry.value.file, entry.value.start_line)
						end
					end)
					map("i", "<C-v>", function()
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if entry then
							open_file(entry.value.file, entry.value.start_line, "vsplit")
						end
					end)
					map("i", "<C-x>", function()
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if entry then
							open_file(entry.value.file, entry.value.start_line, "split")
						end
					end)
					return true
				end,
			})
			:find()
	end)
end

--- Live interactive picker: re-runs vecgrep on each keystroke (debounced).
--- Requires Telescope.
---@param opts? table
function M.live(opts)
	opts = opts or {}

	if not has_telescope then
		vim.notify("vecgrep: live mode requires telescope.nvim", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	local cfg = config.options
	local debounce_ms = opts.debounce_ms or cfg.debounce_ms

	pickers
		.new(opts.telescope or {}, {
			prompt_title = "Vecgrep Live",
			finder = finders.new_dynamic({
				fn = function(prompt)
					if not prompt or prompt == "" then
						return {}
					end

					-- Synchronous wrapper: run vecgrep and wait for results
					local results = {}
					local done = false

					runner.search(prompt, opts, function(r)
						results = r
						done = true
					end)

					-- vim.wait handles vim.schedule callbacks
					vim.wait(30000, function()
						return done
					end, 50)

					return results
				end,
				entry_maker = function(r)
					return {
						value = r,
						display = format_result(r),
						ordinal = r.file,
						filename = r.file,
						lnum = r.start_line,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = previewers.new_buffer_previewer({
				title = "Vecgrep Preview",
				define_preview = function(self, entry)
					local r = entry.value
					conf.buffer_previewer_maker(r.file, self.state.bufnr, {
						bufname = r.file,
						winid = self.state.winid,
						callback = function(bufnr)
							pcall(function()
								for i = r.start_line, r.end_line do
									vim.api.nvim_buf_add_highlight(bufnr, -1, "Search", i - 1, 0, -1)
								end
							end)
						end,
					})
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						open_file(entry.value.file, entry.value.start_line)
					end
				end)
				map("i", "<C-v>", function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						open_file(entry.value.file, entry.value.start_line, "vsplit")
					end
				end)
				map("i", "<C-x>", function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						open_file(entry.value.file, entry.value.start_line, "split")
					end
				end)
				return true
			end,
			debounce = debounce_ms,
		})
		:find()
end

return M
