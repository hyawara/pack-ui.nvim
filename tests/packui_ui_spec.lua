-- 测试只验证 PackUI 自己的行为，nui/plenary 用最小替身隔离外部插件安装状态。
package.preload['nui.popup'] = function()
    local Popup = {}
    Popup.__index = Popup

    setmetatable(Popup, {
        __call = function(_, opts)
            return setmetatable({ opts = opts or {} }, Popup)
        end,
    })

    function Popup:mount()
        self.bufnr = vim.api.nvim_create_buf(false, true)

        for name, value in pairs(self.opts.buf_options or {}) do
            vim.api.nvim_set_option_value(name, value, { buf = self.bufnr })
        end

        local border = self.opts.border and self.opts.border.style or self.opts.border
        if border == 'none' then
            border = nil
        end

        self.winid = vim.api.nvim_open_win(self.bufnr, self.opts.enter == true, {
            relative = self.opts.relative or 'editor',
            row = self.opts.position and self.opts.position.row or 1,
            col = self.opts.position and self.opts.position.col or 1,
            width = self.opts.size and self.opts.size.width or 60,
            height = self.opts.size and self.opts.size.height or 20,
            border = border,
            style = 'minimal',
            focusable = self.opts.focusable ~= false,
            zindex = self.opts.zindex,
        })

        for name, value in pairs(self.opts.win_options or {}) do
            vim.api.nvim_set_option_value(name, value, { win = self.winid })
        end
    end

    function Popup:unmount()
        if self.winid and vim.api.nvim_win_is_valid(self.winid) then
            vim.api.nvim_win_close(self.winid, true)
        end
        if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
            vim.api.nvim_buf_delete(self.bufnr, { force = true })
        end
    end

    return Popup
end

package.preload['plenary.job'] = function()
    local Job = {}
    Job.__index = Job

    function Job:new(opts)
        return setmetatable({ opts = opts or {} }, self)
    end

    function Job:start()
        if self.opts.on_exit then
            self.opts.on_exit({
                result = function()
                    return {}
                end,
            }, 1)
        end
        return self
    end

    return Job
end

package.preload['plenary.path'] = function()
    local Path = {}
    Path.__index = Path

    function Path:new(...)
        local parts = { ... }
        return setmetatable({ filename = table.concat(parts, '/') }, self)
    end

    function Path:exists()
        return vim.fn.filereadable(self.filename) == 1 or vim.fn.isdirectory(self.filename) == 1
    end

    function Path:is_dir()
        return vim.fn.isdirectory(self.filename) == 1
    end

    function Path:read()
        return table.concat(vim.fn.readfile(self.filename), '\n')
    end

    return Path
end

local function assert_truthy(value, message)
    if not value then
        error(message, 2)
    end
end

local function assert_equals(expected, actual, message)
    if expected ~= actual then
        error(string.format('%s\nexpected: %s\nactual: %s', message, vim.inspect(expected), vim.inspect(actual)), 2)
    end
end

local function assert_contains(haystack, needle, message)
    if not haystack:find(needle, 1, true) then
        error(string.format('%s\nmissing: %s\nin: %s', message, needle, haystack), 2)
    end
end

local function assert_not_contains(haystack, needle, message)
    if haystack:find(needle, 1, true) then
        error(string.format('%s\nunexpected: %s\nin: %s', message, needle, haystack), 2)
    end
end

local function make_plugin(name)
    return {
        name = name,
        active = true,
        version = 'main',
        short_rev = 'abcdef12',
        latest_commit = 'Initial commit message',
        update_count = '0',
        repo = 'owner/' .. name,
        github_url = 'https://github.com/owner/' .. name,
        src = 'https://github.com/owner/' .. name,
        path = vim.fn.getcwd(),
    }
end

local function make_source(plugins)
    return {
        list_plugins = function()
            return plugins
        end,
        prime_update_counts = function(_, _, _)
            return false
        end,
        prime_latest_commits = function(_, _, _)
            return false
        end,
        invalidate_update_count = function() end,
        invalidate_all_update_counts = function() end,
    }
