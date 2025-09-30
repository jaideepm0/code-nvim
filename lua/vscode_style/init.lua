-- VSCode-style insert mode editing for Neovim
-- Provides flexible, non-opinionated VSCode-like keybindings in insert mode

local M = {}

local utils = require('vscode_style.utils')
local config_module = require('vscode_style.config')
local actions = require('vscode_style.actions')
local multi_cursor = require('vscode_style.multi_cursor')

-- Plugin state
local state = {
  ns = nil,
  cursors = {},
  config = nil,
  autocmd_group = nil,
  snapshots = {},
  backspace_mapped = false,
  initialized = false,
}

--- Set up keymappings based on configuration
local function set_mappings()
  local config = state.config
  
  -- Skip if default keymaps are disabled
  if not config.enable_default_keymaps then
    config_module.log(config, 'Default keymaps disabled', 'info')
    return
  end
  
  -- Helper to create mapping if enabled
  local function map_if_enabled(action_name, handler, opts)
    opts = opts or {}
    
    -- Check if this action is enabled
    if not config_module.is_keymap_enabled(config, action_name) then
      config_module.log(config, string.format('Keymap disabled: %s', action_name), 'debug')
      return false
    end
    
    local key = config_module.get_keymap(config, action_name)
    if not key then
      return false
    end
    
    -- Check if we should respect existing mappings
    if config.respect_existing_maps and utils.keymap_exists(key, 'i') then
      config_module.log(config, string.format('Keymap exists, skipping: %s -> %s', action_name, key), 'debug')
      return false
    end
    
    -- Set default options
    opts.silent = opts.silent ~= false
    opts.buffer = opts.buffer or nil
    
    vim.keymap.set('i', key, handler, opts)
    config_module.log(config, string.format('Mapped: %s -> %s', key, action_name), 'debug')
    return true
  end
  
  -- Check if feature is enabled
  local function feature_enabled(feature_name)
    return config_module.is_feature_enabled(config, feature_name)
  end
  
  -- Core selection and cursor movement
  if feature_enabled('selection') then
    map_if_enabled('select_character_left', function()
      actions.select_character('left')
    end)
    
    map_if_enabled('select_character_right', function()
      actions.select_character('right')
    end)
    
    map_if_enabled('select_line_up', function()
      actions.select_line('up')
    end)
    
    map_if_enabled('select_line_down', function()
      actions.select_line('down')
    end)
    
    map_if_enabled('select_word_left', function()
      actions.select_word('left')
    end)
    
    map_if_enabled('select_word_right', function()
      actions.select_word('right')
    end)
    
    map_if_enabled('select_to_line_start', function()
      actions.select_to_line_boundary('home')
    end)
    
    map_if_enabled('select_to_line_end', function()
      actions.select_to_line_boundary('end')
    end)
    
    map_if_enabled('select_to_file_start', function()
      actions.select_to_file_boundary('home')
    end)
    
    map_if_enabled('select_to_file_end', function()
      actions.select_to_file_boundary('end')
    end)
  end
  
  -- Tab handling
  if config.tab_indents_selection then
    map_if_enabled('handle_tab', function()
      actions.handle_tab()
    end)
    
    map_if_enabled('handle_shift_tab', function()
      actions.handle_shift_tab()
    end)
  end
  
  -- Backspace handling
  if config.backspace_deletes_selection then
    -- Try to map backspace with expression mode
    local bs_mapped = map_if_enabled('handle_backspace', function()
      return actions.backspace_expr()
    end, { expr = true })
    
    if bs_mapped then
      state.backspace_mapped = true
      config_module.log(config, 'Backspace mapped with expr mode', 'debug')
    end
    
    -- Also try Ctrl+h
    local ch_mapped = map_if_enabled('handle_backspace_ctrl', function()
      return actions.backspace_expr()
    end, { expr = true })
    
    if ch_mapped then
      state.backspace_mapped = true
      config_module.log(config, 'Ctrl+h mapped with expr mode', 'debug')
    end
    
    -- If neither mapped, fall back to InsertCharPre autocmd
    if not state.backspace_mapped then
      config_module.log(config, 'Using InsertCharPre fallback for backspace', 'debug')
    end
  end
  
  -- Line and block manipulation
  if feature_enabled('line_manipulation') then
    map_if_enabled('move_line_up', function()
      actions.move_line('up')
    end)
    
    map_if_enabled('move_line_down', function()
      actions.move_line('down')
    end)
    
    map_if_enabled('copy_line_up', function()
      actions.copy_line('up')
    end)
    
    map_if_enabled('copy_line_down', function()
      actions.copy_line('down')
    end)
    
    map_if_enabled('delete_line', function()
      actions.delete_line()
    end)
  end
  
  -- Multi-cursor and column selection
  if feature_enabled('multi_cursor') then
    map_if_enabled('alt_click', function()
      actions.alt_click_cursor()
    end)
    
    map_if_enabled('add_cursor_up', function()
      actions.add_cursor_vertical('up')
    end)
    
    map_if_enabled('add_cursor_down', function()
      actions.add_cursor_vertical('down')
    end)
    
    map_if_enabled('add_cursor_next_match', function()
      actions.add_selection_to_next_match()
    end)
    
    map_if_enabled('select_all_occurrences', function()
      actions.select_all_occurrences()
    end)
    
    map_if_enabled('expand_selection', function()
      actions.expand_selection()
    end)
    
    map_if_enabled('shrink_selection', function()
      actions.shrink_selection()
    end)
  end
  
  -- Column selection
  if feature_enabled('column_selection') then
    map_if_enabled('column_selection_start', function()
      actions.column_selection_drag_start()
    end)
    
    map_if_enabled('column_selection_end', function()
      actions.column_selection_drag_end()
    end)
  end
  
  -- Map any custom actions
  if config.actions then
    for action_name, action_fn in pairs(config.actions) do
      local key = config.keymaps[action_name]
      if key and type(action_fn) == 'function' then
        vim.keymap.set('i', key, action_fn, { silent = true })
        config_module.log(config, string.format('Mapped custom action: %s -> %s', key, action_name), 'info')
      end
    end
  end
