local cache = require('packui.source.cache')
local normalize = require('packui.source.normalize')
local preview = require('packui.source.preview')

local M = {}

local function safe_decode_json(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok or type(lines) ~= 'table' then
        return nil
    end

    local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
    if not decoded_ok or type(decoded) ~= 'table' then
        return nil
    end
    return decoded
end

local function sort_by_name(items)
    table.sort(items, function(a, b)
        return (a.name or '') < (b.name or '')
    end)
    return items
end

local function list_from_pack_get()
    if type(vim.pack) ~= 'table' or type(vim.pack.get) ~= 'function' then
        return nil
    end

    local ok, data = pcall(vim.pack.get, nil, { info = false })
    if not ok or type(data) ~= 'table' then
        return nil
    end

    local items = {}
    for _, item in ipairs(data) do
        local normalized = normalize.normalize_pack_item(item, cache.update_count_cached(item.path))
        items[#items + 1] = preview.build(normalized)
    end

    return sort_by_name(items)
end

local function list_from_lock_file()
    local decoded = safe_decode_json(vim.fn.stdpath('config') .. '/nvim-pack-lock.json')
    if not decoded or type(decoded.plugins) ~= 'table' then
        return {}
    end

    local items = {}
    for name, spec in pairs(decoded.plugins) do
        if type(name) == 'string' and type(spec) == 'table' then
            items[#items + 1] = preview.build(normalize.normalize_lock_item(name, spec))
        end
    end

    return sort_by_name(items)
end

function M.list_plugins()
    local plugins = list_from_pack_get()
    if plugins and #plugins > 0 then
        return plugins
    end

    return list_from_lock_file()
end

function M.prime_update_counts(items, on_updated, opts)
    return cache.prime_update_counts(items, on_updated, opts)
end

function M.invalidate_update_count(path)
    cache.invalidate(path)
end

function M.invalidate_all_update_counts()
    cache.invalidate_all()
end

return M