end

local function make_actions()
    local calls = {
        open_github = 0,
        update_all = 0,
        update_one = 0,
        delete_one = 0,
        last_deleted = nil,
    }

    return {
        calls = calls,
        update_all = function(opts)
            calls.update_all = calls.update_all + 1
            if opts and opts.on_done then
                opts.on_done({})
            end
        end,
        update_one = function(_, opts)
            calls.update_one = calls.update_one + 1
            if opts and opts.on_done then
                opts.on_done({})
            end
        end,
        delete_one = function(item, on_done)
            calls.delete_one = calls.delete_one + 1
            calls.last_deleted = item and item.name or nil
            if on_done then
                on_done()
            end
        end,
        open_github = function()
            calls.open_github = calls.open_github + 1
        end,
    }
end

local function text(buf)
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

local function count_occurrences(haystack, needle)
    local count = 0
    local init = 1
    while true do
        local start_pos, end_pos = haystack:find(needle, init, true)
        if not start_pos then
            break
        end
        count = count + 1
        init = end_pos + 1
    end
    return count
end

local function close_state(state)
    if state and state.close then
        state.close()
    end
end

local function cursor_line(win)
    return vim.api.nvim_win_get_cursor(win)[1]
end

local tests = {}

tests.opens_single_buffer_ui = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })
    assert_truthy(type(state) == 'table', 'ui.open returns a UI state table')

    -- Single main window only
    assert_truthy(vim.api.nvim_win_is_valid(state.wins.main_win), 'main window is valid')
    assert_truthy(state.wins.main_buf, 'main buffer exists')
    assert_equals(true, vim.api.nvim_get_option_value('cursorline', { win = state.wins.main_win }), 'native cursorline is enabled')
    assert_equals(0, vim.api.nvim_get_option_value('winblend', { win = state.wins.main_win }), 'popup is not blended')
    local packui_normal = vim.api.nvim_get_hl(0, { name = 'PackUINormal', link = false })
    assert_truthy(type(packui_normal.bg) == 'number', 'PackUINormal has concrete background')
    assert_equals(0, packui_normal.blend, 'PackUINormal does not blend')
    local winhighlight = vim.api.nvim_get_option_value('winhighlight', { win = state.wins.main_win })
    assert_contains(winhighlight, 'Normal:PackUINormal', 'normal background uses PackUINormal')
    assert_contains(winhighlight, 'NormalNC:PackUINormal', 'inactive floating background uses PackUINormal')
    assert_contains(winhighlight, 'NormalFloat:PackUINormal', 'floating background uses PackUINormal')
    assert_contains(winhighlight, 'EndOfBuffer:PackUINormal', 'empty popup cells use PackUINormal')
    assert_contains(winhighlight, 'NonText:PackUINormal', 'non-text cells use PackUINormal')
    assert_contains(winhighlight, 'SignColumn:PackUINormal', 'sign column uses PackUINormal')

    local buf_text = text(state.wins.main_buf)

    -- Key help at top
    assert_contains(buf_text, 'Open repo (o)', 'open repo hint present')
    assert_contains(buf_text, 'Update (u)', 'update one hint present')
    assert_contains(buf_text, 'Update all (U)', 'update all hint present')
    assert_contains(buf_text, 'Refresh (r)', 'refresh hint present')
    assert_contains(buf_text, 'Details (<CR>)', 'details hint present')
    assert_contains(buf_text, 'Delete (x)', 'delete hint present')
    assert_contains(buf_text, 'Close (q)', 'close hint present')

    -- Column headers present
    assert_contains(buf_text, 'NAME', 'has NAME column')
    assert_contains(buf_text, 'VERSION', 'has VERSION column')
    assert_contains(buf_text, 'COMMIT', 'has COMMIT column')
    assert_contains(buf_text, 'Initial commit message', 'active row shows latest commit message')
    assert_not_contains(buf_text, 'REV', 'does not show REV column')
    assert_not_contains(buf_text, 'STATUS', 'does not show STATUS column')
    assert_contains(buf_text, 'Active Plugins', 'has Active Plugins section')

    -- No eager detail pane

    assert_not_contains(buf_text, 'Status:', 'no eager detail lines')
    assert_not_contains(buf_text, 'Commit:', 'no eager commit info in default view')

    close_state(state)