end

--- Set up autocommands
local function setup_autocommands()
  local config = state.config
  
  -- Clear existing autocommands
  if state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
  end
  
  state.autocmd_group = vim.api.nvim_create_augroup('VscodeStyleInsert', { clear = true })
  
  -- InsertCharPre for typing replacement
  if config.typing_replaces_selection then
    vim.api.nvim_create_autocmd('InsertCharPre', {
      group = state.autocmd_group,
      callback = function()
        if not utils.is_enabled_for_buffer(config) then
          return
        end
        actions.on_insert_pre()
      end,
    })
  end
  
  -- InsertLeave to clear selections
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = state.autocmd_group,
    callback = function()
      if not utils.is_enabled_for_buffer(config) then
        return
      end
      multi_cursor.save_snapshot()
      multi_cursor.clear_all_selections()
      multi_cursor.update_highlights()
      
      -- Execute callback
      config_module.execute_callback(config, 'on_leave_insert')
    end,
  })
  
  -- BufEnter to switch buffers
  vim.api.nvim_create_autocmd('BufEnter', {
    group = state.autocmd_group,
    callback = function()
      multi_cursor.switch_buffer()
    end,
  })
  
  -- InsertEnter to restore snapshot
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = state.autocmd_group,
    callback = function()
      if not utils.is_enabled_for_buffer(config) then
        return
      end
      multi_cursor.restore_snapshot()
      
      -- Execute callback
      config_module.execute_callback(config, 'on_enter_insert')
    end,
  })
  
  -- Buffer cleanup
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    group = state.autocmd_group,
    callback = function(args)
      multi_cursor.clear_snapshot(args.buf)
    end,
  })
  
  config_module.log(config, 'Autocommands configured', 'debug')
end

--- Main setup function
---@param user_config table|nil User configuration
function M.setup(user_config)
  -- Merge configuration with defaults
  state.config = config_module.merge(user_config)
  local config = state.config
  
  -- Check if plugin is enabled
  if not config.enabled then
    config_module.log(config, 'Plugin disabled by configuration', 'info')
    return
  end
  
  -- Log setup start
  config_module.log(config, 'Setting up vscode_style plugin...', 'info')
  
  -- Preserve buffer modified state
  local buf = vim.api.nvim_get_current_buf()
  local was_modified = false
  if vim.api.nvim_buf_is_valid(buf) then
    was_modified = vim.api.nvim_buf_get_option(buf, 'modified')
  end
  
  -- Create namespace with configured name
  if not state.ns then
    state.ns = vim.api.nvim_create_namespace(config.namespace or 'vscode_style')
    config_module.log(config, string.format('Created namespace: %s', config.namespace), 'debug')
  end
  
  -- Initialize state
  state.cursors = {}
  state.column_selecting = false
  state.column_anchor = nil
  
  -- Initialize modules
  multi_cursor.setup(state)
  actions.setup(state, multi_cursor)
  
  -- Set up autocommands
  setup_autocommands()
  
  -- Set up keymappings
  set_mappings()
  
  -- Restore buffer modified state
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_set_option, buf, 'modified', was_modified)
  end
  
  -- Execute on_setup callback
  config_module.execute_callback(config, 'on_setup')
  
  state.initialized = true
  config_module.log(config, 'Plugin setup complete', 'info')
end

--- Get current plugin state (for debugging/testing)
---@return table State
function M.get_state()
  return state
end

--- Check if plugin is initialized
---@return boolean
function M.is_initialized()
  return state.initialized
end

--- Enable plugin for current buffer
function M.enable()
  vim.b.vscode_style_enabled = true
  config_module.log(state.config, 'Plugin enabled for current buffer', 'info')
end

--- Disable plugin for current buffer
function M.disable()
  vim.b.vscode_style_enabled = false
  multi_cursor.clear_all_selections()
  multi_cursor.update_highlights()
  config_module.log(state.config, 'Plugin disabled for current buffer', 'info')
end

--- Toggle plugin for current buffer
function M.toggle()
  local enabled = vim.b.vscode_style_enabled
  if enabled == nil then
    enabled = utils.is_enabled_for_buffer(state.config)
  end
  
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

--- Reload configuration
---@param user_config table|nil New configuration
function M.reload(user_config)
  config_module.log(state.config, 'Reloading plugin...', 'info')
  
  -- Clear current mappings
  if state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
  end
  
  -- Re-setup with new config
  M.setup(user_config)
end

--- Get current configuration
---@return table Configuration
function M.get_config()
  return state.config
end

--- Get cursor count for statusline
---@return string Formatted cursor count
function M.get_cursor_count()
  if not state.config or not state.config.show_cursor_count then
    return ''
  end
  
  local count = #state.cursors
  if count <= 1 then
    return ''
  end
  
  return string.format(state.config.cursor_count_format or 'Cursors: %d', count)
end

return M
