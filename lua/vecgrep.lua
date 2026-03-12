local config = require("vecgrep.config")
local runner = require("vecgrep.runner")
local picker = require("vecgrep.picker")

local M = {}

--- Setup vecgrep with user options.
---@param opts? table user configuration (merged with defaults)
function M.setup(opts)
	config.options = vim.tbl_deep_extend("force", config.defaults, opts or {})

	-- Stop vecgrep server when Neovim exits
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			runner.stop_server()
		end,
	})

	vim.api.nvim_create_user_command("Vecgrep", function(cmd)
		M.search(cmd.args)
	end, { nargs = 1, desc = "Semantic search with vecgrep" })

	vim.api.nvim_create_user_command("VecgrepLive", function()
		M.live()
	end, { desc = "Live semantic search with vecgrep" })

	vim.api.nvim_create_user_command("VecgrepReindex", function(cmd)
		local path = cmd.args ~= "" and cmd.args or nil
		M.reindex(path)
	end, { nargs = "?", desc = "Re-index with vecgrep" })

	vim.api.nvim_create_user_command("VecgrepStats", function()
		M.stats()
	end, { desc = "Show vecgrep index statistics" })

	vim.api.nvim_create_user_command("VecgrepClearCache", function()
		M.clear_cache()
	end, { desc = "Clear vecgrep index cache" })
end

--- Run a static semantic search and open the picker.
---@param query string
---@param opts? table
function M.search(query, opts)
	picker.search(query, opts)
end

--- Open the live interactive semantic search picker.
---@param opts? table
function M.live(opts)
	picker.live(opts)
end

--- Force a full re-index.
---@param path? string path to re-index (defaults to ".")
function M.reindex(path)
	local args = { "--reindex", path or "." }
	vim.notify("vecgrep: reindexing " .. (path or ".") .. " ...", vim.log.levels.INFO)
	runner.run_command(args, function(stdout, stderr, code)
		if code == 0 then
			vim.notify("vecgrep: reindex complete\n" .. stdout, vim.log.levels.INFO)
		else
			vim.notify("vecgrep: reindex failed\n" .. stderr, vim.log.levels.ERROR)
		end
	end)
end

--- Show index statistics.
function M.stats()
	runner.run_command({ "--stats" }, function(stdout, stderr, code)
		if code == 0 then
			vim.notify("vecgrep stats:\n" .. stdout, vim.log.levels.INFO)
		else
			vim.notify("vecgrep: stats failed\n" .. stderr, vim.log.levels.ERROR)
		end
	end)
end

--- Stop the vecgrep server if running.
function M.stop_server()
	runner.stop_server()
end

--- Delete the cached index.
function M.clear_cache()
	runner.run_command({ "--clear-cache" }, function(stdout, stderr, code)
		if code == 0 then
			vim.notify("vecgrep: cache cleared\n" .. stdout, vim.log.levels.INFO)
		else
			vim.notify("vecgrep: clear-cache failed\n" .. stderr, vim.log.levels.ERROR)
		end
	end)
end

return M
