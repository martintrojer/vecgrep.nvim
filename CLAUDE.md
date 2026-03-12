# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

vecgrep.nvim is a Neovim plugin that wraps the [vecgrep](https://github.com/mtrojer/vecgrep) CLI — a semantic grep tool that uses local embeddings to search codebases by meaning. The plugin parses vecgrep's `--json` (JSONL) output and presents results via fzf-lua (with `vim.ui.select` fallback).

## Plugin Structure

```
lua/
  vecgrep.lua                          -- Entry point: require("vecgrep").setup(opts), user commands
  vecgrep/
    config.lua                         -- Default config + merged options
    runner.lua                         -- CLI wrapper, server lifecycle, curl cmd builder
    picker.lua                         -- fzf-lua pickers (static + live) and vim.ui.select fallback
```

## Architecture

**Data flow:**
- **Static search:** user command → `runner.search()` spawns `vecgrep --json` async via `vim.system()` → parses JSONL stdout → `picker` feeds results to `fzf_exec()` → `<CR>` opens file at correct line.
- **Live search:** user command → `runner.ensure_server()` starts `vecgrep --serve` (if not already running) → `picker` calls `fzf_live()` with `runner.build_curl_cmd()` → fzf reloads on each keystroke via `curl` against the warm server → `fn_transform` parses JSONL → results displayed with preview.

**Server lifecycle:** The vecgrep server is started lazily on first `:VecgrepLive` invocation. It loads the ONNX embedding model and index once, then serves queries over HTTP. The server is stopped automatically on `VimLeavePre`. The port is auto-detected from the server's stderr output (`Listening on http://127.0.0.1:PORT`).

**Module responsibilities:**

| Module | Role |
|---|---|
| `config.lua` | Holds `defaults` and `options` tables (cmd, args, top_k, threshold, context, paths, debounce_ms) |
| `runner.lua` | `search(query, opts, callback)` — one-shot async search. `start_server/stop_server/ensure_server` — server lifecycle. `build_curl_cmd(query, opts)` — curl command for fzf_live reload. `run_command(args, callback)` — arbitrary vecgrep commands |
| `picker.lua` | `search(query)` — static fzf-lua picker with vim.ui.select fallback. `live()` — fzf_live picker backed by the vecgrep HTTP server |
| `vecgrep.lua` | `setup(opts)` merges config, registers user commands + VimLeavePre cleanup. Convenience wrappers for search/live/reindex/stats/clear_cache/stop_server |

## Key Design Decisions

- **Server-backed live mode**: Live search starts a `vecgrep --serve` HTTP server on first use. The server loads the ONNX model and index once, then each keystroke query is just a `curl` request — embedding + dot-product search with no startup overhead. fzf handles the `curl` process lifecycle and reload.
- **One-shot static mode**: Static search spawns a fresh `vecgrep --json` process via `vim.system()`. Acceptable since it's a single query.
- **JSONL parsing**: vecgrep outputs one JSON object per line: `{"file":"...","start_line":42,"end_line":58,"score":0.847,"text":"..."}`. In static mode, parsed in Lua with `vim.json.decode()`. In live mode, parsed by `fn_transform` before fzf displays entries.
- **Entry format**: Entries use `\x01` delimiter to embed structured data: `file\x01start_line\x01end_line\x01score\x01display_text`. fzf shows only field 5 (`--with-nth=5`), while the previewer and actions parse hidden fields 1-4.
- **Fallback**: If fzf-lua is not installed, static search falls back to `vim.ui.select`. Live mode requires fzf-lua and shows an error if missing.
- **File opening**: `vim.cmd("edit +" .. line .. " " .. vim.fn.fnameescape(path))`. Supports `<C-v>` (vsplit), `<C-s>` (split), and `<C-t>` (tabedit) in fzf-lua.
- **Preview**: Custom previewer extending `builtin.buffer_or_file` — overrides `parse_entry` to extract path/line from hidden fields, and `populate_preview_buf` to highlight the matched chunk region (`start_line` to `end_line`) using the `Search` highlight group.
- **Score color coding**: Green (>= 0.7), yellow (>= 0.5), red (< 0.5), matching the vecgrep TUI.

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

- **Required**: `vecgrep` binary (with `--serve` support) on `$PATH`
- **Optional**: [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua) (needed for live mode, enhances static mode)

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
- No external Lua dependencies beyond Neovim's stdlib and optional fzf-lua.
