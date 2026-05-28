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
| `g` | Open selected plugin GitHub repository |
| `U` | Update all plugins |
| `u` | Update selected plugin |
| `x` | Delete selected plugin |
| `r` / `<C-r>` | Refresh list |
| `<CR>` | Focus details panel |
| `q` | Close |

## Layout

```text
plugin/packui.lua            command entry
lua/packui/init.lua          module wiring
lua/packui/actions.lua       update/delete/open actions
lua/packui/ui.lua            native floating-window UI
lua/packui/win.lua           window and buffer helpers
lua/packui/utils.lua         notifications and URL opening
lua/packui/source/init.lua   package listing API
lua/packui/source/cache.lua  async update-count cache
lua/packui/source/normalize.lua
lua/packui/source/preview.lua
```
