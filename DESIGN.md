# Design Notes

## Goals

This plugin is intentionally small, but it still separates responsibilities so that maintenance does not depend on remembering every Neovim API call at once.

The design goals are:

1. Keep the command entry trivial.
2. Keep plugin data plain.
3. Keep rendering derivable from state.
4. Keep side effects in one place.

## Data Flow

The runtime flow is:

1. `:PackUI` calls `require('packui').open()`.
2. `lua/packui/init.lua` passes `source`, `actions`, and `ui` dependencies together.
3. `ui/controller.lua` creates the window and initial state.
4. `source/init.lua` returns plugin items from `vim.pack.get()` or the lock file fallback.
5. `ui/state.lua` stores those items and tracks the selected plugin by name.
6. `ui/render.lua` converts state into buffer lines and highlight metadata (pure, no state mutation).
7. `ui/controller.lua` syncs the render output back into state via `sync_render_state`, then applies highlights and cursor to the window.

The important rule is: selection is stored as `selected_name`, not `selected_line`.

That makes refreshes safer because line numbers can change, but plugin identity does not.

## Module Boundaries

### `plugin/packui.lua`

Only defines the user command. No state, no logic.

### `lua/packui/init.lua`

Acts as the composition root. If you want to replace a data source or action implementation later, start here.

### `lua/packui/source/*`

The source layer answers one question: "what is a plugin item?"

- `init.lua` chooses where data comes from.
- `model.lua` converts raw `vim.pack` or lock-file data into a stable item shape.
- `cache.lua` owns async update-count caching.

Nothing in this layer should know about windows, keymaps, or cursor positions.

### `lua/packui/ui/state.lua`

This file is the easiest place for a beginner to start reading UI behavior.

It answers:

- What fields exist in state?
- How is the current plugin selected?
- How are updated items rebuilt?
- Which expanded detail blocks should survive refresh?

### `lua/packui/ui/render.lua`

This is the pure rendering layer. It has zero imports from `state.lua` and performs no state mutations.

Given a state table, it returns:

- lines
- row highlight metadata
- line-to-plugin mapping
- plugin navigation order
- selected line number (computed via `compute_selected_line`, which does NOT modify state)

When behavior looks wrong on screen, inspect this file first.

### `lua/packui/ui/controller.lua`

This file owns side effects only:

- keymaps
- refresh orchestration
- update callbacks
- git history loading
- window lifecycle

If something touches `vim.system`, `vim.schedule`, or key bindings, it belongs here.

## Maintenance Rules

If you want to keep the plugin teachable, follow these rules:

1. Do not put new business logic directly into `plugin/packui.lua`.
2. Do not put Neovim side effects into `source/*`.
3. Do not store render-only text on plugin items.
4. Prefer adding a pure helper in `ui/render.lua` before adding another state mutation.
5. If a bug is about selection or refresh, fix the state model before patching the renderer.

## Suggested Next Improvements

These are intentionally left as future work, not bundled into the refactor:

1. Add unit tests for `source/model.lua` URL normalization.
2. Add unit tests for `ui/render.lua` snapshot output.
3. Add a second integration test file dedicated to update/refresh race scenarios.
