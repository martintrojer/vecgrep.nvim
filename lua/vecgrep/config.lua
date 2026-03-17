local M = {}

M.defaults = {
	cmd = "vecgrep",
	args = {},
	top_k = nil,
	threshold = nil,
	search_from_root = false,
	debug = false,
	server_port = nil,
}

M.options = M.defaults

return M
