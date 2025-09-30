local M = {}

local default_config = {
  selection_hl = 'Visual',
  max_cursors = 32,
  mappings = {
    -- How to set mappings: 'respect' (only if unmapped), 'force' (override), 'skip' (no mappings)
    strategy = 'respect',
    -- Enable/disable groups
    selection = true,        -- Shift+Arrows, Ctrl+Shift+Arrows, Home/End, file boundaries
    line_ops = true,         -- Alt+Up/Down, Shift+Alt+Up/Down, Ctrl+Shift+K
    multi_cursor = true,     -- Alt+Click, Ctrl+Alt+Up/Down, Ctrl+D, Ctrl+Shift+L
    column_selection = true, -- Shift+Alt+Drag/Release
    tab = true,              -- Tab/Shift+Tab indent/dedent for selections
    backspace = true,        -- Backspace over active selections
  },
}

local state = {
  ns = nil,
  cursors = {},
  config = default_config,
  autocmd_group = nil,
  snapshots = {},
  backspace_mapped = false,
}

local actions = require('vscode_style.actions')
local multi_cursor = require('vscode_style.multi_cursor')

local function apply_config(user_config)
  if not user_config then
    state.config = vim.tbl_extend('force', {}, default_config)
    return
  end
  state.config = vim.tbl_extend('force', {}, default_config, user_config or {})
end

local function set_mappings()
  local map = function(lhs, rhs, opts)
    opts = opts or {}
    opts.silent = opts.silent ~= false
    vim.keymap.set('i', lhs, rhs, opts)
  end

  local map_if_unmapped = function(lhs, rhs, opts)
    if vim.fn.maparg(lhs, 'i') ~= '' then
      return false
    end
    map(lhs, rhs, opts)
    return true
  end

  local strategy = (state.config.mappings and state.config.mappings.strategy) or 'respect'
  local try_map = function(lhs, rhs, opts)
    if strategy == 'skip' then return end
    if strategy == 'respect' then
      map_if_unmapped(lhs, rhs, opts)
    else
      map(lhs, rhs, opts)
    end
  end

  -- Core selection and cursor movement
  if state.config.mappings.selection ~= false then
    try_map('<S-Left>', function() actions.select_character('left') end)
    try_map('<S-Right>', function() actions.select_character('right') end)
    try_map('<S-Up>', function() actions.select_line('up') end)
    try_map('<S-Down>', function() actions.select_line('down') end)
    try_map('<C-S-Left>', function() actions.select_word('left') end)
    try_map('<C-S-Right>', function() actions.select_word('right') end)
    try_map('<S-Home>', function() actions.select_to_line_boundary('home') end)
    try_map('<S-End>', function() actions.select_to_line_boundary('end') end)
    try_map('<C-S-Home>', function() actions.select_to_file_boundary('home') end)
    try_map('<C-S-End>', function() actions.select_to_file_boundary('end') end)
  end
  if state.config.mappings.tab ~= false then
    try_map('<Tab>', function() actions.handle_tab() end)
    try_map('<S-Tab>', function() actions.handle_shift_tab() end)
  end
  if state.config.mappings.backspace ~= false then
    local did = false
    if strategy == 'respect' then
      if map_if_unmapped('<BS>', function() return actions.backspace_expr() end, { expr = true }) then did = true end
      if map_if_unmapped('<C-h>', function() return actions.backspace_expr() end, { expr = true }) then did = true end
    elseif strategy == 'force' then
      map('<BS>', function() return actions.backspace_expr() end, { expr = true }); did = true
      map('<C-h>', function() return actions.backspace_expr() end, { expr = true }); did = true
    end
    state.backspace_mapped = did
  end

  -- Line and block manipulation
  if state.config.mappings.line_ops ~= false then
    try_map('<M-Up>', function() actions.move_line('up') end)
    try_map('<M-Down>', function() actions.move_line('down') end)
    try_map('<S-M-Up>', function() actions.copy_line('up') end)
    try_map('<S-M-Down>', function() actions.copy_line('down') end)
    try_map('<C-S-k>', function() actions.delete_line() end, { expr = false })
  end

  -- Multi-cursor and column selection
  if state.config.mappings.multi_cursor ~= false then
    try_map('<M-LeftMouse>', function() actions.alt_click_cursor() end)
    try_map('<C-M-Up>', function() actions.add_cursor_vertical('up') end)
    try_map('<C-M-Down>', function() actions.add_cursor_vertical('down') end)
    try_map('<C-d>', function() actions.add_selection_to_next_match() end)
    try_map('<C-S-l>', function() actions.select_all_occurrences() end)
    try_map('<S-M-Right>', function() actions.expand_selection() end)
    try_map('<S-M-Left>', function() actions.shrink_selection() end)
  end
  if state.config.mappings.column_selection ~= false then
    try_map('<S-M-LeftDrag>', function() actions.column_selection_drag_start() end)
    try_map('<S-M-LeftRelease>', function() actions.column_selection_drag_end() end)
  end
end

function M.setup(user_config)
  local buf = vim.api.nvim_get_current_buf()
  local was_modified = vim.api.nvim_buf_get_option(buf, 'modified')

  apply_config(user_config)

  if not state.ns then
    state.ns = vim.api.nvim_create_namespace('vscode_style')
  end

  state.cursors = {}
  state.column_selecting = false
  state.column_anchor = nil

  multi_cursor.setup(state)
  actions.setup(state, multi_cursor)
  if state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
  end
  state.autocmd_group = vim.api.nvim_create_augroup('VscodeStyleInsert', { clear = true })
  vim.api.nvim_create_autocmd('InsertCharPre', {
    group = state.autocmd_group,
    callback = function()
      actions.on_insert_pre()
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = state.autocmd_group,
    callback = function()
      multi_cursor.save_snapshot()
      multi_cursor.clear_all_selections()
      multi_cursor.update_highlights()
    end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = state.autocmd_group,
    callback = function()
      multi_cursor.switch_buffer()
    end,
  })
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = state.autocmd_group,
    callback = function()
      multi_cursor.restore_snapshot()
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    group = state.autocmd_group,
    callback = function(args)
      multi_cursor.clear_snapshot(args.buf)
    end,
  })
  set_mappings()

  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_set_option, buf, 'modified', was_modified)
  end
end

function M.get_state()
  return state
end

return M
