local M = {}

local NAME_WIDTH = 36
local STATUS_WIDTH = 14
local KEY_HINT_LINES = {
    ' Open repo (o)  Update (u)  Update all (U)  Refresh (r)  Details (<CR>)  Delete (x)  Close (q) ',
}

local function status_label(item)
    if not item.active then
        return '🚫 inactive'
    end
    if item.has_update then
        return '⬆️ update'
    end
    return '✅ active'
end

local function pad_display(value, width)
    local str = tostring(value or '')
    local current = vim.api.nvim_strwidth(str)
    if current >= width then
        return str
    end
    return str .. string.rep(' ', width - current)
end

local function row_parts(item)
    local status = status_label(item)
    return {
        name = pad_display(item.name or '', NAME_WIDTH),
        status = pad_display(status, STATUS_WIDTH),
        version = item.version or '-',
        raw_name = item.name or '',
        raw_status = status,
    }
end

local function row_text(item)
    local parts = row_parts(item)
    return parts.name .. parts.status .. parts.version, parts
end

local function header_text()
    return pad_display('NAME', NAME_WIDTH) .. pad_display('STATUS', STATUS_WIDTH) .. 'VERSION'
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

local function apply_row_highlights(line_number, item, parts)
    local name_end = #parts.raw_name
    local status_start = #parts.name
    -- 高亮使用字节偏移。刻意只高亮状态文本，不包含用于对齐 VERSION 列的填补空格。
    local status_text_end = status_start + #parts.raw_status
    local version_start = #parts.name + #parts.status
    local version_end = version_start + #(item.version or '-')

    return {
        line = line_number,
        highlights = {
            { group = 'PackUIRowName', col_start = 0, col_end = name_end },
            {
                group = item.active and 'PackUIRowActive' or 'PackUIRowInactive',
                col_start = status_start,
                col_end = status_text_end,
            },
            { group = 'PackUIRowVersion', col_start = version_start, col_end = version_end },
        },
    }
end

function M.build_detail_lines(item, is_updated)
    local lines = {}
    local status = item.active and '✅ active' or '🚫 inactive'
    local version = item.version or '-'
    local commit = item.short_rev or '-'

    lines[#lines + 1] = 'Status: ' .. status
    lines[#lines + 1] = 'Version: ' .. version
    lines[#lines + 1] = 'Commit: ' .. commit

    if is_updated then
        lines[#lines + 1] = 'Repo: ' .. (item.repo or '-')
        lines[#lines + 1] = ''
        lines[#lines + 1] = '🕘 Recent commits:'
        lines[#lines + 1] = 'Loading...'
    else
        local update_status = item.has_update and '⬆️ available' or tostring(item.update_count or '-')
        lines[#lines + 1] = 'Updates: ' .. update_status
        lines[#lines + 1] = 'Repo: ' .. (item.repo or '-')
        lines[#lines + 1] = 'GitHub: ' .. (item.github_url or '-')
        lines[#lines + 1] = 'Path: ' .. (item.path ~= '' and item.path or '-')
    end

    return lines
end

local function add_plugin_row(snapshot, item, row_group)
    local line_number = #snapshot.lines + 1
    local text, parts = row_text(item)

    snapshot.lines[line_number] = text
    snapshot.selectable_lines[#snapshot.selectable_lines + 1] = line_number
    snapshot.plugin_order[#snapshot.plugin_order + 1] = item.name
    snapshot.line_to_item[line_number] = item
    if row_group then
        snapshot.highlight_map[line_number] = row_group
    end
    snapshot.row_highlights[#snapshot.row_highlights + 1] = apply_row_highlights(line_number, item, parts)
end

local function add_detail_lines(snapshot, detail_lines, highlight_group)
    for _, detail_line in ipairs(detail_lines or {}) do
        snapshot.lines[#snapshot.lines + 1] = '  ' .. detail_line
        snapshot.highlight_map[#snapshot.lines] = highlight_group
    end
end

function M.compute_selected_line(selected_name, selectable_lines, line_to_item)
    if selected_name then
        for _, line in ipairs(selectable_lines) do
            local item = line_to_item[line]
            if item and item.name == selected_name then
                return line
            end
        end
    end

    return selectable_lines[1]
end

function M.build_snapshot(state)
    local snapshot = {
        lines = {},
        selectable_lines = {},
        plugin_order = {},
        line_to_item = {},
        highlight_map = {},
        row_highlights = {},
        pinned_line_count = 0,
    }

    for _, hint_line in ipairs(KEY_HINT_LINES) do
        snapshot.lines[#snapshot.lines + 1] = hint_line
        snapshot.highlight_map[#snapshot.lines] = 'PackUIKeyHint'
    end

    local status_line = M.status_text(state)
    snapshot.pinned_line_count = #KEY_HINT_LINES + (status_line and 1 or 0)
    if status_line then
        snapshot.lines[#snapshot.lines + 1] = status_line
        snapshot.highlight_map[#snapshot.lines] = 'PackUIUpdating'
    end

    snapshot.lines[#snapshot.lines + 1] = ''

    if #state.updated_items > 0 then
        snapshot.lines[#snapshot.lines + 1] = '📦 Updated'
        snapshot.highlight_map[#snapshot.lines] = 'PackUIUpdatedHeader'
        snapshot.lines[#snapshot.lines + 1] = header_text()
        snapshot.highlight_map[#snapshot.lines] = 'PackUIColumnHeader'

        for _, item in ipairs(state.updated_items) do
            add_plugin_row(snapshot, item, 'PackUIUpdatedRow')
            if state.expanded[item.name] then
                add_detail_lines(snapshot, state.detail_cache[item.name] and state.detail_cache[item.name].lines, 'PackUIUpdatedDetail')
            end
        end

        snapshot.lines[#snapshot.lines + 1] = ''
    end

    snapshot.lines[#snapshot.lines + 1] = '🧩 All Plugins'
    snapshot.highlight_map[#snapshot.lines] = 'PackUIAllPluginsHeader'
    snapshot.lines[#snapshot.lines + 1] = header_text()
    snapshot.highlight_map[#snapshot.lines] = 'PackUIColumnHeader'

    for _, item in ipairs(state.items) do
        if not state.updated_names[item.name] then
            add_plugin_row(snapshot, item)
            if state.expanded[item.name] then
                add_detail_lines(snapshot, state.detail_cache[item.name] and state.detail_cache[item.name].lines, 'PackUIDetail')
            end
        end
    end

    snapshot.selected_line = M.compute_selected_line(state.selected_name, snapshot.selectable_lines, snapshot.line_to_item)
    return snapshot
end

return M
