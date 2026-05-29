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

function M.clear_winhighlight_option(win)
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end
    pcall(vim.api.nvim_set_option_value, 'winhighlight', '', { win = win })
end

function M.create_scratch_buf(filetype)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
    if filetype then
        vim.api.nvim_set_option_value('filetype', filetype, { buf = buf })
    end
    return buf
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
    local desired = math.max(content_width or 60, 60)
    local width = clamp(desired, 60, columns - 8)
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
    local min_w = min_width or 60
    local extra = max_extra or 10
    local editor_width = math.max(vim.o.columns, 40)
    local target = math.max(content_width + extra, min_w)
    target = math.min(target, editor_width - 2)
    local ok, current = pcall(vim.api.nvim_win_get_width, win)
    if ok and current ~= target then
        pcall(vim.api.nvim_win_set_width, win, target)
    end
end

function M.create_float(opts)
    local win = vim.api.nvim_open_win(opts.buf, opts.enter == true, {
        relative = 'editor',
        row = opts.row,
        col = opts.col,
        width = opts.width,
        height = opts.height,
        border = 'none',
        style = 'minimal',
        focusable = opts.focusable ~= false,
        zindex = opts.zindex or 50,
    })

    vim.api.nvim_set_option_value('winhighlight', 'Normal:PackUINormal', { win = win })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    vim.api.nvim_set_option_value('cursorline', false, { win = win })
    vim.api.nvim_set_option_value('scrolloff', 0, { win = win })
    return win
end

function M.close_all(wins)
    if wins.main_win and vim.api.nvim_win_is_valid(wins.main_win) then
        vim.api.nvim_win_close(wins.main_win, true)
    end
    if wins.main_buf and vim.api.nvim_buf_is_valid(wins.main_buf) then
        vim.api.nvim_buf_delete(wins.main_buf, { force = true })
    end
end

function M.is_open(wins)
    return wins and wins.main_win and vim.api.nvim_win_is_valid(wins.main_win)
end

return M
