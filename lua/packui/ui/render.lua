local M = {}

M.LOADING_LINE = 'Loading...'

local NAME_WIDTH = 36
local LEFT_PAD = ' '
local KEY_HINT_LINES = {
    ' Open repo (o)  Update (u)  Update all (U)  Refresh (r)  Details (<CR>)  Delete (x)  Close (q) ',
}

local function pad_display(value, width)
    local str = tostring(value or '')
    local current = vim.api.nvim_strwidth(str)
    if current >= width then
        return str
    end
    return str .. string.rep(' ', width - current)
end

local function updated_row_text(item, widths)
    local version = item.version or '-'
    local parts = {
        name = pad_display(item.name or '', NAME_WIDTH),
        version = pad_display(version, widths.version),
    }
    return parts.name .. parts.version, parts
end

local function active_row_text(item, widths)
    local version = item.version or '-'
    local parts = {
        name = pad_display(item.name or '', NAME_WIDTH),
        version = pad_display(version, widths.version),
        commit = pad_display(item.latest_commit or '-', widths.commit),
    }
    return parts.name .. parts.version .. parts.commit, parts
end

local function updated_header_text(widths)
    return pad_display('NAME', NAME_WIDTH) .. pad_display('VERSION', widths.version)
end

local function active_header_text(widths)
    return pad_display('NAME', NAME_WIDTH) .. pad_display('VERSION', widths.version) .. pad_display('COMMIT', widths.commit)
end

local function inactive_header_text(widths)
    return pad_display('NAME', NAME_WIDTH) .. pad_display('VERSION', widths.version)
end

local function inactive_row_text(item, widths)
    local parts = {
        name = pad_display(item.name or '', NAME_WIDTH),
        version = pad_display(item.version or '-', widths.version),
    }
    return parts.name .. parts.version, parts
end

function M.status_text(state)
    if state.updating then
        return '⏳ Updating…'
    end
    if state.refreshing then
        return '🔄 Refreshing…'
    end
    return nil
end

local function display_width(value)
    if not value or value == '' then
        return 0
    end
    return vim.api.nvim_strwidth(value)
end

function M.compute_content_width(lines)
    local max_width = 56
    for _, line in ipairs(lines or {}) do
        local width = display_width(line)
        if width > max_width then
            max_width = width
        end
    end
    return max_width
end

