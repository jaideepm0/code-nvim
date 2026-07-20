local config_module = require('vscode_style.config')
local actions = require('vscode_style.actions')
local multi_cursor = require('vscode_style.multi_cursor')
local aggressive = require('vscode_style.aggressive')

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
  buffer_states = {},
}

local selection_keymaps_active = {}
local selection_keymap_restore = {}
local buffer_local_maparg
local global_maparg

local function canonical_lhs(lhs)
  lhs = lhs:gsub('<[Ll]eader>', function()
    return vim.g.mapleader or '\\'
  end):gsub('<[Ll]ocal[Ll]eader>', function()
    return vim.g.maplocalleader or '\\'
  end)
  local termcodes = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  local ok, translated = pcall(vim.fn.keytrans, termcodes)
  return ok and translated or lhs
end

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
      local existing = entry.buffer and buffer_local_maparg(entry.buffer, lhs) or global_maparg(lhs)
      local owns_mapping = existing and existing.callback == entry.callback
      local restore_key = entry.restore_key
      local restore = restore_key and state.keymap_restore and state.keymap_restore[restore_key]
      if owns_mapping then
        local opts = entry.buffer and { buffer = entry.buffer } or nil
        pcall(vim.keymap.del, 'i', lhs, opts)
      end
      if owns_mapping and restore then
        if entry.buffer and vim.api.nvim_buf_is_valid(entry.buffer) then
          pcall(vim.api.nvim_buf_call, entry.buffer, function()
            vim.fn.mapset('i', false, restore)
          end)
        elseif not entry.buffer then
          pcall(vim.fn.mapset, 'i', false, restore)
        end
      end
      if restore_key then
        state.keymap_restore[restore_key] = nil
      end
    end
  end
  state.applied_keymaps = {}
end

local function record_applied_keymap(lhs, buffer, restore_key, callback)
  table.insert(state.applied_keymaps, {
    lhs = lhs,
    buffer = buffer,
    restore_key = restore_key,
    callback = callback,
  })
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
  lhs = canonical_lhs(lhs)
  if buffer then
    return string.format('buf:%d:%s', buffer, lhs)
  end
  return 'global:' .. lhs
end

buffer_local_maparg = function(bufnr, lhs)
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

global_maparg = function(lhs)
  local wanted = canonical_lhs(lhs)
  for _, existing in ipairs(vim.api.nvim_get_keymap('i')) do
    if canonical_lhs(existing.lhs) == wanted then
      return existing
    end
  end
  return nil
end

local function has_any_insert_map(lhs, buffer)
  if buffer and buffer_local_maparg(buffer, lhs) then
    return true
  end
  return global_maparg(lhs) ~= nil
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
  local args = type(spec.handler.args) == 'table' and vim.deepcopy(spec.handler.args) or nil
  if not args or #args == 0 then
    return function()
      return fn()
    end
  end
  return function()
    return fn(unpack(args))
  end
end

local function scoped_action_callback(callback, lhs)
  return function()
    -- Aggressive mode deliberately yields in prompt, terminal, floating, and
    -- other excluded UI buffers even though the core mappings are global.
    if aggressive.is_enabled() and not aggressive.is_active(vim.api.nvim_get_current_buf()) then
      local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
      vim.api.nvim_feedkeys(keys, 'n', false)
      return
    end
    return callback()
  end
end

local function apply_keymaps()
  clear_keymaps()

  if state.config.mapping_strategy == 'skip' then
    return
  end

  local strategy = state.config.mapping_strategy
  local seen = {}

  for _, name in ipairs(state.config.keymap_order) do
    local spec = state.config.keymaps[name]
    if spec and spec.enabled then
      local action_callback = make_action_callback(spec)
      if action_callback then
        for _, lhs in ipairs(spec.lhs) do
          local callback = scoped_action_callback(action_callback, lhs)
          local identity = canonical_lhs(lhs)
          if seen[identity] then
            notify(
              vim.log.levels.WARN,
              string.format('vscode_style: duplicate keymap %s (%s already owns it)', lhs, seen[identity])
            )
            goto continue
          end
          seen[identity] = name
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
            record_applied_keymap(lhs, buffer, key, callback)
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

  if state.config.autocommands.buf_cleanup then
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = state.autocmd_group,
      callback = function(args)
        M.deactivate_selection_keymaps(args.buf)
        multi_cursor.cleanup_buffer(args.buf)
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

  if state.config.autocommands.text_changed then
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
      group = state.autocmd_group,
      callback = function(args)
        -- Cursor-history snapshots contain byte positions, not extmarks. Any
        -- edit outside the cursor operations that created them makes them
        -- unsafe to restore.
        multi_cursor.clear_snapshot(args.buf)
      end,
    })
  end

