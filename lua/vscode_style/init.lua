local config_module = require('vscode_style.config')
local actions = require('vscode_style.actions')
local multi_cursor = require('vscode_style.multi_cursor')

local M = {}

local unpack = table.unpack or unpack

local state = {
  ns = nil,
  cursors = {},
  config = nil,
  autocmd_group = nil,
  snapshots = {},
  applied_keymaps = {},
  keymap_restore = {},
}

local function notify(level, msg)
  local fn
  if state and state.config then
    if state.config.notify == false then
      return
    elseif state.config.notify ~= nil then
      fn = state.config.notify
    end
  end
  fn = fn or vim.notify
  if not fn then
    return
  end
  pcall(fn, msg, level or vim.log.levels.INFO)
end

local function apply_config(user_config)
  state.config = config_module.normalize(user_config)
end

local function clear_keymaps()
  if not state.applied_keymaps then
    state.applied_keymaps = {}
    return
  end
  for _, entry in ipairs(state.applied_keymaps) do
    local lhs = entry.lhs
    if lhs then
      local opts = entry.buffer and { buffer = entry.buffer } or nil
      pcall(vim.keymap.del, 'i', lhs, opts)
      local restore_key = entry.restore_key
      local restore = restore_key and state.keymap_restore and state.keymap_restore[restore_key]
      if restore then
        if entry.buffer and vim.api.nvim_buf_is_valid(entry.buffer) then
          pcall(vim.api.nvim_buf_call, entry.buffer, function()
            vim.fn.mapset('i', false, restore)
          end)
        elseif not entry.buffer then
          pcall(vim.fn.mapset, 'i', false, restore)
        end
        state.keymap_restore[restore_key] = nil
      end
    end
  end
  state.applied_keymaps = {}
end

local function record_applied_keymap(lhs, buffer, restore_key)
  table.insert(state.applied_keymaps, { lhs = lhs, buffer = buffer, restore_key = restore_key })
end

local function sanitize_buffer_option(buffer)
  if buffer == nil then
    return nil
  end
  if buffer == true or buffer == 0 then
    return vim.api.nvim_get_current_buf()
  end
  if type(buffer) == 'number' and vim.api.nvim_buf_is_valid(buffer) then
    return buffer
  end
  return nil
end

local function restore_key(lhs, buffer)
  if buffer then
    return string.format('buf:%d:%s', buffer, lhs)
  end
  return 'global:' .. lhs
end

local function buffer_local_maparg(bufnr, lhs)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end
  local ok, result = pcall(vim.api.nvim_buf_call, bufnr, function()
    local existing = vim.fn.maparg(lhs, 'i', false, true)
    if type(existing) == 'table' and existing.lhs ~= '' and existing.buffer == 1 then
      return existing
    end
    return nil
  end)
  if ok then
    return result
  end
  return nil
end

local function global_maparg(lhs)
  for _, existing in ipairs(vim.api.nvim_get_keymap('i')) do
    if existing.lhs == lhs then
      return existing
    end
  end
  return nil
end

local function has_any_insert_map(lhs, buffer)
  if buffer and buffer_local_maparg(buffer, lhs) then
    return true
  end
  return vim.fn.maparg(lhs, 'i') ~= ''
end

local function make_action_callback(spec)
  if not spec then
    return nil
  end
  if type(spec.callback) == 'function' then
    return spec.callback
  end
  if not spec.handler or not spec.handler.fn then
    return nil
  end
  local fn = actions[spec.handler.fn]
  if type(fn) ~= 'function' then
    notify(vim.log.levels.WARN, string.format('vscode_style: action %s is not defined', spec.handler.fn))
    return nil
  end
  local args = spec.handler.args and vim.deepcopy(spec.handler.args) or nil
  if not args or #args == 0 then
    return function()
      return fn()
    end
  end
  return function()
    return fn(unpack(args))
  end
end