local function apply_column_highlights(line_number, columns)
    local start_col = #LEFT_PAD
    local highlights = {}

    for _, column in ipairs(columns) do
        local end_col = start_col + #column.text
        highlights[#highlights + 1] = { group = column.group, col_start = start_col, col_end = end_col }
        start_col = end_col
    end

    return {
        line = line_number,
        highlights = highlights,
    }
end

local function apply_updated_row_highlights(line_number, parts)
    return apply_column_highlights(line_number, {
        { group = 'PackUIRowName', text = parts.name },
        { group = 'PackUIRowVersion', text = parts.version },
    })
end

local function apply_active_row_highlights(line_number, parts)
    return apply_column_highlights(line_number, {
        { group = 'PackUIRowName', text = parts.name },
        { group = 'PackUIRowVersion', text = parts.version },
        { group = 'PackUIRowCommit', text = parts.commit },
    })
end

local function apply_inactive_row_highlights(line_number, parts)
    return apply_column_highlights(line_number, {
        { group = 'PackUIRowName', text = parts.name },
        { group = 'PackUIRowVersion', text = parts.version },
    })
end

function M.build_detail_lines(item, is_updated)
    local lines = {}
    if is_updated then
        lines[#lines + 1] = '🕘 Recent commits:'
        lines[#lines + 1] = M.LOADING_LINE
        return lines
    end

    local status = item.active and '✅ active' or '🚫 inactive'
    local version = item.version or '-'
    local commit = item.short_rev or '-'

    lines[#lines + 1] = 'Status: ' .. status
    lines[#lines + 1] = 'Version: ' .. version
    lines[#lines + 1] = 'Commit: ' .. commit
    local update_status = item.has_update and '⬆️ available' or tostring(item.update_count or '-')
    lines[#lines + 1] = 'Updates: ' .. update_status
    lines[#lines + 1] = 'Repo: ' .. (item.repo or '-')
    lines[#lines + 1] = 'GitHub: ' .. (item.github_url or '-')
    lines[#lines + 1] = 'Path: ' .. (item.path ~= '' and item.path or '-')

    return lines
end

local function add_updated_row(snapshot, item, widths)
    local line_number = #snapshot.lines + 1
    local text, parts = updated_row_text(item, widths)

    snapshot.lines[line_number] = LEFT_PAD .. text
    snapshot.plugin_order[#snapshot.plugin_order + 1] = item.name
    snapshot.line_to_item[line_number] = item
    snapshot.highlight_map[line_number] = 'PackUIUpdatedRow'
    snapshot.row_highlights[#snapshot.row_highlights + 1] = apply_updated_row_highlights(line_number, parts)
end

local function add_active_row(snapshot, item, widths)
    local line_number = #snapshot.lines + 1
    local text, parts = active_row_text(item, widths)

    snapshot.lines[line_number] = LEFT_PAD .. text
    snapshot.plugin_order[#snapshot.plugin_order + 1] = item.name
    snapshot.line_to_item[line_number] = item
    snapshot.row_highlights[#snapshot.row_highlights + 1] = apply_active_row_highlights(line_number, parts)
end

local function add_inactive_row(snapshot, item, widths)
    local line_number = #snapshot.lines + 1
    local text, parts = inactive_row_text(item, widths)

    snapshot.lines[line_number] = LEFT_PAD .. text
    snapshot.plugin_order[#snapshot.plugin_order + 1] = item.name
    snapshot.line_to_item[line_number] = item
    snapshot.highlight_map[line_number] = 'PackUIInactiveRow'
    snapshot.row_highlights[#snapshot.row_highlights + 1] = apply_inactive_row_highlights(line_number, parts)
end

local function add_detail_lines(snapshot, detail_lines, highlight_group)
    for _, detail_line in ipairs(detail_lines or {}) do
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. '  ' .. detail_line
        snapshot.highlight_map[#snapshot.lines] = highlight_group
    end
end

function M.compute_selected_line(selected_name, selected_line, selectable_lines, line_to_item)
    local line_count = #selectable_lines
    if line_count == 0 then
        return nil
    end

    if selected_name then
        for _, line in ipairs(selectable_lines) do
            local item = line_to_item[line]
            if item and item.name == selected_name then
                return line
            end
        end
    end

    if type(selected_line) == 'number' then
        local first_line = selectable_lines[1]
        local last_line = selectable_lines[line_count]
        return math.max(first_line, math.min(last_line, selected_line))
    end

    return selectable_lines[1]
end

local function compute_widths(state)
    local widths = {
        version = display_width('VERSION'),
        commit = display_width('COMMIT'),
    }
    local function scan(items)
        for _, item in ipairs(items or {}) do
            widths.version = math.max(widths.version, display_width(item.version or '-'))
            widths.commit = math.max(widths.commit, display_width(item.latest_commit or '-'))
        end
    end
    scan(state.items)
    scan(state.updated_items)
    return widths
end

local function split_items(state)
    local active_items = {}
    local inactive_items = {}
    for _, item in ipairs(state.items or {}) do
        if not state.updated_names[item.name] then
            if item.active then
                active_items[#active_items + 1] = item
            else
                inactive_items[#inactive_items + 1] = item
            end
        end
    end
    return active_items, inactive_items
end

function M.build_snapshot(state)
    local widths = compute_widths(state)
    local active_items, inactive_items = split_items(state)
    local section_width = math.max(display_width(updated_header_text(widths)), display_width(inactive_header_text(widths)), display_width(active_header_text(widths)))
    local content_width = display_width(LEFT_PAD) + section_width
    local separator = string.rep('─', content_width - display_width(LEFT_PAD))

    local snapshot = {
        lines = {},
        selectable_lines = {},
        plugin_order = {},
        line_to_item = {},
        highlight_map = {},
        row_highlights = {},
    }

    for _, hint_line in ipairs(KEY_HINT_LINES) do
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. hint_line
        snapshot.highlight_map[#snapshot.lines] = 'PackUIKeyHint'
    end

    local status_line = M.status_text(state)
    if status_line then
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. status_line
        snapshot.highlight_map[#snapshot.lines] = 'PackUIUpdating'
    end

    snapshot.lines[#snapshot.lines + 1] = LEFT_PAD

    if #state.updated_items > 0 then
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. '📦 Updated Plugins'
        snapshot.highlight_map[#snapshot.lines] = 'PackUIUpdatedHeader'
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. updated_header_text(widths)
        snapshot.highlight_map[#snapshot.lines] = 'PackUIColumnHeader'

        for _, item in ipairs(state.updated_items) do
            add_updated_row(snapshot, item, widths)
            if state.expanded[item.name] then
                add_detail_lines(snapshot, state.detail_cache[item.name] and state.detail_cache[item.name].lines, 'PackUIUpdatedDetail')
            end
        end

        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. separator
        snapshot.highlight_map[#snapshot.lines] = 'PackUIUpdatedSeparator'
    end

    if #inactive_items > 0 then
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. '🚫 Inactive Plugins'
        snapshot.highlight_map[#snapshot.lines] = 'PackUIInactiveHeader'
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. inactive_header_text(widths)
        snapshot.highlight_map[#snapshot.lines] = 'PackUIColumnHeader'

        for _, item in ipairs(inactive_items) do
            add_inactive_row(snapshot, item, widths)
            if state.expanded[item.name] then
                add_detail_lines(snapshot, state.detail_cache[item.name] and state.detail_cache[item.name].lines, 'PackUIDetail')
            end
        end

        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD
        snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. separator
        snapshot.highlight_map[#snapshot.lines] = 'PackUIUpdatedSeparator'
    end

    snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. '🧩 Active Plugins'
    snapshot.highlight_map[#snapshot.lines] = 'PackUIAllPluginsHeader'
    snapshot.lines[#snapshot.lines + 1] = LEFT_PAD .. active_header_text(widths)
    snapshot.highlight_map[#snapshot.lines] = 'PackUIColumnHeader'

    for _, item in ipairs(active_items) do
        add_active_row(snapshot, item, widths)
        if state.expanded[item.name] then
            add_detail_lines(snapshot, state.detail_cache[item.name] and state.detail_cache[item.name].lines, 'PackUIDetail')
        end
    end

    for i = 1, #snapshot.lines do
        snapshot.selectable_lines[i] = i
    end
    snapshot.selected_line = M.compute_selected_line(state.selected_name, state.selected_line, snapshot.selectable_lines, snapshot.line_to_item)
    return snapshot
end

return M
