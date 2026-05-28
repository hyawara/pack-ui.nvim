local M = {}

local function line(label, value)
    return string.format('- **%s**: %s', label, tostring(value or '-'))
end

function M.build(item)
    local status = item.active and 'active' or 'inactive'
    local update_status = item.has_update and 'available' or tostring(item.update_count or '-')

    item.preview = {
        text = table.concat({
            '# PackUI: ' .. tostring(item.name or '-'),
            '',
            '## Keys',
            '- `g`: open GitHub repository',
            '- `U`: update all plugins',
            '- `u`: update selected plugin',
            '- `x`: delete selected plugin',
            '- `r`: refresh list',
            '- `<CR>`: focus details panel',
            '- `?`: show key help',
            '',
            '## Details',
            line('Status', status),
            line('Version', item.version),
            line('Commit', item.short_rev),
            line('Updates', update_status),
            line('Repo', item.repo),
            line('GitHub', item.github_url),
            line('URL', item.src),
            line('Path', item.path ~= '' and item.path or '-'),
        }, '\n'),
        ft = 'markdown',
        loc = false,
    }

    return item
end

return M
