local M = {}
local git = require('packui.git')

local update_cache = {}
local update_inflight = {}
-- generation 让失效后的旧 Git job 回调无法覆盖新缓存。
local update_generation = {}
local latest_commit_cache = {}
local latest_commit_inflight = {}
local latest_commit_generation = {}

local function next_generation(path)
    update_generation[path] = (update_generation[path] or 0) + 1
    return update_generation[path]
end

local function next_latest_commit_generation(path)
    latest_commit_generation[path] = (latest_commit_generation[path] or 0) + 1
    return latest_commit_generation[path]
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

local function latest_commit_from_result(res)
    if res and res.code == 0 then
        local out = (res.stdout or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if out ~= '' then
            return out
        end
    end
    return '-'
end

local function invalidate_update_count(path)
    update_cache[path] = nil
    update_inflight[path] = nil
    next_generation(path)
end

local function invalidate_latest_commit(path)
    latest_commit_cache[path] = nil
    latest_commit_inflight[path] = nil
    next_latest_commit_generation(path)
end

local function should_prime_update_count(path)
    return type(path) == 'string' and path ~= '' and update_cache[path] == nil and not update_inflight[path]
end

local function should_prime_latest_commit(path)
    return type(path) == 'string' and path ~= '' and latest_commit_cache[path] == nil and not latest_commit_inflight[path]
end

function M.update_count_cached(path)
    if type(path) ~= 'string' or path == '' then
        return '-'
    end
    return update_cache[path] or '-'
end

function M.latest_commit_cached(path)
    if type(path) ~= 'string' or path == '' then
        return '-'
    end
    return latest_commit_cache[path] or '-'
end

function M.invalidate(path)
    if type(path) == 'string' and path ~= '' then
        invalidate_update_count(path)
        invalidate_latest_commit(path)
    end
end

function M.invalidate_all()
    update_cache = {}
    latest_commit_cache = {}
    for path in pairs(update_inflight) do
        next_generation(path)
    end
    for path in pairs(latest_commit_inflight) do
        next_latest_commit_generation(path)
    end
    update_inflight = {}
    latest_commit_inflight = {}
end

function M.prime_update_counts(items, on_updated, opts)
    local pending = 0
    local force = opts and opts.force == true

    -- packui.git 已把回调切回主循环；这里仅等待本轮启动的 Git job 全部结束。
    for _, item in ipairs(items or {}) do
        local path = item.path
        if force then
            invalidate_update_count(path)
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

function M.prime_latest_commits(items, on_updated, opts)
    local pending = 0
    local force = opts and opts.force == true

    for _, item in ipairs(items or {}) do
        if item.active == true then
            local path = item.path
            if force and type(path) == 'string' and path ~= '' then
                invalidate_latest_commit(path)
            end

            if should_prime_latest_commit(path) then
                local generation = next_latest_commit_generation(path)

                local function on_done(res)
                    if latest_commit_inflight[path] == generation then
                        latest_commit_cache[path] = latest_commit_from_result(res)
                        latest_commit_inflight[path] = nil
                    end
                    pending = pending - 1

                    if pending == 0 and on_updated then
                        on_updated()
                    end
                end

                pending = pending + 1
                latest_commit_inflight[path] = generation
                git.latest_commit_subject(path, on_done)
            end
        end
    end

    return pending > 0
end

return M