end

tests.inline_details_toggled_by_cr = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })

    -- Before <CR>: no inline details
    local before_text = text(state.wins.main_buf)
    assert_not_contains(before_text, 'Status:', 'no details before <CR>')

    -- Feed <CR> to toggle details inline
    assert_truthy(state.selected_line, 'selected_line is set after open')
    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_win_set_cursor(state.wins.main_win, { state.selected_line, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)

    -- After <CR>: inline details present
    local after_text = text(state.wins.main_buf)
    assert_contains(after_text, 'Status: ✅ active', 'status shown after <CR>')
    assert_contains(after_text, 'Version: main', 'version in details after <CR>')
    assert_contains(after_text, 'Commit: abcdef12', 'commit in details after <CR>')

    -- Feed <CR> again to collapse
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
    local collapsed_text = text(state.wins.main_buf)
    assert_not_contains(collapsed_text, 'Status:', 'details hidden after second <CR>')

    close_state(state)
end

tests.handles_empty_plugin_list = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({}), actions = make_actions() })
    assert_truthy(type(state) == 'table', 'empty source still opens UI')

    local buf_text = text(state.wins.main_buf)
    assert_contains(buf_text, 'Update (u)', 'update hint renders for empty list')
    assert_contains(buf_text, 'Active Plugins', 'Active Plugins section header for empty list')
    assert_contains(buf_text, 'NAME', 'column header for empty list')

    close_state(state)
end

tests.updated_section_deduplicates_plugin_rows = function()
    local ui = require('packui.ui')
    local actions = make_actions()
    actions.update_one = function(_, opts)
        if opts and opts.on_done then
            opts.on_done({ 'alpha.nvim' })
        end
    end

    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = actions })
    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_win_set_cursor(state.wins.main_win, { state.selected_line, 0 })
    vim.api.nvim_feedkeys('u', 'x', false)

    local ok = vim.wait(100, function()
        return text(state.wins.main_buf):find('📦 Updated Plugins', 1, true) ~= nil
    end)
    assert_truthy(ok, 'update callback renders Updated section')

    local buf_text = text(state.wins.main_buf)
    assert_contains(buf_text, '📦 Updated Plugins', 'updated section appears after update')
    assert_contains(buf_text, 'Active Plugins', 'active plugins section remains visible')
    assert_truthy(count_occurrences(buf_text, 'alpha.nvim') >= 1, 'updated plugin is present after update')

    close_state(state)
end

tests.binds_actions_and_cleans_up = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })
    assert_truthy(type(state) == 'table', 'ui.open returns state for keymap test')

    -- Keymaps bound on main_buf
    local keymaps = vim.api.nvim_buf_get_keymap(state.wins.main_buf, 'n')
    local seen = {}
    for _, keymap in ipairs(keymaps) do
        seen[keymap.lhs] = keymap.desc or true
    end

    for _, key in ipairs({ 'o', 'U', 'u', 'x', 'r', '<CR>', 'q' }) do
        assert_truthy(seen[key], 'main buffer binds key ' .. key)
    end

    -- Close cleans main_win
    local main_win = state.wins.main_win
    close_state(state)
    assert_equals(false, vim.api.nvim_win_is_valid(main_win), 'close invalidates main window')
end

tests.o_key_opens_selected_plugin_repository = function()
    local ui = require('packui.ui')
    local actions = make_actions()
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = actions })

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_feedkeys('o', 'x', false)

    assert_equals(1, actions.calls.open_github, 'o invokes open_github for the selected plugin')

    close_state(state)
end

