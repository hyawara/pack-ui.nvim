# pack-ui.nvim

A small `vim.pack` manager UI for Neovim 0.12+.

It uses a native Neovim floating-window UI and keeps the first render fast by reading package data with `vim.pack.get(nil, { info = false })`. Git update counts are collected asynchronously and cached until refresh or package mutations.

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
| `j` / `k` | Navigate plugin list |
| `g` | Open selected plugin GitHub repository |
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

## Project structure

```text
plugin/packui.lua            command entry
lua/packui/init.lua          module wiring
lua/packui/actions.lua       update/delete/open actions
lua/packui/ui.lua            native single-buffer UI
lua/packui/win.lua           window and buffer helpers
lua/packui/utils.lua         notifications and URL opening
lua/packui/source/init.lua   package listing API
lua/packui/source/cache.lua  async update-count cache
lua/packui/source/normalize.lua
lua/packui/source/preview.lua
```
