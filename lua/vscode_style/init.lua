local M = {}

local default_config = {
  selection_hl = 'Visual',
  max_cursors = 32,
}

local state = {
  ns = nil,
  cursors = {},
  config = default_config,
  autocmd_group = nil,
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

  -- Core selection and cursor movement
  map('<S-Left>', function()
    actions.select_character('left')
  end)
  map('<S-Right>', function()
    actions.select_character('right')
  end)
  map('<S-Up>', function()
    actions.select_line('up')
  end)
  map('<S-Down>', function()
    actions.select_line('down')
  end)
  map('<C-S-Left>', function()
    actions.select_word('left')
  end)
  map('<C-S-Right>', function()
    actions.select_word('right')
  end)
  map('<S-Home>', function()
    actions.select_to_line_boundary('home')
  end)
  map('<S-End>', function()
    actions.select_to_line_boundary('end')
  end)
  map('<C-S-Home>', function()
    actions.select_to_file_boundary('home')
  end)
  map('<C-S-End>', function()
    actions.select_to_file_boundary('end')
  end)
  map('<BS>', function()
    actions.handle_backspace()
  end)
  map('<Tab>', function()
    actions.handle_tab()
  end)
  map('<S-Tab>', function()
    actions.handle_shift_tab()
  end)

  -- Line and block manipulation
  map('<M-Up>', function()
    actions.move_line('up')
  end)
  map('<M-Down>', function()
    actions.move_line('down')
  end)
  map('<S-M-Up>', function()
    actions.copy_line('up')
  end)
  map('<S-M-Down>', function()
    actions.copy_line('down')
  end)
  map('<C-S-k>', function()
    actions.delete_line()
  end, { expr = false })

  -- Multi-cursor and column selection
  map('<M-LeftMouse>', function()
    actions.alt_click_cursor()
  end)
  map('<C-M-Up>', function()
    actions.add_cursor_vertical('up')
  end)
  map('<C-M-Down>', function()
    actions.add_cursor_vertical('down')
  end)
  map('<C-d>', function()
    actions.add_selection_to_next_match()
  end)
  map('<C-S-l>', function()
    actions.select_all_occurrences()
  end)
  map('<S-M-Right>', function()
    actions.expand_selection()
  end)
  map('<S-M-Left>', function()
    actions.shrink_selection()
  end)
  map('<S-M-LeftDrag>', function()
    actions.column_selection_drag_start()
  end)
  map('<S-M-LeftRelease>', function()
    actions.column_selection_drag_end()
  end)
end

function M.setup(user_config)
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
      actions.on_insert_char_pre(vim.v.char, vim.v.key)
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = state.autocmd_group,
    callback = function()
      multi_cursor.clear_all_selections()
      multi_cursor.update_highlights()
    end,
  })
  set_mappings()
end

function M.get_state()
  return state
end

return M