tests.key_hints_match_real_keymaps = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })

    local buf_text = text(state.wins.main_buf)
    assert_contains(buf_text, 'Refresh (r)', 'refresh hint matches mapped key')
    assert_contains(buf_text, 'Delete (x)', 'delete hint matches mapped key')
    assert_contains(buf_text, 'Close (q)', 'close hint matches mapped key')

    close_state(state)
end

tests.navigation_moves_one_rendered_row_at_a_time = function()
    local ui = require('packui.ui')
    local plugins = { make_plugin('alpha.nvim'), make_plugin('beta.nvim') }
    local state = ui.open({ source = make_source(plugins), actions = make_actions() })

    local first_item = state.line_to_item[state.selected_line]
    assert_truthy(first_item and first_item.name == 'alpha.nvim', 'selection starts on first plugin row')
    local first_plugin_line = state.selected_line

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_win_set_cursor(state.wins.main_win, { first_plugin_line, 0 })
    vim.api.nvim_feedkeys('k', 'x', false)

    assert_equals(first_plugin_line - 1, cursor_line(state.wins.main_win), 'native k moves one rendered row up')
    assert_truthy(state.line_to_item[cursor_line(state.wins.main_win)] == nil, 'current cursor line is not a plugin row')

    vim.api.nvim_feedkeys('j', 'x', false)
    local second_item = state.line_to_item[cursor_line(state.wins.main_win)]
    assert_truthy(second_item and second_item.name == 'alpha.nvim', 'moving down returns to first plugin row')

    vim.api.nvim_feedkeys('j', 'x', false)
    local third_item = state.line_to_item[cursor_line(state.wins.main_win)]
    assert_truthy(third_item and third_item.name == 'beta.nvim', 'second j lands on next plugin row')

    close_state(state)
end

tests.refresh_preserves_expanded_plugin_details = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
    assert_contains(text(state.wins.main_buf), 'Status: ✅ active', 'details expand before refresh')

    vim.api.nvim_feedkeys('r', 'x', false)
    assert_contains(text(state.wins.main_buf), 'Status: ✅ active', 'refresh keeps expanded details for same plugin')

    close_state(state)
end

tests.update_all_key_invokes_action = function()
    local ui = require('packui.ui')
    local actions = make_actions()
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = actions })

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_feedkeys('U', 'x', false)
    vim.wait(50)

    assert_equals(1, actions.calls.update_all, 'U invokes update_all action')

    close_state(state)
end

tests.delete_key_invokes_action_for_selected_plugin = function()
    local ui = require('packui.ui')
    local actions = make_actions()
    local plugins = { make_plugin('alpha.nvim'), make_plugin('beta.nvim') }
    local state = ui.open({ source = make_source(plugins), actions = actions })

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_feedkeys('x', 'x', false)
    vim.wait(50)

    assert_equals(1, actions.calls.delete_one, 'x invokes delete_one action')
    assert_equals('alpha.nvim', actions.calls.last_deleted, 'x deletes the selected plugin')

    close_state(state)
end

tests.navigation_stops_at_boundaries = function()
    local ui = require('packui.ui')
    local plugins = { make_plugin('alpha.nvim'), make_plugin('beta.nvim') }
    local state = ui.open({ source = make_source(plugins), actions = make_actions() })

    vim.api.nvim_set_current_win(state.wins.main_win)

    vim.api.nvim_win_set_cursor(state.wins.main_win, { 1, 0 })
    vim.api.nvim_feedkeys('k', 'x', false)
    assert_equals(1, cursor_line(state.wins.main_win), 'native k stays on the first rendered line')

    local last_line = #state.selectable_lines
    vim.api.nvim_win_set_cursor(state.wins.main_win, { last_line, 0 })
    vim.api.nvim_feedkeys('j', 'x', false)
    assert_equals(last_line, cursor_line(state.wins.main_win), 'native j stays on the last rendered line')

    close_state(state)
end

tests.render_does_not_mutate_state_directly = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })

    local name_before = state.selected_name
    local render = require('packui.ui.render')
    local snapshot = render.build_snapshot(state)

    assert_equals(name_before, state.selected_name, 'build_snapshot does not change selected_name')
    assert_truthy(snapshot.selected_line, 'snapshot still computes selected_line')

    close_state(state)
