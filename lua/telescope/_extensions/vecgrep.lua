local picker = require("vecgrep.picker")

return require("telescope").register_extension({
	exports = {
		search = function(opts)
			opts = opts or {}
			local query = opts.query or opts.args
			if not query or query == "" then
				vim.notify("vecgrep: query required (e.g. :Telescope vecgrep search query=foo)", vim.log.levels.ERROR)
				return
			end
			picker.search(query, opts)
		end,
		live = function(opts)
			picker.live(opts)
		end,
	},
})
