-- Configuration management for vscode_style plugin
local M = {}
local utils = require('vscode_style.utils')

--- Default configuration
M.defaults = {
  -- Core settings
  enabled = true,
  selection_hl = 'Visual',
  max_cursors = 32,
  namespace = 'vscode_style',
  
  -- Buffer-local settings
  buffer_local = false,
  exclude_filetypes = {},
  include_filetypes = {},
  
  -- Feature toggles
  features = {
    selection = true,
    multi_cursor = true,
    line_manipulation = true,
    column_selection = true,
  },
  
  -- Keybinding control
  enable_default_keymaps = true,
  respect_existing_maps = false,
  disable_keymaps = {},
  
  -- Custom keymaps (action_name = key or false to disable)
  keymaps = {},
  
  -- Behavior customization
  backspace_deletes_selection = true,
  tab_indents_selection = true,
  typing_replaces_selection = true,
  
  -- Visual feedback
  show_cursor_count = false,
  cursor_count_format = 'Cursors: %d',
  cursor_count_hl = 'Comment',
  
  -- Callbacks/Hooks
  on_setup = nil,
  on_cursor_add = nil,
  on_cursor_remove = nil,
  on_selection_change = nil,
  on_enter_insert = nil,
  on_leave_insert = nil,
  
  -- Custom actions and overrides
  actions = {},
  action_overrides = {},
  
  -- Advanced
  debug = false,
  log_level = 'warn',
}

--- Default keymaps (action_name = key)
M.default_keymaps = {
  -- Core selection and cursor movement
  select_character_left = '<S-Left>',
  select_character_right = '<S-Right>',
  select_line_up = '<S-Up>',
  select_line_down = '<S-Down>',
  select_word_left = '<C-S-Left>',
  select_word_right = '<C-S-Right>',
  select_to_line_start = '<S-Home>',
  select_to_line_end = '<S-End>',
  select_to_file_start = '<C-S-Home>',
  select_to_file_end = '<C-S-End>',
  handle_tab = '<Tab>',
  handle_shift_tab = '<S-Tab>',
  handle_backspace = '<BS>',
  handle_backspace_ctrl = '<C-h>',
  
  -- Line and block manipulation
  move_line_up = '<M-Up>',
  move_line_down = '<M-Down>',
  copy_line_up = '<S-M-Up>',
  copy_line_down = '<S-M-Down>',
  delete_line = '<C-S-k>',
  
  -- Multi-cursor and column selection
  alt_click = '<M-LeftMouse>',
  add_cursor_up = '<C-M-Up>',
  add_cursor_down = '<C-M-Down>',
  add_cursor_next_match = '<C-d>',
  select_all_occurrences = '<C-S-l>',
  expand_selection = '<S-M-Right>',
  shrink_selection = '<S-M-Left>',
  column_selection_start = '<S-M-LeftDrag>',
  column_selection_end = '<S-M-LeftRelease>',
}

--- Merge user config with defaults
---@param user_config table|nil User configuration
---@return table Merged configuration
function M.merge(user_config)
  if not user_config then
    return vim.deepcopy(M.defaults)
  end
  
  -- Validate configuration
  local valid, err = utils.validate_config(user_config)
  if not valid then
    vim.notify(
      string.format('Invalid configuration: %s. Using defaults.', err),
      vim.log.levels.ERROR
    )
    return vim.deepcopy(M.defaults)
  end
  
  -- Deep merge with defaults
  local config = utils.deep_merge(M.defaults, user_config)
  
  -- Normalize disable_keymaps to a set for fast lookup
  if config.disable_keymaps then
    local disabled_set = {}
    for _, key in ipairs(config.disable_keymaps) do
      disabled_set[key] = true
    end
    config._disabled_keymaps_set = disabled_set
  end
  
  return config
end

--- Check if a keymap action is enabled
---@param config table Configuration
---@param action_name string Action name
---@return boolean enabled
function M.is_keymap_enabled(config, action_name)
  -- Check if action is explicitly disabled in custom keymaps
  if config.keymaps[action_name] == false then
    return false
  end
  
  -- Get the key for this action
  local key = config.keymaps[action_name] or M.default_keymaps[action_name]
  
  -- Check if this key is in the disable list
  if key and config._disabled_keymaps_set and config._disabled_keymaps_set[key] then
    return false
  end
  
  return true
end

--- Get the key for a keymap action
---@param config table Configuration
---@param action_name string Action name
---@return string|nil key
function M.get_keymap(config, action_name)
  -- Return custom keymap if specified
  if config.keymaps[action_name] then
    return config.keymaps[action_name]
  end
  
  -- Return default keymap
  return M.default_keymaps[action_name]
end

--- Check if a feature is enabled
---@param config table Configuration
---@param feature_name string Feature name
---@return boolean enabled
function M.is_feature_enabled(config, feature_name)
  if not config.features then
    return true
  end
  
  local enabled = config.features[feature_name]
  if enabled == nil then
    return true
  end
  
  return enabled
end

--- Execute a callback if defined
---@param config table Configuration
---@param callback_name string Callback name (e.g., 'on_cursor_add')
---@param ... any Arguments to pass to callback
---@return boolean success
function M.execute_callback(config, callback_name, ...)
  local callback = config[callback_name]
  return utils.safe_callback(callback, ...)
end

--- Get custom action if defined
---@param config table Configuration
---@param action_name string Action name
---@return function|nil action
function M.get_custom_action(config, action_name)
  return config.actions and config.actions[action_name]
end

--- Get action override if defined
---@param config table Configuration
---@param action_name string Action name
---@return function|nil override
function M.get_action_override(config, action_name)
  return config.action_overrides and config.action_overrides[action_name]
end

--- Log debug message if debug mode is enabled
---@param config table Configuration
---@param message string Message to log
---@param level string|nil Log level ('trace', 'debug', 'info', 'warn', 'error')
function M.log(config, message, level)
  level = level or 'debug'
  
  if not config.debug and level == 'debug' then
    return
  end
  
  local log_levels = {
    trace = vim.log.levels.TRACE,
    debug = vim.log.levels.DEBUG,
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
  }
  
  local vim_level = log_levels[level] or vim.log.levels.INFO
  
  -- Check if we should log based on configured log level
  local level_order = { trace = 1, debug = 2, info = 3, warn = 4, error = 5 }
  local current_level = level_order[config.log_level] or 4
  local msg_level = level_order[level] or 3
  
  if msg_level >= current_level then
    vim.notify('[vscode_style] ' .. message, vim_level)
  end
end

return M