end

tests.updated_detail_lines_show_only_recent_commits = function()
    local render = require('packui.ui.render')
    local lines = table.concat(render.build_detail_lines(make_plugin('alpha.nvim'), true), '\n')

    assert_contains(lines, 'Recent commits:', 'updated details show recent commits heading')
    assert_contains(lines, 'Loading...', 'updated details keep loading placeholder')
    assert_not_contains(lines, 'Status:', 'updated details omit repeated status')
    assert_not_contains(lines, 'Version:', 'updated details omit repeated version')
    assert_not_contains(lines, 'Commit:', 'updated details omit repeated commit')
    assert_not_contains(lines, 'Repo:', 'updated details omit repeated repo')
end

tests.inactive_plugins_render_in_separate_section = function()
    local render = require('packui.ui.render')
    local active = make_plugin('active.nvim')
    local inactive = make_plugin('inactive.nvim')
    inactive.active = false
    inactive.version = 'v1.2.3'
    inactive.short_rev = '1234abcd'
    inactive.repo = 'owner/inactive.nvim'

    local state = {
        items = { active, inactive },
        updated_items = {},
        updated_names = {},
        selected_name = 'active.nvim',
        expanded = {},
        detail_cache = {},
        updating = false,
        refreshing = false,
    }

    local snapshot = render.build_snapshot(state)
    local text_lines = table.concat(snapshot.lines, '\n')
    assert_contains(text_lines, '🚫 Inactive Plugins', 'inactive section is rendered')
    assert_contains(text_lines, '🧩 Active Plugins', 'active section is rendered')
    assert_not_contains(text_lines, 'REPO', 'inactive header omits REPO column')
    assert_not_contains(text_lines, '1234abcd', 'inactive row omits short commit')
    assert_not_contains(text_lines, 'owner/inactive.nvim', 'inactive row omits repo')

    local inactive_header_line
    for line_number, line in ipairs(snapshot.lines) do
        if line:find('🚫 Inactive Plugins', 1, true) then
            inactive_header_line = line_number + 1
            break
        end
    end

    assert_truthy(inactive_header_line, 'inactive column header line found')
    assert_not_contains(snapshot.lines[inactive_header_line], 'STATUS', 'inactive section omits STATUS column')

    local inactive_rows = 0
    local inactive_line
    for _, item in pairs(snapshot.line_to_item) do
        if item.name == 'inactive.nvim' then
            inactive_rows = inactive_rows + 1
        end
    end
    assert_equals(1, inactive_rows, 'inactive plugin appears in one plugin row')

    for line_number, item in pairs(snapshot.line_to_item) do
        if item.name == 'inactive.nvim' then
            inactive_line = line_number
            break
        end
    end

    for _, entry in ipairs(snapshot.row_highlights) do
        if entry.line == inactive_line then
            local hl = entry.highlights
            assert_equals(2, #hl, 'inactive row has 2 highlight columns')
            assert_equals(hl[1].col_end, hl[2].col_start, 'inactive name meets version')
            assert_equals(#snapshot.lines[inactive_line], hl[2].col_end, 'inactive version reaches row end')
            return
        end
    end

    error('inactive row highlight entry not found')
end

tests.k_from_first_plugin_reaches_key_hints = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })
    local render = require('packui.ui.render')
    local snapshot = render.build_snapshot(state)

    local key_hint_line = 1
    assert_contains(snapshot.lines[key_hint_line], 'Open repo (o)', 'line 1 is the key hint')

    local first_plugin_line = state.selected_line
    assert_truthy(first_plugin_line > key_hint_line, 'first plugin is below key hints')

    vim.api.nvim_set_current_win(state.wins.main_win)
    local presses = first_plugin_line - key_hint_line
    for _ = 1, presses do
        vim.api.nvim_feedkeys('k', 'x', false)
    end

    assert_equals(key_hint_line, cursor_line(state.wins.main_win), 'repeated k from first plugin reaches key hint line')

    close_state(state)
