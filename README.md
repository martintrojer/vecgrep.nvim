# vecgrep.nvim

Neovim plugin for [vecgrep](https://github.com/mtrojer/vecgrep) — semantic grep that searches your codebase by meaning using local embeddings.

## Features

- **Static search** — run a query, browse results in fzf-lua (or `vim.ui.select`)
- **Live search** — interactive fzf-lua picker backed by a warm vecgrep server (model loaded once, instant queries)
- **Preview** — file preview with syntax highlighting and matched chunk region highlighted
- **Score coloring** — green (high), yellow (medium), red (low) similarity scores
- **Index management** — reindex, stats, and cache clearing from within Neovim

## Requirements

- [vecgrep](https://github.com/mtrojer/vecgrep) binary on `$PATH` (with `--serve` support)
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

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "martintrojer/vecgrep.nvim",
  requires = { "ibhagwan/fzf-lua" },
  config = function()
    require("vecgrep").setup()
  end,
}
```

## Configuration

```lua
require("vecgrep").setup({
  cmd = "vecgrep",        -- path to vecgrep binary
  args = {},              -- extra default CLI args (e.g. {"--hidden"})
  top_k = 20,             -- number of results (-k)
  threshold = 0.3,        -- minimum similarity (--threshold)
  context = 3,            -- context lines (-C)
  paths = { "." },        -- default search paths
  debounce_ms = 300,      -- debounce for live mode (ms)
})
```

## Usage

### Commands

| Command | Description |
|---|---|
| `:Vecgrep <query>` | Semantic search for `<query>` |
| `:VecgrepLive` | Live interactive semantic search (starts server on first use) |
| `:VecgrepReindex [path]` | Force full re-index |
| `:VecgrepStats` | Show index statistics |
| `:VecgrepClearCache` | Delete cached index |

### How live mode works

`:VecgrepLive` starts a `vecgrep --serve` HTTP server in the background on first invocation. The server loads the embedding model and index once, then stays warm for the session. Each keystroke triggers a `curl` request to the server — just embedding + search, no model loading overhead. The server is stopped automatically when Neovim exits.

### Lua API

```lua
require("vecgrep").search("error handling")
require("vecgrep").live()
require("vecgrep").reindex("./src")
require("vecgrep").stats()
require("vecgrep").clear_cache()
require("vecgrep").stop_server()  -- manually stop the background server
```

### Keymaps

```lua
vim.keymap.set("n", "<leader>vs", function()
  require("vecgrep").search(vim.fn.input("Vecgrep: "))
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
