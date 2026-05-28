local source = require('packui.source')
local ui = require('packui.ui')
local actions = require('packui.actions')
local utils = require('packui.utils')

local M = {}

function M.open()
    local picker = ui.open({ source = source, actions = actions })
    if not picker then
        utils.notify('PackUI: failed to open window', vim.log.levels.ERROR)
        return
    end
end

return M
