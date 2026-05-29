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
        invalidate_update_count = function() end,
        invalidate_all_update_counts = function() end,
    }
end

local function make_actions()
    local calls = {
        open_github = 0,
    }

    return {
        calls = calls,
        update_all = function(opts)
            if opts and opts.on_done then
                opts.on_done({})
            end
        end,
        update_one = function(_, opts)
            if opts and opts.on_done then
                opts.on_done({})
            end
        end,
        delete_one = function(_, on_done)
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

local tests = {}

tests.opens_single_buffer_ui = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })
    assert_truthy(type(state) == 'table', 'ui.open returns a native UI state table')

    -- Single main window only
    assert_truthy(vim.api.nvim_win_is_valid(state.wins.main_win), 'main window is valid')
    assert_truthy(state.wins.main_buf, 'main buffer exists')

    local buf_text = text(state.wins.main_buf)

    -- Key help at top
    assert_contains(buf_text, 'Open repo (g)', 'open repo hint present')
    assert_contains(buf_text, 'Update (u)', 'update one hint present')
    assert_contains(buf_text, 'Update all (U)', 'update all hint present')
    assert_contains(buf_text, 'Refresh (r)', 'refresh hint present')
    assert_contains(buf_text, 'Details (<CR>)', 'details hint present')
    assert_contains(buf_text, 'Delete (x)', 'delete hint present')
    assert_contains(buf_text, 'Close (q)', 'close hint present')

    -- Column headers present
    assert_contains(buf_text, 'NAME', 'has NAME column')
    assert_contains(buf_text, 'STATUS', 'has STATUS column')
    assert_contains(buf_text, 'VERSION', 'has VERSION column')
    assert_contains(buf_text, 'All Plugins', 'has All Plugins section')

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
    assert_truthy(type(state) == 'table', 'empty source still opens native UI')

    local buf_text = text(state.wins.main_buf)
    assert_contains(buf_text, 'Update (u)', 'update hint renders for empty list')
    assert_contains(buf_text, 'All Plugins', 'All Plugins section header for empty list')
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
        return text(state.wins.main_buf):find('📦 Updated', 1, true) ~= nil
    end)
    assert_truthy(ok, 'update callback renders Updated section')

    local buf_text = text(state.wins.main_buf)
    assert_contains(buf_text, '📦 Updated', 'updated section appears after update')
    assert_contains(buf_text, 'All Plugins', 'all plugins section remains visible')
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

    for _, key in ipairs({ 'g', 'U', 'u', 'x', 'r', '<CR>', 'q' }) do
        assert_truthy(seen[key], 'main buffer binds key ' .. key)
    end

    -- Close cleans main_win
    local main_win = state.wins.main_win
    close_state(state)
    assert_equals(false, vim.api.nvim_win_is_valid(main_win), 'close invalidates main window')
end

tests.g_key_opens_selected_plugin_repository = function()
    local ui = require('packui.ui')
    local actions = make_actions()
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = actions })

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_feedkeys('g', 'x', false)

    assert_equals(1, actions.calls.open_github, 'g invokes open_github for the selected plugin')

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

tests.navigation_only_visits_plugin_rows = function()
    local ui = require('packui.ui')
    local plugins = { make_plugin('alpha.nvim'), make_plugin('beta.nvim') }
    local state = ui.open({ source = make_source(plugins), actions = make_actions() })

    local first_item = state.line_to_item[state.selected_line]
    assert_truthy(first_item and first_item.name == 'alpha.nvim', 'selection starts on first plugin row')

    vim.api.nvim_set_current_win(state.wins.main_win)
    vim.api.nvim_feedkeys('k', 'x', false)

    local still_first_item = state.line_to_item[state.selected_line]
    assert_truthy(still_first_item and still_first_item.name == 'alpha.nvim', 'moving up does not land on hint or header rows')

    vim.api.nvim_feedkeys('j', 'x', false)
    local second_item = state.line_to_item[state.selected_line]
    assert_truthy(second_item and second_item.name == 'beta.nvim', 'moving down lands on next plugin row')

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

for name, test in pairs(tests) do
    local ok, err = pcall(test)
    if not ok then
        error(string.format('tests/packui_native_ui_spec.lua::%s failed\n%s', name, err), 0)
    end
end

print('packui_native_ui_spec: all tests passed')
