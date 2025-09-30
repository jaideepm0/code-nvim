-- Auto-loader for code-nvim plugin
-- This file is sourced automatically by Neovim

-- Prevent loading twice
if vim.g.loaded_code_nvim then
  return
end
vim.g.loaded_code_nvim = 1

-- Note: Actual setup is deferred until user calls require('vscode_style').setup()
-- or require('code-nvim').setup()
-- This allows users to configure the plugin before initialization