end

function M.setup(user_config)
  aggressive.teardown()
  local active_buffers = vim.tbl_keys(selection_keymaps_active)
  for _, bufnr in ipairs(active_buffers) do
    M.deactivate_selection_keymaps(bufnr)
  end
  if state.ns then
    multi_cursor.teardown()
  end

  apply_config(user_config)

  if not state.ns then
    state.ns = vim.api.nvim_create_namespace('vscode_style')
  end

  state.cursors = {}
  state.buffer_states = {}
  state.snapshots = {}
  state.pending_inserts = {}
  state.clipboard_payload = nil
  state.column_selecting = false
  state.column_anchor = nil

  multi_cursor.setup(state)
  actions.setup(state, multi_cursor)

  setup_autocommands()
  apply_keymaps()
  aggressive.setup(state, actions)
end

function M.get_state()
  return state
end

function M.get_cursors()
  return multi_cursor.get_cursors()
end

function M.get_cursor_count()
  return #multi_cursor.iter()
end

function M.enable_aggressive_mode()
  aggressive.enable()
end

function M.disable_aggressive_mode()
  aggressive.disable()
end

function M.toggle_aggressive_mode()
  aggressive.toggle()
end

function M.suspend_aggressive_mode(bufnr)
  aggressive.suspend(bufnr)
end

function M.resume_aggressive_mode(bufnr)
  aggressive.resume(bufnr)
end

function M.is_aggressive_mode()
  return aggressive.is_enabled()
end

function M.is_aggressive_buffer(bufnr)
  return aggressive.is_active(bufnr)
end

function M.enter_normal_mode(bufnr)
  return aggressive.enter_normal_mode(bufnr)
end

function M.is_aggressive_normal_mode(bufnr)
  return aggressive.is_normal_session(bufnr)
end

local function set_selection_delete_keymap(bufnr, lhs)
  local restore = buffer_local_maparg(bufnr, lhs)
  if restore then
    selection_keymap_restore[bufnr] = selection_keymap_restore[bufnr] or {}
    selection_keymap_restore[bufnr][lhs] = restore
  end
  local callback = function()
    require('vscode_style.actions').delete_selection_and_cleanup(lhs == '<Del>' and 'right' or 'left')
  end
  vim.keymap.set('i', lhs, callback, {
    buffer = bufnr,
    silent = true,
    desc = 'Delete VS Code-style selection',
  })
  selection_keymaps_active[bufnr] = selection_keymaps_active[bufnr] or {}
  selection_keymaps_active[bufnr][lhs] = callback
end

function M.activate_selection_keymaps(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local active = selection_keymaps_active[bufnr] or {}
  if state.config.feature_flags.backspace ~= false and not active['<BS>'] then
    set_selection_delete_keymap(bufnr, '<BS>')
  end
  if not active['<Del>'] then
    set_selection_delete_keymap(bufnr, '<Del>')
  end
end

function M.deactivate_selection_keymaps(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    selection_keymaps_active[bufnr] = nil
    selection_keymap_restore[bufnr] = nil
    return
  end
  if not selection_keymaps_active[bufnr] then
    return
  end
  for lhs, callback in pairs(selection_keymaps_active[bufnr]) do
    local current = buffer_local_maparg(bufnr, lhs)
    local owns_mapping = current and current.callback == callback
    if owns_mapping then
      pcall(vim.keymap.del, 'i', lhs, { buffer = bufnr })
    end
    local restore = selection_keymap_restore[bufnr] and selection_keymap_restore[bufnr][lhs]
    if owns_mapping and restore then
      pcall(vim.api.nvim_buf_call, bufnr, function()
        vim.fn.mapset('i', false, restore)
      end)
    end
    if selection_keymap_restore[bufnr] then
      selection_keymap_restore[bufnr][lhs] = nil
    end
  end
  if selection_keymap_restore[bufnr] and not next(selection_keymap_restore[bufnr]) then
    selection_keymap_restore[bufnr] = nil
  end
  selection_keymaps_active[bufnr] = nil
end

function M.disable()
  aggressive.teardown()
  local active_buffers = vim.tbl_keys(selection_keymaps_active)
  for _, bufnr in ipairs(active_buffers) do
    M.deactivate_selection_keymaps(bufnr)
  end
  clear_keymaps()
  if state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
    state.autocmd_group = nil
  end
  multi_cursor.teardown()
  state.pending_inserts = {}
  state.clipboard_payload = nil
  state.column_selecting = false
  state.column_anchor = nil
end

return M
