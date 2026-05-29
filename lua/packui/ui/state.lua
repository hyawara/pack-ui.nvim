local M = {}

local function index_items(items)
    local item_by_name = {}
    for _, item in ipairs(items or {}) do
        item_by_name[item.name] = item
    end
    return item_by_name
end

function M.create(opts)
    return {
        source = assert(opts.source, 'packui.ui.open requires source'),
        actions = assert(opts.actions, 'packui.ui.open requires actions'),
        wins = assert(opts.wins, 'packui.ui.open requires wins'),
        items = {},
        item_by_name = {},
        selected_name = nil,
        selected_line = nil,
        selectable_lines = {},
        plugin_order = {},
        line_to_item = {},
        expanded = {},
        detail_cache = {},
        updated_items = {},
        updated_names = {},
        updating = false,
        refreshing = false,
        closed = false,
    }
end

function M.current_plugin(state)
    if not state.selected_name then
        return nil
    end
    return state.item_by_name[state.selected_name]
end

function M.set_items(state, items)
    state.items = items or {}
    state.item_by_name = index_items(state.items)

    if state.selected_name and not state.item_by_name[state.selected_name] then
        state.selected_name = nil
    end

    if not state.selected_name and state.items[1] then
        state.selected_name = state.items[1].name
    end

    M.rebuild_updated_items(state)
end

function M.rebuild_updated_items(state)
    local updated_items = {}
    for _, item in ipairs(state.items) do
        if state.updated_names[item.name] then
            updated_items[#updated_items + 1] = item
        end
    end
    state.updated_items = updated_items
end

function M.restore_details(state, expanded_by_name, detail_cache_by_name)
    state.expanded = {}
    state.detail_cache = {}

    local expanded = expanded_by_name or {}
    local detail_cache = detail_cache_by_name or {}

    for _, item in ipairs(state.items) do
        if expanded[item.name] then
            state.expanded[item.name] = true
        end
        if detail_cache[item.name] then
            state.detail_cache[item.name] = detail_cache[item.name]
        end
    end
end

function M.set_updated_names(state, names, reset)
    if reset then
        state.updated_names = {}
    end

    for _, name in ipairs(names or {}) do
        state.updated_names[name] = true
    end

    M.rebuild_updated_items(state)
end

function M.sync_render_state(state, snapshot)
    state.selectable_lines = snapshot.selectable_lines
    state.plugin_order = snapshot.plugin_order
    state.line_to_item = snapshot.line_to_item
    state.selected_line = snapshot.selected_line

    if state.selected_line then
        local item = state.line_to_item[state.selected_line]
        state.selected_name = item and item.name or nil
    else
        state.selected_name = nil
    end
end

function M.move_selection(state, delta)
    if #state.plugin_order == 0 then
        return false
    end

    local current_index = 1
    if state.selected_name then
        for index, name in ipairs(state.plugin_order) do
            if name == state.selected_name then
                current_index = index
                break
            end
        end
    end

    local next_index = math.max(1, math.min(#state.plugin_order, current_index + delta))
    if next_index == current_index then
        return false
    end

    state.selected_name = state.plugin_order[next_index]
    return true
end

return M
