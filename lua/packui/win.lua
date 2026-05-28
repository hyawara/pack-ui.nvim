local M = {}

local HIGHLIGHTS = {
    PackUINormal = { link = 'NormalFloat' },
    PackUIBorder = { link = 'FloatBorder' },
    PackUITitle = { link = 'Title' },
    PackUIFooter = { link = 'Comment' },
    PackUIHeader = { link = 'Title' },
    PackUISelected = { link = 'Visual' },
}

function M.setup_highlights()
    for group, opts in pairs(HIGHLIGHTS) do
        opts.default = true
        vim.api.nvim_set_hl(0, group, opts)
    end
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

function M.calc_layout()
    local columns = math.max(vim.o.columns, 40)
    local lines = math.max(vim.o.lines - vim.o.cmdheight, 12)
    local width = clamp(math.floor(columns * 0.88), 60, columns - 4)
    local height = clamp(math.floor(lines * 0.78), 14, lines - 4)
    local row = math.max(1, math.floor((lines - height) / 2))
    local col = math.max(2, math.floor((columns - width) / 2))
    local footer_height = 1
    local panel_height = height - footer_height
    local list_width = clamp(math.floor(width * 0.48), 34, width - 30)
    local detail_width = width - list_width

    return {
        list = { row = row, col = col, width = list_width, height = panel_height },
        detail = { row = row, col = col + list_width, width = detail_width, height = panel_height },
        footer = { row = row + panel_height, col = col, width = width, height = footer_height },
    }
end

function M.create_float(opts)
    local win = vim.api.nvim_open_win(opts.buf, opts.enter == true, {
        relative = 'editor',
        row = opts.row,
        col = opts.col,
        width = opts.width,
        height = opts.height,
        border = opts.border or 'rounded',
        title = opts.title,
        title_pos = opts.title_pos or 'center',
        style = 'minimal',
        focusable = opts.focusable ~= false,
        zindex = opts.zindex or 50,
    })

    vim.api.nvim_set_option_value('winhighlight', 'Normal:PackUINormal,FloatBorder:PackUIBorder,FloatTitle:PackUITitle', { win = win })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    vim.api.nvim_set_option_value('cursorline', opts.cursorline == true, { win = win })
    return win
end

function M.close_all(wins)
    for _, key in ipairs({ 'list_win', 'detail_win', 'footer_win' }) do
        local win = wins[key]
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    for _, key in ipairs({ 'list_buf', 'detail_buf', 'footer_buf' }) do
        local buf = wins[key]
        if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

function M.is_open(wins)
    return wins and wins.list_win and vim.api.nvim_win_is_valid(wins.list_win)
end

return M
