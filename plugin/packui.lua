vim.api.nvim_create_user_command('PackUI', function()
    require('packui').open()
end, { desc = 'Open vim.pack manager UI' })
