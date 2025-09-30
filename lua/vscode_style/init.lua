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
  backspace_mapped = false,
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
    local opts = entry.opts
    if lhs then
      pcall(vim.keymap.del, 'i', lhs, opts)
      local restore = state.keymap_restore and state.keymap_restore[lhs]
      if restore then
        pcall(vim.fn.mapset, 'i', false, restore)
        state.keymap_restore[lhs] = nil
      end
    end
  end
  state.applied_keymaps = {}
end

local function record_applied_keymap(lhs, opts)
  table.insert(state.applied_keymaps, { lhs = lhs, opts = opts })
end

local function sanitize_buffer_option(buffer)
  if buffer == nil then
    return nil
  end
  if buffer == true then
    return 0
  end
  if type(buffer) == 'number' then
    return buffer
  end
  return nil
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
  state.backspace_mapped = false

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
          if buffer then
            opts.buffer = buffer
          else
            opts.buffer = nil
          end

          if strategy == 'respect' and vim.fn.maparg(lhs, 'i') ~= '' then
            goto continue
          end

          if strategy == 'force' then
            local existing = vim.fn.maparg(lhs, 'i', false, true)
            if type(existing) == 'table' and existing.lhs ~= '' then
              state.keymap_restore[lhs] = state.keymap_restore[lhs] or existing
            end
          end

          local ok, err = pcall(vim.keymap.set, 'i', lhs, callback, opts)
          if ok then
            local del_opts = opts.buffer and { buffer = opts.buffer } or nil
            record_applied_keymap(lhs, del_opts)
            if spec.handler and spec.handler.fn == 'backspace_expr' and opts.expr then
              state.backspace_mapped = true
            end
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
      callback = function()
        multi_cursor.save_snapshot()
        multi_cursor.clear_all_selections()
        multi_cursor.update_highlights()
      end,
    })
  end

  if state.config.autocommands.buf_enter then
    vim.api.nvim_create_autocmd('BufEnter', {
      group = state.autocmd_group,
      callback = function()
        multi_cursor.switch_buffer()
      end,
    })
  end

  if state.config.autocommands.insert_enter then
    vim.api.nvim_create_autocmd('InsertEnter', {
      group = state.autocmd_group,
      callback = function()
        multi_cursor.restore_snapshot()
      end,
    })
  end

  if state.config.autocommands.buf_cleanup then
    vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
      group = state.autocmd_group,
      callback = function(args)
        multi_cursor.clear_snapshot(args.buf)
      end,
    })
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

  setup_autocommands()
  apply_keymaps()

  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_set_option, buf, 'modified', was_modified)
  end
end

function M.get_state()
  return state
end

return M
