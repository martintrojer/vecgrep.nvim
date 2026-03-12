local M = {}

M.defaults = {
	cmd = "vecgrep",
	args = {},
	top_k = 20,
	threshold = 0.3,
	context = 3,
	debounce_ms = 300,
}

M.options = M.defaults

return M
