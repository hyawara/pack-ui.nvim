local Job = require('plenary.job')
local Path = require('plenary.path')

local M = {}

local function run_git(args, cwd, on_done)
    Job:new({
        command = 'git',
        args = args,
        cwd = cwd,
        on_exit = function(j, code)
            local stdout = table.concat(j:result() or {}, '\n')
            vim.schedule(function()
                on_done({ code = code, stdout = stdout })
            end)
        end,
    }):start()
end

function M.is_repo(path)
    if type(path) ~= 'string' or path == '' then
        return false
    end

    local root = Path:new(path)
    local dot_git = Path:new(path, '.git')
    return root:exists() and root:is_dir() and dot_git:exists()
end

function M.update_count(path, on_done)
    run_git({ 'rev-list', '--count', 'HEAD..@{upstream}' }, path, on_done)
end

function M.recent_commits(path, on_done)
    run_git({ 'log', '--oneline', '-5' }, path, on_done)
end

return M
