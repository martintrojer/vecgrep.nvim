# vecgrep.nvim

Neovim plugin for [vecgrep](https://github.com/mtrojer/vecgrep) — semantic grep that searches your codebase by meaning using local embeddings.

## Features

- **Static search** — run a query, browse results in Telescope (or `vim.ui.select`)
- **Live search** — interactive Telescope picker that re-runs semantic search on each keystroke (debounced)
- **Preview** — file preview with the matched chunk region highlighted
- **Index management** — reindex, stats, and cache clearing from within Neovim

## Requirements

- [vecgrep](https://github.com/mtrojer/vecgrep) binary on `$PATH`
- Neovim >= 0.10
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, but needed for live mode)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "martintrojer/vecgrep.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "martintrojer/vecgrep.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
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
| `:VecgrepLive` | Live interactive semantic search |
| `:VecgrepReindex [path]` | Force full re-index |
| `:VecgrepStats` | Show index statistics |
| `:VecgrepClearCache` | Delete cached index |

### Telescope extension

```vim
:Telescope vecgrep search query=error handling
:Telescope vecgrep live
```

### Lua API

```lua
require("vecgrep").search("error handling")
require("vecgrep").live()
require("vecgrep").reindex("./src")
require("vecgrep").stats()
require("vecgrep").clear_cache()
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

In the Telescope picker:

| Key | Action |
|---|---|
| `<CR>` | Open file at match line |
| `<C-v>` | Open in vertical split |
| `<C-x>` | Open in horizontal split |

## License

MIT
