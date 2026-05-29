local render = require('packui.ui.render')
local state_model = require('packui.ui.state')
local ui_win = require('packui.win')
local utils = require('packui.utils')

local M = {}

local NS = vim.api.nvim_create_namespace('packui.native')

local function redraw_now()
    pcall(vim.cmd.redraw)
end

local function preserve_snapshot(state)
    return {
        expanded = vim.deepcopy(state.expanded),
        detail_cache = vim.deepcopy(state.detail_cache),
    }
end

local function load_items(state, preserved)
    state_model.set_items(state, state.source.list_plugins())
    state_model.restore_details(state, preserved and preserved.expanded, preserved and preserved.detail_cache)
end

local function apply_highlights(buf, highlight_map, row_highlights)
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

    for line_number, group in pairs(highlight_map) do
        vim.api.nvim_buf_add_highlight(buf, NS, group, line_number - 1, 0, -1)
    end

    for _, entry in ipairs(row_highlights) do
        for _, highlight in ipairs(entry.highlights) do
            vim.api.nvim_buf_add_highlight(buf, NS, highlight.group, entry.line - 1, highlight.col_start, highlight.col_end)
        end
    end
end

local function restore_cursor(state, snapshot)
    if not state.selected_line or state.selected_line > #snapshot.lines then
        return
    end
    if not vim.api.nvim_win_is_valid(state.wins.main_win) then
        return
    end

    vim.api.nvim_buf_add_highlight(state.wins.main_buf, NS, 'PackUISelected', state.selected_line - 1, 0, -1)
    vim.api.nvim_win_set_cursor(state.wins.main_win, { state.selected_line, 0 })

    local win_height = vim.api.nvim_win_get_height(state.wins.main_win)
    local visible_top = math.max(0, state.selected_line - win_height + 1)
    if visible_top < snapshot.pinned_line_count then
        pcall(vim.api.nvim_win_call, state.wins.main_win, function()
            vim.cmd('normal! zt')
        end)
        vim.api.nvim_win_set_cursor(state.wins.main_win, { state.selected_line, 0 })
    end
end

function M.render(state)
    if state.closed or not ui_win.is_open(state.wins) then
        return
    end

    local snapshot = render.build_snapshot(state)
    ui_win.set_buf_lines(state.wins.main_buf, snapshot.lines)
    ui_win.resize_win_to_content(state.wins.main_win, render.compute_content_width(snapshot.lines))
    state_model.sync_render_state(state, snapshot)
    apply_highlights(state.wins.main_buf, snapshot.highlight_map, snapshot.row_highlights)
    restore_cursor(state, snapshot)
end

local function current_plugin(state)
    local item = state_model.current_plugin(state)
    if item then
        return item
    end
    utils.notify('PackUI: select a plugin first', vim.log.levels.WARN)
    return nil
end

