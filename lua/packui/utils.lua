local M = {}

function M.notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO)
end

function M.open_url(url)
    if type(url) ~= 'string' or url == '' then
        M.notify('PackUI: no URL to open', vim.log.levels.WARN)
        return false
    end

    if vim.ui and type(vim.ui.open) == 'function' then
        vim.ui.open(url)
        return true
    end

    local command
    if vim.fn.has('win32') == 1 then
        command = { 'cmd', '/c', 'start', '', url }
    elseif vim.fn.has('mac') == 1 then
        command = { 'open', url }
    else
        command = { 'xdg-open', url }
    end

    vim.fn.jobstart(command, { detach = true })
    return true
end

return M
