local M = {}
local ui_win = require('packui.win')
local utils = require('packui.utils')

local NS = vim.api.nvim_create_namespace('packui.native')
local NAME_WIDTH = 36
local STATUS_WIDTH = 14
local KEY_HINT_LINES = {
    ' Update (u)  Update all (U)  Refresh (R)  Details (<CR>)  Delete (X)  Close (Q) ',
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

local function row_text(item)
    local name = pad_display(item.name or '', NAME_WIDTH)
    local status = pad_display(status_label(item), STATUS_WIDTH)
    local version = item.version or '-'
    return name .. status .. version
end

local function header_text()
    return pad_display('NAME', NAME_WIDTH) .. pad_display('STATUS', STATUS_WIDTH) .. 'VERSION'
end

local function status_text(state)
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

local function compute_content_width(lines)
    local max_width = 56
    for _, line in ipairs(lines or {}) do
        local width = display_width(line)
        if width > max_width then
            max_width = width
        end
    end
    return max_width
end

local function apply_row_highlights(line_number, item)
    local name = item.name or ''
    local status = status_label(item)
    local version = item.version or '-'
    local name_end = #name
    local status_start = NAME_WIDTH
    local status_end = status_start + #status
    local version_start = NAME_WIDTH + STATUS_WIDTH
    local version_end = version_start + #version
    return {
        line = line_number,
        highlights = {
            { group = 'PackUIRowName', col_start = 0, col_end = name_end },
            {
                group = item.active and 'PackUIRowActive' or 'PackUIRowInactive',
                col_start = status_start,
                col_end = status_end,
            },
            { group = 'PackUIRowVersion', col_start = version_start, col_end = version_end },
        },
    }
end

local function redraw_now()
    pcall(vim.cmd.redraw)
end

local function build_items(plugins)
    local items = {}
    for _, plugin in ipairs(plugins or {}) do
        plugin.text = row_text(plugin)
        items[#items + 1] = plugin
    end
    return items
end

local function current_plugin(state)
    local item = state.line_to_item[state.selected_line]
    if item then
        return item
    end
    for i = state.selected_line - 1, 1, -1 do
        if state.line_to_item[i] then
            return state.line_to_item[i]
        end
    end
    utils.notify('PackUI: select a plugin first', vim.log.levels.WARN)
    return nil
end

local function build_detail_lines(item, is_updated)
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

local function fetch_commits(item, state)
    if not item.path or item.path == '' then
        return
    end
    if vim.fn.isdirectory(item.path) ~= 1 or vim.fn.isdirectory(item.path .. '/.git') ~= 1 then
        return
    end

    vim.system({ 'git', 'log', '--oneline', '-5' }, {
        cwd = item.path,
        text = true,
    }, function(res)
        vim.schedule(function()
            if state.closed or not ui_win.is_open(state.wins) then
                return
            end

            local cache = state.detail_cache[item.name]
            if not cache then
                return
            end

            local new_lines = {}
            for _, line in ipairs(cache.lines) do
                if line ~= 'Loading...' then
                    new_lines[#new_lines + 1] = line
                end
            end

            if res and res.code == 0 and res.stdout then
                local commit_lines = vim.split(res.stdout:gsub('%s+$', ''), '\n', { plain = true })
                for _, commit in ipairs(commit_lines) do
                    if commit ~= '' then
                        new_lines[#new_lines + 1] = '  ' .. commit
                    end
                end
            else
                new_lines[#new_lines + 1] = '  (no commits available)'
            end

            cache.lines = new_lines
            cache.loading = false

            if ui_win.is_open(state.wins) then
                M._render(state)
            end
        end)
    end)
end

local function toggle_detail(state)
    local item = current_plugin(state)
    if not item then
        return
    end

    if state.expanded[item.name] then
        state.expanded[item.name] = nil
    else
        if not state.detail_cache[item.name] then
            local is_updated = state.updated_names[item.name] == true
            state.detail_cache[item.name] = {
                lines = build_detail_lines(item, is_updated),
                loading = is_updated,
            }
            if is_updated then
                fetch_commits(item, state)
            end
        end
        state.expanded[item.name] = true
    end

    M._render(state)
end

function M._render(state)
    local lines = {}
    local selectable_lines = {}
    local line_to_item = {}
    local highlight_map = {}
    local row_highlights = {}

    for _, hint_line in ipairs(KEY_HINT_LINES) do
        lines[#lines + 1] = hint_line
        highlight_map[#lines] = 'PackUIKeyHint'
        selectable_lines[#selectable_lines + 1] = #lines
    end

    local status_line = status_text(state)
    if status_line then
        lines[#lines + 1] = status_line
        highlight_map[#lines] = 'PackUIUpdating'
        selectable_lines[#selectable_lines + 1] = #lines
    end

    lines[#lines + 1] = ''

    -- Updated section
    if #state.updated_items > 0 then
        lines[#lines + 1] = '📦 Updated'
        highlight_map[#lines] = 'PackUIUpdatedHeader'
        selectable_lines[#selectable_lines + 1] = #lines
        lines[#lines + 1] = header_text()
        highlight_map[#lines] = 'PackUIColumnHeader'
        selectable_lines[#selectable_lines + 1] = #lines
        for _, item in ipairs(state.updated_items) do
            local idx = #lines + 1
            lines[idx] = item.text
            selectable_lines[#selectable_lines + 1] = idx
            line_to_item[idx] = item
            highlight_map[idx] = 'PackUIUpdatedRow'
            row_highlights[#row_highlights + 1] = apply_row_highlights(idx, item)

            if state.expanded[item.name] then
                local cache = state.detail_cache[item.name]
                if cache then
                    for _, dline in ipairs(cache.lines) do
                        lines[#lines + 1] = '  ' .. dline
                        highlight_map[#lines] = 'PackUIUpdatedDetail'
                        selectable_lines[#selectable_lines + 1] = #lines
                    end
                end
            end
        end
        lines[#lines + 1] = ''
    end

    -- All Plugins section
    lines[#lines + 1] = '🧩 All Plugins'
    highlight_map[#lines] = 'PackUIAllPluginsHeader'
    selectable_lines[#selectable_lines + 1] = #lines
    lines[#lines + 1] = header_text()
    highlight_map[#lines] = 'PackUIColumnHeader'
    selectable_lines[#selectable_lines + 1] = #lines
    for _, item in ipairs(state.items) do
        if not state.updated_names[item.name] then
            local idx = #lines + 1
            lines[idx] = item.text
            selectable_lines[#selectable_lines + 1] = idx
            line_to_item[idx] = item
            row_highlights[#row_highlights + 1] = apply_row_highlights(idx, item)

            if state.expanded[item.name] then
                local cache = state.detail_cache[item.name]
                if cache then
                    for _, dline in ipairs(cache.lines) do
                        lines[#lines + 1] = '  ' .. dline
                        highlight_map[#lines] = 'PackUIDetail'
                        selectable_lines[#selectable_lines + 1] = #lines
                    end
                end
            end
        end
    end

    -- Set buffer lines
    if state.closed or not ui_win.is_open(state.wins) then
        return
    end

    ui_win.set_buf_lines(state.wins.main_buf, lines)
    ui_win.resize_win_to_content(state.wins.main_win, compute_content_width(lines))

    state.selectable_lines = selectable_lines
    state.line_to_item = line_to_item

    -- Validate selected_line
    if #selectable_lines > 0 then
        local found = false
        for _, ln in ipairs(selectable_lines) do
            if ln == state.selected_line then
                found = true
                break
            end
        end
        if not found then
            for _, ln in ipairs(selectable_lines) do
                if line_to_item[ln] then
                    state.selected_line = ln
                    found = true
                    break
                end
            end
            if not found then
                state.selected_line = selectable_lines[1]
            end
        end
    else
        state.selected_line = nil
    end

    -- Apply highlights
    vim.api.nvim_buf_clear_namespace(state.wins.main_buf, NS, 0, -1)
    for line_num, hl_group in pairs(highlight_map) do
        vim.api.nvim_buf_add_highlight(state.wins.main_buf, NS, hl_group, line_num - 1, 0, -1)
    end
    for _, entry in ipairs(row_highlights) do
        for _, hl in ipairs(entry.highlights) do
            vim.api.nvim_buf_add_highlight(state.wins.main_buf, NS, hl.group, entry.line - 1, hl.col_start, hl.col_end)
        end
    end

    -- Highlight selected row
    if state.selected_line and state.selected_line <= #lines then
        vim.api.nvim_buf_add_highlight(state.wins.main_buf, NS, 'PackUISelected', state.selected_line - 1, 0, -1)
    end

    -- Set cursor
    if state.selected_line and vim.api.nvim_win_is_valid(state.wins.main_win) then
        vim.api.nvim_win_set_cursor(state.wins.main_win, { state.selected_line, 0 })
        local win_height = vim.api.nvim_win_get_height(state.wins.main_win)
        local visible_top = math.max(0, state.selected_line - win_height + 1)
        local hint_end = #KEY_HINT_LINES + (status_text(state) and 1 or 0)
        if visible_top < hint_end then
            pcall(vim.api.nvim_win_call, state.wins.main_win, function()
                vim.cmd('normal! zt')
            end)
            vim.api.nvim_win_set_cursor(state.wins.main_win, { state.selected_line, 0 })
        end
    end
end

local function navigate(state, delta)
    if #state.selectable_lines == 0 or not state.selected_line then
        return
    end

    local current_idx = nil
    for i, ln in ipairs(state.selectable_lines) do
        if ln == state.selected_line then
            current_idx = i
            break
        end
    end

    if not current_idx then
        state.selected_line = state.selectable_lines[1]
        M._render(state)
        return
    end

    local next_idx = current_idx + delta
    if next_idx < 1 then
        next_idx = 1
    elseif next_idx > #state.selectable_lines then
        next_idx = #state.selectable_lines
    end

    if next_idx == current_idx then
        return
    end

    state.selected_line = state.selectable_lines[next_idx]
    M._render(state)
end

local function refresh(state, refresh_opts)
    if state.refreshing then
        return
    end
    if state.closed or not ui_win.is_open(state.wins) then
        return
    end
    state.refreshing = true

    local old_expanded = state.expanded or {}
    local old_detail_cache = state.detail_cache or {}
    local old_updated_names = state.updated_names or {}

    state.items = build_items(state.source.list_plugins())

    -- Preserve expanded and detail cache across refresh
    state.expanded = {}
    state.detail_cache = {}
    for _, item in ipairs(state.items) do
        if old_expanded[item.name] then
            state.expanded[item.name] = true
        end
        if old_detail_cache[item.name] then
            state.detail_cache[item.name] = old_detail_cache[item.name]
        end
    end

    -- Rebuild updated items from current items
    state.updated_names = old_updated_names
    state.updated_items = {}
    for _, item in ipairs(state.items) do
        if state.updated_names[item.name] then
            state.updated_items[#state.updated_items + 1] = item
        end
    end

    M._render(state)

    local has_async_jobs = state.source.prime_update_counts(state.items, function()
        state.refreshing = false
        state.items = build_items(state.source.list_plugins())

        -- Re-preserve expanded/cache after async update
        state.expanded = {}
        state.detail_cache = {}
        for _, item in ipairs(state.items) do
            if old_expanded[item.name] then
                state.expanded[item.name] = true
            end
            if old_detail_cache[item.name] then
                state.detail_cache[item.name] = old_detail_cache[item.name]
            end
        end

        state.updated_items = {}
        for _, item in ipairs(state.items) do
            if state.updated_names[item.name] then
                state.updated_items[#state.updated_items + 1] = item
            end
        end

        if ui_win.is_open(state.wins) then
            M._render(state)
        end
    end, { force = refresh_opts and refresh_opts.force_counts == true })

    if not has_async_jobs then
        state.refreshing = false
    end
end

local function close(state)
    if state.closed then
        return
    end
    state.closed = true
    if state.augroup then
        pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    end
    ui_win.close_all(state.wins)
end

local function expand_updated_items(state, names)
    if not names or #names == 0 then
        return
    end
    local by_name = {}
    for _, item in ipairs(state.items) do
        by_name[item.name] = item
    end
    for _, name in ipairs(names) do
        if not state.expanded[name] then
            state.expanded[name] = true
        end
        if not state.detail_cache[name] then
            local item = by_name[name]
            if item then
                state.detail_cache[name] = {
                    lines = build_detail_lines(item, true),
                    loading = true,
                }
                fetch_commits(item, state)
            end
        end
    end
end

local function map_keys(state)
    local buf = state.wins.main_buf
    local function map(key, fn, desc)
        vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end

    map('q', function()
        close(state)
    end, 'Close PackUI')
    map('j', function()
        navigate(state, 1)
    end, 'Next plugin')
    map('k', function()
        navigate(state, -1)
    end, 'Previous plugin')
    map('r', function()
        refresh(state, { force_counts = true })
    end, 'Refresh list')
    map('U', function()
        state.updating = true
        M._render(state)
        redraw_now()

        vim.schedule(function()
            state.actions.update_all({
                on_done = function(updated_names)
                    if state.closed or not ui_win.is_open(state.wins) then
                        return
                    end
                    state.updating = false
                    state.updated_names = {}
                    for _, name in ipairs(updated_names) do
                        state.updated_names[name] = true
                    end
                    state.source.invalidate_all_update_counts()
                    refresh(state, { force_counts = true })
                    expand_updated_items(state, updated_names)
                    if ui_win.is_open(state.wins) then
                        M._render(state)
                    end
                end,
                on_error = function()
                    if state.closed then
                        return
                    end
                    state.updating = false
                    if ui_win.is_open(state.wins) then
                        M._render(state)
                    end
                end,
            })
        end)
    end, 'Update all plugins')
    map('u', function()
        local item = current_plugin(state)
        if item then
            state.updating = true
            M._render(state)
            redraw_now()

            vim.schedule(function()
                state.actions.update_one(item, {
                    on_done = function(updated_names)
                        if state.closed or not ui_win.is_open(state.wins) then
                            return
                        end
                        state.updating = false
                        for _, name in ipairs(updated_names) do
                            state.updated_names[name] = true
                        end
                        state.source.invalidate_update_count(item.path)
                        refresh(state, { force_counts = true })
                        expand_updated_items(state, updated_names)
                        if ui_win.is_open(state.wins) then
                            M._render(state)
                        end
                    end,
                    on_error = function()
                        if state.closed then
                            return
                        end
                        state.updating = false
                        if ui_win.is_open(state.wins) then
                            M._render(state)
                        end
                    end,
                })
            end)
        end
    end, 'Update selected plugin')
    map('x', function()
        local item = current_plugin(state)
        if item then
            state.actions.delete_one(item, function()
                state.source.invalidate_update_count(item.path)
                refresh(state, { force_counts = true })
            end)
        end
    end, 'Delete selected plugin')
    map('<CR>', function()
        toggle_detail(state)
    end, 'Toggle details')
end

local function create_windows()
    ui_win.setup_highlights()
    local layout = ui_win.calc_layout()
    local wins = {
        main_buf = ui_win.create_scratch_buf(),
    }
    wins.main_win = ui_win.create_float(vim.tbl_extend('force', layout.main, {
        buf = wins.main_buf,
        enter = true,
    }))
    vim.api.nvim_set_option_value('scrolloff', 3, { win = wins.main_win })
    return wins
end

function M.open(opts)
    local state = {
        source = assert(opts.source, 'packui.ui.open requires source'),
        actions = assert(opts.actions, 'packui.ui.open requires actions'),
        wins = create_windows(),
        items = {},
        selected_line = nil,
        selectable_lines = {},
        line_to_item = {},
        expanded = {},
        detail_cache = {},
        updated_items = {},
        updated_names = {},
        updating = false,
        refreshing = false,
        closed = false,
    }

    state.close = function()
        close(state)
    end
    state.augroup = vim.api.nvim_create_augroup('PackUINative' .. tostring(state.wins.main_win), { clear = true })
    vim.api.nvim_create_autocmd('WinClosed', {
        group = state.augroup,
        pattern = tostring(state.wins.main_win),
        callback = function()
            vim.schedule(function()
                close(state)
            end)
        end,
        once = true,
    })
    map_keys(state)
    refresh(state)
    return state
end

return M
