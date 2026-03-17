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
		local search_opts = {}
		if cmd.bang then
			search_opts.from_root = not config.options.search_from_root
		end
		M.search(cmd.args, search_opts)
	end, { nargs = 1, bang = true, desc = "Semantic search with vecgrep (! toggles root)" })

	vim.api.nvim_create_user_command("VecgrepLive", function(cmd)
		local live_opts = {}
		if cmd.bang then
			live_opts.from_root = not config.options.search_from_root
		end
		M.live(live_opts)
	end, { bang = true, desc = "Live semantic search with vecgrep (! toggles root)" })

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
---@param path? string path to re-index (defaults to current buffer's directory)
function M.reindex(path)
	path = path or vim.fn.expand("%:p:h")
	local args = { "--reindex", path }
	vim.notify("vecgrep: reindexing " .. path .. " ...", vim.log.levels.INFO)
	runner.run_command(args, function(stdout, stderr, code)
		if code == 0 then
			vim.notify("vecgrep: reindex complete\n" .. stdout, vim.log.levels.INFO)
		else
			vim.notify("vecgrep: reindex failed\n" .. stderr, vim.log.levels.ERROR)
		end
	end)
end

--- Show index statistics, and server status if a server is running.
function M.stats()
	local parts = {}
	local pending = 1

	local function maybe_notify()
		pending = pending - 1
		if pending > 0 then
			return
		end
		if #parts == 0 then
			vim.notify("vecgrep: no stats available", vim.log.levels.WARN)
		else
			vim.notify(table.concat(parts, "\n"), vim.log.levels.INFO)
		end
	end

	if runner._server_port then
		pending = pending + 1
		local url = string.format("http://127.0.0.1:%d/status", runner._server_port)
		vim.system({ "curl", "-s", url }, { text = true }, function(result)
			vim.schedule(function()
				if result.code == 0 and result.stdout then
					local ok, s = pcall(vim.json.decode, result.stdout)
					if ok then
						local info = {}
						if s.version then
							table.insert(info, "version: " .. s.version)
						end
						if s.root then
							table.insert(info, "root: " .. s.root)
						end
						if s.scope and #s.scope > 0 then
							table.insert(info, "scope: " .. table.concat(s.scope, ", "))
						end
						if s.status == "ready" then
							table.insert(info, string.format("status: ready (%d files, %d chunks)", s.files, s.chunks))
						else
							local total = s.total and tostring(s.total) or "??"
							table.insert(
								info,
								string.format("status: indexing %d/%s files, %d chunks", s.indexed, total, s.chunks)
							)
						end
						table.insert(parts, "server:\n  " .. table.concat(info, "\n  "))
					end
				end
				maybe_notify()
			end)
		end)
	end

	runner.run_command({ "--stats" }, function(_, stderr)
		local output = (stderr or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if output ~= "" then
			table.insert(parts, output)
		end
		maybe_notify()
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
