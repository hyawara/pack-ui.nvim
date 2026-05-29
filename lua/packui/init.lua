local source = require('packui.source')
local ui = require('packui.ui')
local actions = require('packui.actions')

local M = {}

function M.open()
    ui.open({ source = source, actions = actions })
end

return M
