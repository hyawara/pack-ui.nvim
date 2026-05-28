local M = {}
local utils = require('packui.utils')
local snacks_ok, snacks = pcall(require, 'snacks')

local COLUMN_FORMAT = '%-2s %-28s %-9s %-12s %-8s %-7s %s'

local function header_text()
    return string.format(COLUMN_FORMAT, '', 'NAME', 'STATUS', 'VERSION', 'COMMIT', 'UPDATES', 'REPO')
end

local function row_text(item)
    local icon = item.active and '●' or '○'
    local status = item.active and 'active' or 'inactive'
    return string.format(
        COLUMN_FORMAT,
        icon,
        item.name or '',
        status,
        item.version or '-',
        item.short_rev or '-',
        item.update_count or '-',
        item.repo or '-'
    )
end

local function build_items(plugins)
    local items = {
        { header = true, text = header_text(), preview = { text = '# PackUI\n\nSelect a plugin to view details.', ft = 'markdown', loc = false } },
    }
    for _, plugin in ipairs(plugins) do
        plugin.text = row_text(plugin)
        items[#items + 1] = plugin
    end
    return items
end

local function current_plugin(picker)
    local item = picker:current()
    if not item or item.header then
        utils.notify('PackUI: select a plugin first', vim.log.levels.WARN)
        return nil
    end
    return item
end

function M.open(opts)
    local source = assert(opts.source, 'packui.ui.open requires source')
    local actions = assert(opts.actions, 'packui.ui.open requires actions')
    local refreshing = false

    local picker_items = build_items(source.list_plugins())

    local function refresh(picker, refresh_opts)
        if refreshing then
            return
        end
        refreshing = true
        picker_items = build_items(source.list_plugins())
        local has_async_jobs = source.prime_update_counts(picker_items, function()
            refreshing = false
            picker_items = build_items(source.list_plugins())
            if picker and not picker.closed then
                picker:find()
            end
        end, { force = refresh_opts and refresh_opts.force_counts == true })

        if picker and not picker.closed then
            picker:find()
        end

        if not has_async_jobs then
            refreshing = false
        end
    end

    if not snacks_ok then
        utils.notify('PackUI: snacks.nvim is required for the picker UI', vim.log.levels.ERROR)
        return nil
    end

    return snacks.picker.pick({
        source = 'packui',
        title = 'PackUI - vim.pack manager',
        finder = function()
            return picker_items
        end,
        format = function(item)
            if item.header then
                return { { item.text or '', 'Title' } }
            end
            return { { item.text or '' } }
        end,
        preview = 'preview',
        layout = {
            preset = 'default',
            preview = true,
        },
        win = {
            input = {
                title = 'Search plugins',
                keys = {
                    ['<c-r>'] = { 'refresh_packui', mode = { 'i', 'n' }, desc = 'Refresh list' },
                    ['g'] = { 'open_github_packui', mode = { 'n' }, desc = 'Open GitHub repo' },
                    ['U'] = { 'update_all_packui', mode = { 'n' }, desc = 'Update all plugins' },
                    ['u'] = { 'update_one_packui', mode = { 'n' }, desc = 'Update selected plugin' },
                    ['x'] = { 'delete_one_packui', mode = { 'n' }, desc = 'Delete selected plugin' },
                    ['r'] = { 'refresh_packui', mode = { 'n' }, desc = 'Refresh list' },
                    ['<CR>'] = { 'details_packui', mode = { 'n' }, desc = 'Open details panel' },
                    ['q'] = { 'close', mode = { 'n' }, desc = 'Close PackUI' },
                },
            },
            list = {
                title = 'Plugins  |  g:GitHub  U:All  u:One  x:Delete  r:Refresh  Enter:Details',
                keys = {
                    ['g'] = { 'open_github_packui', mode = { 'n' }, desc = 'Open GitHub repo' },
                    ['U'] = { 'update_all_packui', mode = { 'n' }, desc = 'Update all plugins' },
                    ['u'] = { 'update_one_packui', mode = { 'n' }, desc = 'Update selected plugin' },
                    ['x'] = { 'delete_one_packui', mode = { 'n' }, desc = 'Delete selected plugin' },
                    ['r'] = { 'refresh_packui', mode = { 'n' }, desc = 'Refresh list' },
                    ['<CR>'] = { 'details_packui', mode = { 'n' }, desc = 'Open details panel' },
                    ['q'] = { 'close', mode = { 'n' }, desc = 'Close PackUI' },
                },
            },
            preview = {
                title = 'Plugin details',
            },
        },
        actions = {
            refresh_packui = function(picker)
                refresh(picker, { force_counts = true })
                utils.notify('PackUI refreshed', vim.log.levels.INFO)
            end,
            update_all_packui = function(picker)
                actions.update_all(function()
                    source.invalidate_all_update_counts()
                    refresh(picker, { force_counts = true })
                end)
            end,
            update_one_packui = function(picker)
                local item = current_plugin(picker)
                if not item then
                    return
                end
                actions.update_one(item, function()
                    source.invalidate_update_count(item.path)
                    refresh(picker, { force_counts = true })
                end)
            end,
            delete_one_packui = function(picker)
                local item = current_plugin(picker)
                if not item then
                    return
                end
                actions.delete_one(item, function()
                    source.invalidate_update_count(item.path)
                    refresh(picker, { force_counts = true })
                end)
            end,
            open_github_packui = function(picker)
                local item = current_plugin(picker)
                if not item then
                    return
                end
                actions.open_github(item)
            end,
            details_packui = function(picker)
                picker:toggle('preview', { enable = true, focus = 'preview' })
            end,
        },
        on_show = function(picker)
            refresh(picker)
        end,
    })
end

return M