local function commit_lines_without_loading(lines)
    local new_lines = {}
    for _, line in ipairs(lines or {}) do
        if line ~= 'Loading...' then
            new_lines[#new_lines + 1] = line
        end
    end
    return new_lines
end

local function finalize_commit_preview(state, item, commits)
    local cache = state.detail_cache[item.name]
    if not cache then
        return
    end

    local lines = commit_lines_without_loading(cache.lines)
    if #commits == 0 then
        lines[#lines + 1] = '  (no commits available)'
    else
        for _, commit in ipairs(commits) do
            lines[#lines + 1] = '  ' .. commit
        end
    end

    cache.lines = lines
    cache.loading = false

    if ui_win.is_open(state.wins) then
        M.render(state)
    end
end

local function fetch_commits(item, state)
    local function no_commits_available()
        finalize_commit_preview(state, item, {})
    end

    if not item.path or item.path == '' then
        no_commits_available()
        return
    end

    if vim.fn.isdirectory(item.path) ~= 1 or vim.fn.isdirectory(item.path .. '/.git') ~= 1 then
        no_commits_available()
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

            if not state.detail_cache[item.name] then
                return
            end

            if res and res.code == 0 and res.stdout then
                local commits = {}
                for _, commit in ipairs(vim.split(res.stdout:gsub('%s+$', ''), '\n', { plain = true })) do
                    if commit ~= '' then
                        commits[#commits + 1] = commit
                    end
                end
                finalize_commit_preview(state, item, commits)
                return
            end

            no_commits_available()
        end)
    end)
end

local function ensure_detail_cache(state, item, is_updated)
    if state.detail_cache[item.name] then
        return
    end

    state.detail_cache[item.name] = {
        lines = render.build_detail_lines(item, is_updated),
        loading = is_updated,
    }

    if is_updated then
        fetch_commits(item, state)
    end
end

local function toggle_detail(state)
    local item = current_plugin(state)
    if not item then
        return
    end

    if state.expanded[item.name] then
        state.expanded[item.name] = nil
    else
        ensure_detail_cache(state, item, state.updated_names[item.name] == true)
        state.expanded[item.name] = true
    end

    M.render(state)
end

local function refresh(state, refresh_opts)
    if state.refreshing then
        return
    end
    if state.closed or not ui_win.is_open(state.wins) then
        return
    end

    state.refreshing = true
    load_items(state, preserve_snapshot(state))
    M.render(state)

    local has_async_jobs = state.source.prime_update_counts(state.items, function()
        state.refreshing = false
        load_items(state, preserve_snapshot(state))

        if ui_win.is_open(state.wins) then
            M.render(state)
        end
    end, { force = refresh_opts and refresh_opts.force_counts == true })

    if not has_async_jobs then
        state.refreshing = false
        M.render(state)
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

    for _, name in ipairs(names) do
        local item = state.item_by_name[name]
        if item then
            state.expanded[name] = true
            ensure_detail_cache(state, item, true)
        end
    end
end

local function navigate(state, delta)
    if state_model.move_selection(state, delta) then
        M.render(state)
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
    map('g', function()
        local item = current_plugin(state)
        if item then
            state.actions.open_github(item)
        end
    end, 'Open plugin repository')
    map('r', function()
        refresh(state, { force_counts = true })
    end, 'Refresh list')
    map('U', function()
        state.updating = true
        M.render(state)
        redraw_now()

        vim.schedule(function()
            state.actions.update_all({
                on_done = function(updated_names)
                    if state.closed or not ui_win.is_open(state.wins) then
                        return
                    end

                    state.updating = false
                    state_model.set_updated_names(state, updated_names, true)
                    state.source.invalidate_all_update_counts()
                    refresh(state, { force_counts = true })
                    expand_updated_items(state, updated_names)
                    if ui_win.is_open(state.wins) then
                        M.render(state)
                    end
                end,
                on_error = function()
                    if state.closed then
                        return
                    end

                    state.updating = false
                    if ui_win.is_open(state.wins) then
                        M.render(state)
                    end
                end,
            })
        end)
    end, 'Update all plugins')
    map('u', function()
        local item = current_plugin(state)
        if not item then
            return
        end

        state.updating = true
        M.render(state)
        redraw_now()

        vim.schedule(function()
            state.actions.update_one(item, {
                on_done = function(updated_names)
                    if state.closed or not ui_win.is_open(state.wins) then
                        return
                    end

                    state.updating = false
                    state_model.set_updated_names(state, updated_names, false)
                    state.source.invalidate_update_count(item.path)
                    refresh(state, { force_counts = true })
                    expand_updated_items(state, updated_names)
                    if ui_win.is_open(state.wins) then
                        M.render(state)
                    end
                end,
                on_error = function()
                    if state.closed then
                        return
                    end

                    state.updating = false
                    if ui_win.is_open(state.wins) then
                        M.render(state)
                    end
                end,
            })
        end)
    end, 'Update selected plugin')
    map('x', function()
        local item = current_plugin(state)
        if not item then
            return
        end

        state.actions.delete_one(item, function()
            state.updated_names[item.name] = nil
            state.source.invalidate_update_count(item.path)
            refresh(state, { force_counts = true })
        end)
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
    local state = state_model.create({
        source = opts.source,
        actions = opts.actions,
        wins = create_windows(),
    })

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
