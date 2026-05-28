local M = {}
local utils = require('packui.utils')

local notify = utils.notify

local function ensure_pack_api()
    if type(vim.pack) ~= 'table' then
        notify('PackUI: vim.pack is not available in this Neovim build', vim.log.levels.ERROR)
        return false
    end
    return true
end

function M.update_all(on_done)
    if not ensure_pack_api() then
        return
    end

    local ok, err = pcall(vim.pack.update, nil, { force = true })
    if not ok then
        notify('PackUI: update all failed: ' .. tostring(err), vim.log.levels.ERROR)
    end

    if on_done then
        on_done()
    end
end

function M.update_one(item, on_done)
    if not item or not item.name then
        notify('PackUI: no plugin selected', vim.log.levels.WARN)
        return
    end

    if not ensure_pack_api() then
        return
    end

    local ok, err = pcall(vim.pack.update, { item.name }, { force = true })
    if not ok then
        notify('PackUI: update failed for ' .. item.name .. ': ' .. tostring(err), vim.log.levels.ERROR)
    end

    if on_done then
        on_done()
    end
end

function M.delete_one(item, on_done)
    if not item or not item.name then
        notify('PackUI: no plugin selected', vim.log.levels.WARN)
        return
    end

    local confirmed = vim.fn.confirm(
        string.format('Delete plugin "%s"?', item.name),
        '&Yes\n&No',
        2
    )
    if confirmed ~= 1 then
        return
    end

    if not ensure_pack_api() then
        return
    end

    local ok, err = pcall(vim.pack.del, { item.name }, { force = true })
    if not ok then
        notify('PackUI: delete failed for ' .. item.name .. ': ' .. tostring(err), vim.log.levels.ERROR)
    else
        notify(
            string.format('PackUI: %s deleted from disk. Remove its spec to avoid reinstall on next startup.', item.name),
            vim.log.levels.WARN
        )
    end

    if on_done then
        on_done()
    end
end

function M.open_github(item)
    if not item or item.header then
        notify('PackUI: select a plugin first', vim.log.levels.WARN)
        return
    end

    if type(item.github_url) ~= 'string' or item.github_url == '' then
        notify('PackUI: no GitHub repository for ' .. tostring(item.name or 'selected plugin'), vim.log.levels.WARN)
        return
    end

    if utils.open_url(item.github_url) then
        notify('PackUI: opened ' .. item.github_url, vim.log.levels.INFO)
    end
end

return M
