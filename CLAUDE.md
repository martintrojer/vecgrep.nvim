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
    log.lua                            -- Debug logging (conditional on config.debug)
```

## Architecture

**Data flow:**
- **Static search:** user command → `runner.search()` spawns `vecgrep --json` async via `vim.system()` → parses JSONL stdout → `fzf_lua.fzf_exec()` with pre-fetched items → `<CR>` opens file at correct line.
- **Live search:** user command → `runner.ensure_server()` starts `vecgrep --serve` (if not already running) → `fzf_lua.fzf_live()` → callback runs `curl` via `runner.build_curl_args()` against the warm server → parses JSONL → results displayed with preview.

**Server lifecycle:** The vecgrep server is started lazily on first `:VecgrepLive` invocation. It loads the ONNX embedding model and index once, then serves queries over HTTP. The server is stopped automatically on `VimLeavePre`. The port is auto-detected from the server's stderr output (`Listening on http://127.0.0.1:PORT`).

**Module responsibilities:**

| Module | Role |
|---|---|
| `config.lua` | Holds `defaults` and `options` tables (cmd, args, top_k, threshold, debug, server_port) |
| `runner.lua` | `search(query, opts, callback)` — one-shot async search. `start_server/stop_server/ensure_server` — server lifecycle. `build_curl_args(query, opts)` — curl args for live search. `poll_status(port, progress_cb, done_cb)` — poll `/status` endpoint. `run_command(args, callback)` — arbitrary vecgrep commands |
| `picker.lua` | `search(query)` — static fzf-lua picker with vim.ui.select fallback. `live()` — fzf-lua live picker backed by the vecgrep HTTP server |
| `vecgrep.lua` | `setup(opts)` merges config, registers user commands + VimLeavePre cleanup. Convenience wrappers for search/live/reindex/stats/clear_cache/stop_server |

## Key Design Decisions

- **Server-backed live mode**: Live search starts a `vecgrep --serve` HTTP server on first use. The server loads the ONNX model and index once, then each keystroke query is just a `curl` request — embedding + dot-product search with no startup overhead. fzf-lua's `fzf_live` handles the callback lifecycle.
- **One-shot static mode**: Static search spawns a fresh `vecgrep --json` process via `vim.system()`. Acceptable since it's a single query.
- **JSONL parsing**: vecgrep outputs one JSON object per line: `{"file":"...","start_line":42,"end_line":58,"score":0.847,"text":"..."}`. Parsed in Lua with `vim.json.decode()` in both modes.
- **Fallback**: If fzf-lua is not installed, static search falls back to `vim.ui.select`. Live mode requires fzf-lua and shows an error if missing.
- **File opening**: Custom `open_result` action handles `<CR>`. Paths are resolved against the project root (from vecgrep's `root` JSONL field). Absolute paths from vecgrep are used as-is.
- **Preview**: Custom fzf-lua previewer extends `buffer_or_file` to add `Search` line highlights for the matched chunk region (start_line to end_line) via extmarks.
- **Score color coding**: Green (>= 0.7), yellow (>= 0.5), red (< 0.5), matching the vecgrep TUI. Uses `DiagnosticOk`/`DiagnosticWarn`/`DiagnosticError` highlight groups.

## User Commands

| Command | Action |
|---|---|
| `:Vecgrep[!] <query>` | Static semantic search (`!` toggles root search) |
| `:VecgrepLive[!]` | Live interactive semantic search (`!` toggles root search) |
| `:VecgrepReindex [path]` | Force full re-index |
| `:VecgrepStats` | Show index statistics (and server status if running) |
| `:VecgrepClearCache` | Delete cached index |

## Configuration Defaults

```lua
{
  cmd = "vecgrep",        -- path to vecgrep binary
  args = {},              -- extra default CLI args
  top_k = nil,             -- number of results (-k), nil uses vecgrep default
  threshold = nil,         -- minimum similarity (--threshold), nil uses vecgrep default
  search_from_root = false, -- always search from project root (via vecgrep --show-root)
  debug = false,          -- write debug log to stdpath("data")/vecgrep.log
  server_port = nil,      -- fixed port for --serve (nil = auto-detect)
}
```

Search path is derived automatically from the current buffer's directory. vecgrep finds its own project root from there.

## Dependencies

- **Required**: `vecgrep` binary (with `--serve` support) on `$PATH`
- **Optional**: [fzf-lua](https://github.com/ibhagwan/fzf-lua) (needed for live mode, enhances static mode)

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
