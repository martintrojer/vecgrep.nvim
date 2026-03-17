local M = {}

M.defaults = {
	cmd = "vecgrep",
	args = {},
	top_k = 20,
	threshold = 0.3,
	debug = false,
	server_port = nil,
}

M.options = M.defaults

return M