local function apply_keymaps()
  clear_keymaps()

  if state.config.mapping_strategy == 'skip' then
    return
  end

  local strategy = state.config.mapping_strategy

  for _, name in ipairs(state.config.keymap_order) do
    local spec = state.config.keymaps[name]
    if spec and spec.enabled then
      local callback = make_action_callback(spec)
      if callback then
        for _, lhs in ipairs(spec.lhs) do
          local opts = vim.tbl_extend('force', {}, spec.opts or {})
          opts.desc = opts.desc or spec.description
          if opts.silent == nil then
            opts.silent = true
          end
          local buffer = sanitize_buffer_option(opts.buffer)
          if not buffer and opts.buf ~= nil then
            buffer = sanitize_buffer_option(opts.buf)
          end
          opts.buf = nil
          if buffer then
            opts.buffer = buffer
          else
            opts.buffer = nil
          end

          if strategy == 'respect' and has_any_insert_map(lhs, buffer) then
            goto continue
          end

          local key = restore_key(lhs, buffer)
          if strategy == 'force' then
            local existing = buffer and buffer_local_maparg(buffer, lhs) or global_maparg(lhs)
            if type(existing) == 'table' and existing.lhs ~= '' then
              state.keymap_restore[key] = state.keymap_restore[key] or existing
            end
          end

          local ok, err = pcall(vim.keymap.set, 'i', lhs, callback, opts)
          if ok then
            record_applied_keymap(lhs, buffer, key)
          else
            notify(vim.log.levels.WARN, string.format('vscode_style: failed to map %s (%s)', lhs, err))
          end
          ::continue::
        end
      end
    end
  end
end

local function setup_autocommands()
  if state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
    state.autocmd_group = nil
  end
  state.autocmd_group = vim.api.nvim_create_augroup('VscodeStyleInsert', { clear = true })

  if state.config.autocommands.insert_char_pre then
    vim.api.nvim_create_autocmd('InsertCharPre', {
      group = state.autocmd_group,
      callback = function()
        actions.on_insert_pre()
      end,
    })
  end

  if state.config.autocommands.insert_leave then
    vim.api.nvim_create_autocmd('InsertLeave', {
      group = state.autocmd_group,
      callback = function(args)
        M.deactivate_selection_keymaps(args.buf)
        multi_cursor.clear_all_selections()
        multi_cursor.update_highlights()
      end,
    })
  end

  if state.config.autocommands.buf_enter then
    vim.api.nvim_create_autocmd('BufLeave', {
      group = state.autocmd_group,
      callback = function(args)
        M.deactivate_selection_keymaps(args.buf)
      end,
    })
    vim.api.nvim_create_autocmd('BufEnter', {
      group = state.autocmd_group,
      callback = function()
        multi_cursor.switch_buffer()
      end,
    })
  end

  if state.config.autocommands.cursor_moved_i then
    vim.api.nvim_create_autocmd('CursorMovedI', {
      group = state.autocmd_group,
      callback = function()
        actions.on_cursor_moved_i()
      end,
    })
  end

  -- insert_enter and buf_cleanup hooks are intentionally no-ops in this revision
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

  setup_autocommands()
  apply_keymaps()

  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_set_option, buf, 'modified', was_modified)
  end
end

function M.get_state()
  return state
end

local selection_keymaps_active = {}
local selection_keymap_restore = {}

local function set_selection_delete_keymap(bufnr, lhs)
  local restore = buffer_local_maparg(bufnr, lhs)
  if restore then
    selection_keymap_restore[bufnr] = selection_keymap_restore[bufnr] or {}
    selection_keymap_restore[bufnr][lhs] = restore
  end
  vim.keymap.set('i', lhs, function()
    require('vscode_style.actions').delete_selection_and_cleanup()
  end, { buffer = bufnr, silent = true })
end

function M.activate_selection_keymaps(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if selection_keymaps_active[bufnr] then
    return
  end
  set_selection_delete_keymap(bufnr, '<BS>')
  set_selection_delete_keymap(bufnr, '<Del>')
  selection_keymaps_active[bufnr] = true
end

function M.deactivate_selection_keymaps(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    selection_keymaps_active[bufnr] = nil
    return
  end
  if not selection_keymaps_active[bufnr] then
    return
  end
  for _, lhs in ipairs({ '<BS>', '<Del>' }) do
    pcall(vim.keymap.del, 'i', lhs, { buffer = bufnr })
    local restore = selection_keymap_restore[bufnr] and selection_keymap_restore[bufnr][lhs]
    if restore then
      pcall(vim.api.nvim_buf_call, bufnr, function()
        vim.fn.mapset('i', false, restore)
      end)
      selection_keymap_restore[bufnr][lhs] = nil
    end
  end
  if selection_keymap_restore[bufnr] and not next(selection_keymap_restore[bufnr]) then
    selection_keymap_restore[bufnr] = nil
  end
  selection_keymaps_active[bufnr] = nil
end

return M
