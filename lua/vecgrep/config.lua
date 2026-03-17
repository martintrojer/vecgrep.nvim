local M = {}

M.defaults = {
	cmd = "vecgrep",
	args = {},
	top_k = nil,
	threshold = nil,
	debug = false,
	server_port = nil,
}

M.options = M.defaults

return M
