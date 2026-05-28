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
        path = 'C:/plugins/' .. name,
        preview = {
            text = table.concat({
                '# PackUI: ' .. name,
                '',
                '## Keys',
                '- `g`: open GitHub repository',
                '- `U`: update all plugins',
                '',
                '## Details',
                '- **Commit**: abcdef12',
                '- **Repo**: owner/' .. name,
            }, '\n'),
            ft = 'markdown',
            loc = false,
        },
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
    return {
        update_all = function(on_done)
            if on_done then
                on_done()
            end
        end,
        update_one = function(_, on_done)
            if on_done then
                on_done()
            end
        end,
        delete_one = function(_, on_done)
            if on_done then
                on_done()
            end
        end,
        open_github = function() end,
    }
end

local function text(buf)
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

local function close_state(state)
    if state and state.close then
        state.close()
    end
end

local tests = {}

tests.opens_native_three_panel_ui = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })
    assert_truthy(type(state) == 'table', 'ui.open returns a native UI state table')

    assert_truthy(vim.api.nvim_win_is_valid(state.wins.list_win), 'list window is valid')
    assert_truthy(vim.api.nvim_win_is_valid(state.wins.detail_win), 'detail window is valid')
    assert_truthy(vim.api.nvim_win_is_valid(state.wins.footer_win), 'footer window is valid')

    local list_text = text(state.wins.list_buf)
    assert_contains(list_text, 'NAME', 'list has NAME column')
    assert_contains(list_text, 'STATUS', 'list has STATUS column')
    assert_contains(list_text, 'VERSION', 'list has VERSION column')
    assert_not_contains(list_text, 'COMMIT', 'left list omits commit column')
    assert_not_contains(list_text, 'UPDATES', 'left list omits updates column')
    assert_not_contains(list_text, 'REPO', 'left list omits repo column')

    local detail_text = text(state.wins.detail_buf)
    assert_contains(detail_text, '## Keys', 'detail panel shows key help')
    assert_contains(detail_text, '- `U`: update all plugins', 'detail panel shows update-all key')
    assert_contains(detail_text, '- **Commit**: abcdef12', 'detail panel keeps full plugin details')

    close_state(state)
end

tests.handles_empty_plugin_list = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({}), actions = make_actions() })
    assert_truthy(type(state) == 'table', 'empty source still opens native UI')

    assert_contains(text(state.wins.list_buf), 'No plugins found', 'empty list renders an empty state')
    assert_contains(text(state.wins.detail_buf), 'Select a plugin', 'empty detail panel tells user what to do')
    assert_contains(text(state.wins.footer_buf), 'g: GitHub', 'footer still renders key help')

    close_state(state)
end

tests.binds_actions_and_cleans_up = function()
    local ui = require('packui.ui')
    local state = ui.open({ source = make_source({ make_plugin('alpha.nvim') }), actions = make_actions() })
    assert_truthy(type(state) == 'table', 'ui.open returns state for keymap test')

    local keymaps = vim.api.nvim_buf_get_keymap(state.wins.list_buf, 'n')
    local seen = {}
    for _, keymap in ipairs(keymaps) do
        seen[keymap.lhs] = keymap.desc or true
    end

    for _, key in ipairs({ 'g', 'U', 'u', 'x', 'r', '<CR>', 'q' }) do
        assert_truthy(seen[key], 'list buffer binds key ' .. key)
    end

    local list_win = state.wins.list_win
    local detail_win = state.wins.detail_win
    local footer_win = state.wins.footer_win
    close_state(state)

    assert_equals(false, vim.api.nvim_win_is_valid(list_win), 'close invalidates list window')
    assert_equals(false, vim.api.nvim_win_is_valid(detail_win), 'close invalidates detail window')
    assert_equals(false, vim.api.nvim_win_is_valid(footer_win), 'close invalidates footer window')
end

for name, test in pairs(tests) do
    local ok, err = pcall(test)
    if not ok then
        error(string.format('tests/packui_native_ui_spec.lua::%s failed\n%s', name, err), 0)
    end
end

print('packui_native_ui_spec: all tests passed')
