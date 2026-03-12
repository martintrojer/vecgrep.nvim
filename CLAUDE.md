# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

vecgrep.nvim is a Neovim plugin that wraps the [vecgrep](https://github.com/mtrojer/vecgrep) CLI — a semantic grep tool that uses local embeddings to search codebases by meaning. The plugin parses vecgrep's `--json` (JSONL) output and presents results via Telescope (with `vim.ui.select` fallback).

## Plugin Structure

```
lua/
  vecgrep.lua                          -- Entry point: require("vecgrep").setup(opts), user commands
  vecgrep/
    config.lua                         -- Default config + merged options
    runner.lua                         -- Async CLI wrapper (vim.system), JSONL parsing
    picker.lua                         -- Telescope pickers (static + live) and vim.ui.select fallback
  telescope/
    _extensions/
      vecgrep.lua                      -- Telescope extension: :Telescope vecgrep search/live
```

## Architecture

**Data flow:** user command → `runner.search()` spawns `vecgrep --json` async via `vim.system()` → parses JSONL stdout → `picker` displays results in Telescope or `vim.ui.select` → `<CR>` opens file at correct line.

**Module responsibilities:**

| Module | Role |
|---|---|
| `config.lua` | Holds `defaults` and `options` tables (cmd, args, top_k, threshold, context, paths, debounce_ms) |
| `runner.lua` | `search(query, opts, callback)` — builds CLI args, runs async, parses JSONL. `run_command(args, callback)` — arbitrary vecgrep commands |
| `picker.lua` | `search(query)` — static Telescope picker with vim.ui.select fallback. `live()` — dynamic Telescope finder that re-runs vecgrep per keystroke (debounced) |
| `vecgrep.lua` | `setup(opts)` merges config, registers user commands. Convenience wrappers for search/live/reindex/stats/clear_cache |
| `telescope/_extensions/vecgrep.lua` | Registers `:Telescope vecgrep search query=...` and `:Telescope vecgrep live` |

## Key Design Decisions

- **Async everywhere**: All CLI calls use `vim.system()` with callbacks + `vim.schedule()` to avoid blocking the editor.
- **JSONL parsing**: vecgrep `--json` outputs one JSON object per line: `{"file":"...","start_line":42,"end_line":58,"score":0.847,"text":"..."}`. Parsed with `vim.json.decode()` per line.
- **Telescope live mode**: Uses `finders.new_dynamic()` with the `debounce` option. The `fn` callback uses `vim.wait()` to bridge async `runner.search()` into a synchronous return.
- **Fallback**: If Telescope is not installed, static search falls back to `vim.ui.select`. Live mode requires Telescope and shows an error if missing.
- **File opening**: `vim.cmd("edit +" .. line .. " " .. vim.fn.fnameescape(path))`. Supports `<C-v>` (vsplit) and `<C-x>` (split) in Telescope.
- **Preview**: Custom `new_buffer_previewer` that loads the file and highlights the matched chunk region (`start_line` to `end_line`) using the `Search` highlight group.

## User Commands

| Command | Action |
|---|---|
| `:Vecgrep <query>` | Static semantic search |
| `:VecgrepLive` | Live interactive semantic search |
| `:VecgrepReindex [path]` | Force full re-index |
| `:VecgrepStats` | Show index statistics |
| `:VecgrepClearCache` | Delete cached index |

## Configuration Defaults

```lua
{
  cmd = "vecgrep",        -- path to vecgrep binary
  args = {},              -- extra default CLI args
  top_k = 20,             -- number of results (-k)
  threshold = 0.3,        -- minimum similarity (--threshold)
  context = 3,            -- context lines (-C)
  paths = { "." },        -- search paths
  debounce_ms = 300,      -- debounce for live mode
}
```

## Dependencies

- **Required**: `vecgrep` binary on `$PATH`
- **Optional**: `nvim-telescope/telescope.nvim` (needed for live mode, enhances static mode)

## Before Committing

Always run these before committing:

```bash
stylua lua/
luacheck lua/
```

## Conventions

- All Lua modules return a table `M`.
- Use `---@param` / `---@return` LuaLS annotations for public functions.
- Async operations use `vim.system()` callbacks and `vim.schedule()` for safety.
- No external Lua dependencies beyond Neovim's stdlib and optional Telescope.
