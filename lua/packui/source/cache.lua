local M = {}

local update_cache = {}
local update_inflight = {}

function M.update_count_cached(path)
    if type(path) ~= 'string' or path == '' then
        return '-'
    end
    return update_cache[path] or '-'
end

function M.invalidate(path)
    if type(path) == 'string' and path ~= '' then
        update_cache[path] = nil
    end
end

function M.invalidate_all()
    update_cache = {}
end

function M.prime_update_counts(items, on_updated, opts)
    local pending = 0
    local force = opts and opts.force == true

    for _, item in ipairs(items or {}) do
        local path = item.path
        if force then
            M.invalidate(path)
        end

        if type(path) == 'string' and path ~= '' and update_cache[path] == nil and not update_inflight[path] then
            pending = pending + 1
            update_inflight[path] = true

            vim.system({ 'git', 'rev-list', '--count', 'HEAD..@{upstream}' }, {
                cwd = path,
                text = true,
            }, function(res)
                local value = '-'
                if res and res.code == 0 then
                    local out = (res.stdout or ''):gsub('%s+', '')
                    if out ~= '' then
                        value = out
                    end
                end

                update_cache[path] = value
                update_inflight[path] = nil
                pending = pending - 1

                if pending == 0 and on_updated then
                    vim.schedule(on_updated)
                end
            end)
        end
    end

    return pending > 0
end

return M
