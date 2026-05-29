local M = {}
local git = require('packui.git')

local update_cache = {}
local update_inflight = {}
-- generation 让失效后的旧 Git job 回调无法覆盖新缓存。
local update_generation = {}

local function next_generation(path)
    update_generation[path] = (update_generation[path] or 0) + 1
    return update_generation[path]
end

local function update_count_from_result(res)
    if res and res.code == 0 then
        local out = (res.stdout or ''):gsub('%s+', '')
        if out ~= '' then
            return out
        end
    end
    return '-'
end

local function should_prime_update_count(path)
    return type(path) == 'string' and path ~= '' and update_cache[path] == nil and not update_inflight[path]
end

function M.update_count_cached(path)
    if type(path) ~= 'string' or path == '' then
        return '-'
    end
    return update_cache[path] or '-'
end

function M.invalidate(path)
    if type(path) == 'string' and path ~= '' then
        update_cache[path] = nil
        update_inflight[path] = nil
        next_generation(path)
    end
end

function M.invalidate_all()
    update_cache = {}
    for path in pairs(update_inflight) do
        next_generation(path)
    end
    update_inflight = {}
end

function M.prime_update_counts(items, on_updated, opts)
    local pending = 0
    local force = opts and opts.force == true

    -- packui.git 已把回调切回主循环；这里仅等待本轮启动的 Git job 全部结束。
    for _, item in ipairs(items or {}) do
        local path = item.path
        if force then
            M.invalidate(path)
        end

        if should_prime_update_count(path) then
            local generation = next_generation(path)

            local function on_done(res)
                if update_inflight[path] == generation then
                    update_cache[path] = update_count_from_result(res)
                    update_inflight[path] = nil
                end
                pending = pending - 1

                if pending == 0 and on_updated then
                    on_updated()
                end
            end

            pending = pending + 1
            update_inflight[path] = generation
            git.update_count(path, on_done)
        end
    end

    return pending > 0
end

return M
