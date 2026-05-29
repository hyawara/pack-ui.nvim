local M = {}

local function value_or_dash(value)
    if value == nil or value == '' then
        return '-'
    end
    return tostring(value)
end

function M.short_rev(rev)
    if type(rev) ~= 'string' or rev == '' then
        return '-'
    end
    return rev:sub(1, 8)
end

function M.repo_from_url(url)
    if type(url) ~= 'string' or url == '' then
        return '-'
    end

    local repo = url:match('github%.com[:/]%d+/(.+)$') or url:match('github%.com[:/](.+)$')
    if not repo then
        return url:gsub('%.git$', '')
    end

    return repo:gsub('%.git$', '')
end

function M.github_url_from_repo(repo)
    if type(repo) ~= 'string' or repo == '' or repo == '-' then
        return '-'
    end

    if repo:match('^https?://') then
        return repo
    end

    if not repo:match('^[%w%._%-]+/[%w%._%-]+$') then
        return '-'
    end

    return 'https://github.com/' .. repo
end

function M.from_pack_item(item, update_count)
    local spec = item.spec or {}
    local name = spec.name or vim.fn.fnamemodify(item.path or '', ':t')
    local src = spec.src or spec.url or ''
    local repo = M.repo_from_url(src)

    return {
        name = value_or_dash(name),
        src = value_or_dash(src),
        repo = repo,
        github_url = M.github_url_from_repo(repo),
        version = value_or_dash(spec.version),
        short_rev = M.short_rev(item.rev),
        update_count = value_or_dash(update_count),
        rev = item.rev,
        rev_to = item.rev_to,
        has_update = type(item.rev_to) == 'string' and item.rev_to ~= '' and item.rev_to ~= item.rev,
        installed = true,
        active = item.active == true,
        path = item.path or '',
    }
end

function M.from_lock_item(name, spec)
    local src = spec.src or spec.url or ''
    local repo = M.repo_from_url(src)

    return {
        name = value_or_dash(name),
        src = value_or_dash(src),
        repo = repo,
        github_url = M.github_url_from_repo(repo),
        version = value_or_dash(spec.version),
        short_rev = M.short_rev(spec.rev),
        update_count = '-',
        rev = spec.rev,
        rev_to = nil,
        has_update = false,
        installed = true,
        active = false,
        path = '',
    }
end

return M
