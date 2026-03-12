local M = {}

local log_path = vim.fn.stdpath("data") .. "/vecgrep.log"

---@param ... any
function M.log(...)
	local config = require("vecgrep.config")
	if not config.options.debug then
		return
	end
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	local line = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ") .. "\n"
	local f = io.open(log_path, "a")
	if f then
		f:write(line)
		f:close()
	end
end

return M
