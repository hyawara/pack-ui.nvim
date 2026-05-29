# pack-ui.nvim

A small `vim.pack` manager UI for Neovim 0.12+.

It uses a native Neovim floating-window UI and keeps the first render fast by reading package data with `vim.pack.get(nil, { info = false })`. Git update counts are collected asynchronously and cached until refresh or package mutations.

This repository is intentionally structured as a small, readable plugin. The goal is not just to work, but to show how a Neovim plugin can separate command entry, data loading, UI state, rendering, and side effects.

## Requirements

- Neovim 0.12+
- Git

## Installation

```lua
vim.pack.add({
    'https://github.com/hyawara/pack-ui.nvim',
})
```

## Usage

```vim
:PackUI
```

## Keys

| Key | Action |
| --- | --- |
| `g` | Open selected plugin GitHub repository |
| `j` / `k` | Navigate plugin list |
| `U` | Update all plugins |
| `u` | Update selected plugin |
| `x` | Delete selected plugin |
| `r` | Refresh list |
| `<CR>` | Toggle inline details for selected plugin |
| `q` | Close |

## Updating behavior

- `U` updates all plugins, `u` updates only the selected plugin.
- Updated plugins are shown in a dedicated section with stronger visual emphasis and are auto-expanded with recent commit history when available.
- The top bar shows a compact indicator while an update or refresh is in progress.

## Layout

PackUI uses a single floating window with lazy inline details (similar to lazy.nvim).

- **Top**: grouped key hints with simple updating/refreshing indicator
- **Updated** (optional): plugins changed by the last update, with recent commit details auto-expanded
- **All Plugins**: full plugin list with `NAME STATUS VERSION` columns
- **`<CR>`** expands/collapses details inline; details are built on first expansion only
- **Adaptive width**: window width follows content instead of a fixed large percentage

Running tests:

```sh
make test
```

## Architecture

- `plugin/packui.lua` only defines the `:PackUI` command.
- `lua/packui/init.lua` wires source, actions, and UI together.
- `lua/packui/source/` is the data layer. It reads `vim.pack` or the lock file, models items into a stable shape, and caches async update counts.
- `lua/packui/ui/state.lua` owns UI state and selection by plugin name, not by screen line.
- `lua/packui/ui/render.lua` is the pure render layer. It turns state into lines, highlights, and plugin-row navigation targets.
- `lua/packui/ui/controller.lua` handles side effects: keymaps, refresh, update callbacks, window lifecycle, and async git history loading.
- `lua/packui/win.lua` contains low-level floating-window helpers only.

The important teaching point is that rendering no longer decides behavior. Behavior updates state, then the render layer derives the screen from state.

## Learning Path

If you are a Java developer learning Lua plugins, read the project in this order:

1. `plugin/packui.lua`: command entry point.
2. `lua/packui/init.lua`: dependency wiring.
3. `lua/packui/source/init.lua` and `lua/packui/source/model.lua`: how external/editor data becomes a plugin item model.
4. `lua/packui/ui/state.lua`: what the UI remembers.
5. `lua/packui/ui/render.lua`: how state becomes text and highlights.
6. `lua/packui/ui/controller.lua`: where side effects live.

If you already understand MVC or presenter-style UI code, the mapping is roughly:

- `source/*` = repository + mapper
- `ui/state.lua` = state model
- `ui/render.lua` = view model renderer
- `ui/controller.lua` = controller / coordinator

## Project structure

```text
plugin/packui.lua            command entry
lua/packui/init.lua          module wiring
lua/packui/actions.lua       update/delete/open actions
lua/packui/ui.lua            UI facade
lua/packui/ui/controller.lua stateful UI orchestration
lua/packui/ui/render.lua     pure rendering and detail text
lua/packui/ui/state.lua      UI state and selection rules
lua/packui/win.lua           window and buffer helpers
lua/packui/utils.lua         notifications and URL opening
lua/packui/source/init.lua   package listing API
lua/packui/source/model.lua  package normalization
lua/packui/source/cache.lua  async update-count cache
tests/packui_native_ui_spec.lua interaction scenarios
DESIGN.md                    architecture notes for maintenance
```