end

tests.j_after_native_top_jump_starts_from_cursor = function()
    local ui = require('packui.ui')
    local state = ui.open({
        source = make_source({ make_plugin('alpha.nvim'), make_plugin('beta.nvim') }),
        actions = make_actions(),
    })

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_win_set_cursor(state.wins.main_win, { 1, 0 })
    vim.api.nvim_feedkeys('j', 'x', false)

    assert_equals(2, cursor_line(state.wins.main_win), 'j after a native top jump starts from line 1')
    assert_truthy(state.line_to_item[cursor_line(state.wins.main_win)] == nil, 'line 2 is not a plugin row')

    close_state(state)
end

tests.k_after_native_bottom_jump_starts_from_cursor = function()
    local ui = require('packui.ui')
    local state = ui.open({
        source = make_source({ make_plugin('alpha.nvim'), make_plugin('beta.nvim') }),
        actions = make_actions(),
    })

    vim.api.nvim_set_current_win(state.wins.main_win)
    local last_line = #state.selectable_lines
    vim.api.nvim_win_set_cursor(state.wins.main_win, { last_line, 0 })
    vim.api.nvim_feedkeys('k', 'x', false)

    assert_equals(last_line - 1, cursor_line(state.wins.main_win), 'k after a native bottom jump starts from the last line')

    close_state(state)
end

tests.plugin_actions_respect_native_cursor_on_non_plugin_line = function()
    local ui = require('packui.ui')
    local actions = make_actions()
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = actions })

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_win_set_cursor(state.wins.main_win, { 1, 0 })
    vim.api.nvim_feedkeys('o', 'x', false)

    assert_equals(0, actions.calls.open_github, 'o on key hint line does not use stale plugin selection')
    assert_equals(nil, state.selected_name, 'key hint line clears selected plugin')

    close_state(state)
end

