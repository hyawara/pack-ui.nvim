local Popup = require('nui.popup')

local M = {}

local HIGHLIGHTS = {
    PackUINormal = { link = 'NormalFloat' },
    PackUIBorder = { link = 'FloatBorder' },
    PackUITitle = { link = 'Title' },
    PackUIKeyHint = { link = 'Comment' },
    PackUIUpdating = { link = 'DiagnosticInfo' },
    PackUIUpdatedHeader = { link = 'DiffAdd' },
    PackUIAllPluginsHeader = { link = 'Title' },
    PackUIColumnHeader = { link = 'Type' },
    PackUIRowName = { link = 'Identifier' },
    PackUIRowActive = { link = 'String' },
    PackUIRowInactive = { link = 'Comment' },
    PackUIRowVersion = { link = 'Number' },
    PackUIDetail = { link = 'Comment' },
    PackUIUpdatedRow = { link = 'DiffAdd' },
    PackUIUpdatedDetail = { link = 'DiffChange' },
    PackUISelected = { link = 'Visual' },
}

function M.setup_highlights()
    for group, opts in pairs(HIGHLIGHTS) do
        opts.default = true
        vim.api.nvim_set_hl(0, group, opts)
    end
end

function M.set_buf_lines(buf, lines)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
end

local function clamp(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

function M.calc_layout(content_width)
    local columns = math.max(vim.o.columns, 40)
    local lines = math.max(vim.o.lines - vim.o.cmdheight, 12)
    local desired = math.max(content_width or 84, 84)
    local width = clamp(desired, 84, columns - 4)
    local height = clamp(math.floor(lines * 0.82), 14, lines - 2)
    local row = math.max(0, math.floor((lines - height) / 2) - 1)
    local col = math.max(3, math.floor((columns - width) / 4))

    return {
        main = { row = row, col = col, width = width, height = height },
    }
end

function M.resize_win_to_content(win, content_width, min_width, max_extra)
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end
    local min_w = min_width or 84
    local extra = max_extra or 18
    local editor_width = math.max(vim.o.columns, 40)
    local target = math.max(content_width + extra, min_w)
    target = math.min(target, editor_width - 4)
    local ok, current = pcall(vim.api.nvim_win_get_width, win)
    if ok and current ~= target then
        pcall(vim.api.nvim_win_set_width, win, target)
    end
end

function M.create_popup(opts)
    local popup = Popup({
        enter = opts.enter == true,
        focusable = opts.focusable ~= false,
        relative = 'editor',
        position = {
            row = opts.row,
            col = opts.col,
        },
        size = {
            width = opts.width,
            height = opts.height,
        },
        buf_options = {
            buftype = 'nofile',
            bufhidden = 'wipe',
            swapfile = false,
            modifiable = false,
        },
        win_options = {
            winhighlight = 'Normal:PackUINormal,FloatBorder:PackUIBorder,FloatTitle:PackUITitle',
            wrap = false,
            cursorline = false,
            scrolloff = 0,
        },
        zindex = opts.zindex or 50,
    })

    popup:mount()
    return popup
end

function M.close_all(wins)
    if not wins or not wins.main_popup then
        return
    end

    pcall(function()
        wins.main_popup:unmount()
    end)
end

function M.is_open(wins)
    return wins and wins.main_win and vim.api.nvim_win_is_valid(wins.main_win)
end

return M
