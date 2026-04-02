# vecgrep.nvim

Neovim plugin for [vecgrep](https://github.com/martintrojer/vecgrep) — semantic grep that searches your codebase by meaning using local embeddings.

## Features

- **Static search** — run a query, browse results in fzf-lua (or `vim.ui.select`)
- **Live search** — interactive fzf-lua picker backed by a warm vecgrep server (model loaded once, instant queries)
- **Preview** — file preview with syntax highlighting and matched chunk region highlighted
- **Score coloring** — green (high), yellow (medium), red (low) similarity scores
- **Index management** — reindex, stats, and cache clearing from within Neovim

## Requirements

- [vecgrep](https://github.com/martintrojer/vecgrep) binary on `$PATH` (with `--serve` support)
- Neovim >= 0.10
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (optional, but needed for live mode and enhanced static mode)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "martintrojer/vecgrep.nvim",
  dependencies = { "ibhagwan/fzf-lua" },
  opts = {},
}
```

## Configuration

```lua
require("vecgrep").setup({
  cmd = "vecgrep",        -- path to vecgrep binary
  args = {},              -- extra default CLI args (e.g. {"--hidden"})
  top_k = nil,             -- number of results (-k), nil uses vecgrep default
  threshold = nil,         -- minimum similarity (--threshold), nil uses vecgrep default
  search_from_root = false, -- always search from project root (via vecgrep --show-root)
  debug = false,          -- write debug log to stdpath("data")/vecgrep.log
})
```

The search path is derived automatically from the current buffer's directory. vecgrep finds its own project root from there.

## Usage

### Commands

| Command | Description |
|---|---|
| `:Vecgrep[!] <query>` | Semantic search for `<query>` (`!` toggles root search) |
| `:VecgrepLive[!]` | Live interactive semantic search (`!` toggles root search) |
| `:VecgrepReindex` | Force full re-index |
| `:VecgrepStats` | Show index statistics (and server status if running) |
| `:VecgrepClearCache` | Delete cached index |

### How live mode works

`:VecgrepLive` starts a `vecgrep --serve` HTTP server in the background on first invocation. The server loads the embedding model and index once, then stays warm for the session. Each keystroke triggers a query to the server via fzf-lua's live picker — just embedding + search, no model loading overhead. The server is stopped automatically when Neovim exits.

### Lua API

```lua
require("vecgrep").search("error handling")
require("vecgrep").live()
require("vecgrep").reindex()
require("vecgrep").stats()
require("vecgrep").clear_cache()
require("vecgrep").stop_server()  -- manually stop the background server
```

### Keymaps

```lua
vim.keymap.set("n", "<leader>vs", function()
  vim.ui.input({ prompt = "Vecgrep: " }, function(input)
    if input and input ~= "" then
      require("vecgrep").search(input)
    end
  end)
end, { desc = "Vecgrep search" })

vim.keymap.set("n", "<leader>vl", function()
  require("vecgrep").live()
end, { desc = "Vecgrep live" })
```

## Picker Keybindings

In the fzf-lua picker:

| Key | Action |
|---|---|
| `<CR>` | Open file at match line |
| `<C-v>` | Open in vertical split |
| `<C-s>` | Open in horizontal split |
| `<C-t>` | Open in new tab |

## License

MIT