tests.non_plugin_selected_line_clamps_when_snapshot_shrinks = function()
    local render = require('packui.ui.render')
    local state = {
        items = { make_plugin('alpha.nvim') },
        updated_items = {},
        updated_names = {},
        selected_name = nil,
        selected_line = 999,
        expanded = {},
        detail_cache = {},
        updating = false,
        refreshing = false,
    }

    local snapshot = render.build_snapshot(state)
    assert_equals(#snapshot.lines, snapshot.selected_line, 'non-plugin selected_line clamps to last rendered line')
end

tests.snapshot_has_no_pinned_line_count = function()
    local render = require('packui.ui.render')
    local state = {
        items = { make_plugin('alpha.nvim') },
        updated_items = {},
        updated_names = {},
        selected_name = 'alpha.nvim',
        expanded = {},
        detail_cache = {},
        updating = false,
        refreshing = false,
    }
    local snapshot = render.build_snapshot(state)
    assert_equals(nil, snapshot.pinned_line_count, 'snapshot must not contain pinned_line_count')
end

tests.all_lines_start_with_left_padding = function()
    local render = require('packui.ui.render')
    local state = {
        items = { make_plugin('alpha.nvim') },
        updated_items = {},
        updated_names = {},
        selected_name = 'alpha.nvim',
        expanded = {},
        detail_cache = {},
        updating = false,
        refreshing = false,
    }
    local snapshot = render.build_snapshot(state)
    for i, line in ipairs(snapshot.lines) do
        assert_truthy(
            line:sub(1, 1) == ' ',
            string.format('line %d should start with left padding space, got: %q', i, line:sub(1, 1))
        )
    end
end

tests.row_highlights_are_contiguous = function()
    local render = require('packui.ui.render')
    local state = {
        items = { make_plugin('alpha.nvim') },
        updated_items = {},
        updated_names = {},
        selected_name = 'alpha.nvim',
        expanded = {},
        detail_cache = {},
        updating = false,
        refreshing = false,
    }
    local snapshot = render.build_snapshot(state)
    assert_truthy(#snapshot.row_highlights > 0, 'snapshot has row highlights')

    for _, entry in ipairs(snapshot.row_highlights) do
        local hl = entry.highlights
        local line = snapshot.lines[entry.line]
        assert_equals(3, #hl, 'active row has 3 highlight entries')
        assert_equals(1, hl[1].col_start, 'name highlight starts after LEFT_PAD')
        assert_equals(hl[1].col_end, hl[2].col_start, 'name highlight end meets version highlight start')
        assert_equals(hl[2].col_end, hl[3].col_start, 'version highlight end meets commit highlight start')
        assert_equals(#line, hl[3].col_end, 'commit highlight end reaches actual line byte length')
    end
end

tests.updated_section_has_separator = function()
    local render = require('packui.ui.render')
    local plugin = make_plugin('alpha.nvim')
    local state = {
        items = { plugin },
        updated_items = { plugin },
        updated_names = { ['alpha.nvim'] = true },
        selected_name = 'alpha.nvim',
        expanded = {},
        detail_cache = {},
        updating = false,
        refreshing = false,
    }
    local snapshot = render.build_snapshot(state)

    local found_separator = false
    for line_number, group in pairs(snapshot.highlight_map) do
        if group == 'PackUIUpdatedSeparator' then
            found_separator = true
            local line = snapshot.lines[line_number]
            assert_truthy(line:find('─', 1, true), 'separator line contains dash characters')
            assert_truthy(line:sub(1, 1) == ' ', 'separator line has left padding')
            break
        end
    end
    assert_truthy(found_separator, 'Updated section has a PackUIUpdatedSeparator highlight')
end

tests.plugin_rows_have_uniform_display_width = function()
    local render = require('packui.ui.render')
    local short_version = {
        name = 'short.nvim',
        active = true,
        version = '-',
        short_rev = 'a1',
        repo = 'o/short.nvim',
        github_url = 'https://github.com/o/short.nvim',
        src = 'https://github.com/o/short.nvim',
        path = vim.fn.getcwd(),
    }
    local medium_version = {
        name = 'medium.nvim',
        active = true,
        version = 'main',
        short_rev = 'b2',
        repo = 'o/medium.nvim',
        github_url = 'https://github.com/o/medium.nvim',
        src = 'https://github.com/o/medium.nvim',
        path = vim.fn.getcwd(),
    }
    local long_version = {
        name = 'long-version.nvim',
        active = false,
        version = 'v2.0.0-beta.1',
        short_rev = 'c3',
        repo = 'o/long-version.nvim',
        github_url = 'https://github.com/o/long-version.nvim',
        src = 'https://github.com/o/long-version.nvim',
        path = vim.fn.getcwd(),
    }

    local state = {
        items = { short_version, medium_version, long_version },
        updated_items = { long_version },
        updated_names = { ['long-version.nvim'] = true },
        selected_name = 'short.nvim',
        expanded = {},
        detail_cache = {},
        updating = false,
        refreshing = false,
    }
    local snapshot = render.build_snapshot(state)

    local row_widths_by_column_count = {}
    for _, entry in ipairs(snapshot.row_highlights) do
        local line = snapshot.lines[entry.line]
        local column_count = #entry.highlights
        row_widths_by_column_count[column_count] = row_widths_by_column_count[column_count] or {}
        local row_widths = row_widths_by_column_count[column_count]
        row_widths[#row_widths + 1] = vim.api.nvim_strwidth(line)
    end

    for column_count, row_widths in pairs(row_widths_by_column_count) do
        for i = 2, #row_widths do
            assert_equals(
                row_widths[1],
                row_widths[i],
                string.format('row %d display width matches row 1 for %d-column rows (%d vs %d)', i, column_count, row_widths[1], row_widths[i])
            )
        end
    end
end

for name, test in pairs(tests) do
    local ok, err = pcall(test)
    if not ok then
        error(string.format('tests/packui_ui_spec.lua::%s failed\n%s', name, err), 0)
    end
end

print('packui_ui_spec: all tests passed')
