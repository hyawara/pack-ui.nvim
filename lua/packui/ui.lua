local M = {}
local ui_win = require('packui.win')
local utils = require('packui.utils')

local COLUMN_FORMAT = '%-36s %-10s %s'
local NS = vim.api.nvim_create_namespace('packui.native')
local KEY_HINT = ' g: GitHub  U: Update all  u: Update  x: Delete  r: Refresh  <CR>: Details  q: Close '

local function header_text()
    return string.format(COLUMN_FORMAT, 'NAME', 'STATUS', 'VERSION')
end

local function row_text(item)
    local status = item.active and 'active' or 'inactive'
    return string.format(COLUMN_FORMAT, item.name or '', status, item.version or '-')
end

local function build_items(plugins)
    local items = {
        { header = true, text = header_text() },
    }
    for _, plugin in ipairs(plugins or {}) do
        plugin.text = row_text(plugin)
        items[#items + 1] = plugin
    end
    return items
end

local function current_plugin(state)
    local item = state.items[state.selected]
    if not item or item.header then
        utils.notify('PackUI: select a plugin first', vim.log.levels.WARN)
        return nil
    end
    return item
end

local function render_detail(state)
    local item = state.items[state.selected]
    local lines
    if item and not item.header and item.preview and item.preview.text then
        lines = vim.split(item.preview.text, '\n', { plain = true })
    else
        lines = {
            '# PackUI',
            '',
            'Select a plugin to view details.',
            '',
            '## Keys',
            '- `g`: open GitHub repository',
            '- `U`: update all plugins',
            '- `u`: update selected plugin',
            '- `x`: delete selected plugin',
            '- `r`: refresh list',
            '- `q`: close PackUI',
        }
    end
    ui_win.set_buf_lines(state.wins.detail_buf, lines)
end

local function render_footer(state)
    ui_win.set_buf_lines(state.wins.footer_buf, { KEY_HINT })
end

local function render_list(state)
    local lines = {}
    for _, item in ipairs(state.items) do
        lines[#lines + 1] = item.text or ''
    end
    if #state.items == 1 then
        lines[#lines + 1] = 'No plugins found'
    end

    ui_win.set_buf_lines(state.wins.list_buf, lines)
    vim.api.nvim_buf_clear_namespace(state.wins.list_buf, NS, 0, -1)
    vim.api.nvim_buf_add_highlight(state.wins.list_buf, NS, 'PackUIHeader', 0, 0, -1)
    if state.selected > 1 and state.selected <= #lines then
        vim.api.nvim_buf_add_highlight(state.wins.list_buf, NS, 'PackUISelected', state.selected - 1, 0, -1)
        if vim.api.nvim_win_is_valid(state.wins.list_win) then
            vim.api.nvim_win_set_cursor(state.wins.list_win, { state.selected, 0 })
        end
    end
end

local function render(state)
    render_list(state)
    render_detail(state)
    render_footer(state)
end

local function navigate(state, delta)
    if #state.items <= 1 then
        return
    end
    local next_index = state.selected + delta
    if next_index < 2 then
        next_index = #state.items
    elseif next_index > #state.items then
        next_index = 2
    end
    state.selected = next_index
    render(state)
end

local function refresh(state, refresh_opts)
    if state.refreshing then
        return
    end
    state.refreshing = true
    state.items = build_items(state.source.list_plugins())
    if #state.items >= 2 then
        state.selected = math.min(math.max(state.selected or 2, 2), #state.items)
    else
        state.selected = 1
    end
    render(state)

    local has_async_jobs = state.source.prime_update_counts(state.items, function()
        state.refreshing = false
        state.items = build_items(state.source.list_plugins())
        if #state.items >= 2 then
            state.selected = math.min(math.max(state.selected or 2, 2), #state.items)
        else
            state.selected = 1
        end
        if ui_win.is_open(state.wins) then
            render(state)
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

local function focus_detail(state)
    if state.wins.detail_win and vim.api.nvim_win_is_valid(state.wins.detail_win) then
        vim.api.nvim_set_current_win(state.wins.detail_win)
    end
end

local function map_keys(state)
    local buf = state.wins.list_buf
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
    map('g', function()
        local item = current_plugin(state)
        if item then
            state.actions.open_github(item)
        end
    end, 'Open GitHub repo')
    map('U', function()
        state.actions.update_all(function()
            state.source.invalidate_all_update_counts()
            refresh(state, { force_counts = true })
        end)
    end, 'Update all plugins')
    map('u', function()
        local item = current_plugin(state)
        if item then
            state.actions.update_one(item, function()
                state.source.invalidate_update_count(item.path)
                refresh(state, { force_counts = true })
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
        focus_detail(state)
    end, 'Focus details panel')

    vim.keymap.set('n', 'q', function()
        vim.api.nvim_set_current_win(state.wins.list_win)
    end, { buffer = state.wins.detail_buf, nowait = true, silent = true, desc = 'Return to plugin list' })
end

local function create_windows()
    ui_win.setup_highlights()
    local layout = ui_win.calc_layout()
    local wins = {
        list_buf = ui_win.create_scratch_buf(),
        detail_buf = ui_win.create_scratch_buf('markdown'),
        footer_buf = ui_win.create_scratch_buf(),
    }
    wins.list_win = ui_win.create_float(vim.tbl_extend('force', layout.list, { buf = wins.list_buf, enter = true, title = ' 📦 PackUI Plugins ', title_pos = 'left', cursorline = true }))
    wins.detail_win = ui_win.create_float(vim.tbl_extend('force', layout.detail, { buf = wins.detail_buf, enter = false, title = ' 󰦨 Plugin Details ', title_pos = 'left' }))
    wins.footer_win = ui_win.create_float(vim.tbl_extend('force', layout.footer, { buf = wins.footer_buf, enter = false, title = ' Shortcuts ', focusable = false, border = 'single' }))
    return wins
end

function M.open(opts)
    local state = {
        source = assert(opts.source, 'packui.ui.open requires source'),
        actions = assert(opts.actions, 'packui.ui.open requires actions'),
        wins = create_windows(),
        items = {},
        selected = 2,
        refreshing = false,
        closed = false,
    }

    state.close = function()
        close(state)
    end
    state.augroup = vim.api.nvim_create_augroup('PackUINative' .. tostring(state.wins.list_win), { clear = true })
    vim.api.nvim_create_autocmd('WinClosed', {
        group = state.augroup,
        pattern = tostring(state.wins.list_win),
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
