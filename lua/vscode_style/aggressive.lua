local M = {}

local state
local actions
local eligibility = require('vscode_style.eligibility')
local runtime = {
  enabled = false,
  suspended = {},
  active = {},
  active_windows = {},
  normal_sessions = {},
  mappings = {},
  group = nil,
  commands = {},
  policy = {},
  generation = 0,
  pending_enters = {},
}

local unpack = table.unpack or unpack

local definitions = {
  { name = 'left', lhs = '<Left>', action = 'move_cursor', args = { 'character', 'left' }, desc = 'Move left' },
  { name = 'right', lhs = '<Right>', action = 'move_cursor', args = { 'character', 'right' }, desc = 'Move right' },
  { name = 'up', lhs = '<Up>', action = 'move_cursor', args = { 'line', 'up' }, desc = 'Move up' },
  { name = 'down', lhs = '<Down>', action = 'move_cursor', args = { 'line', 'down' }, desc = 'Move down' },
  { name = 'home', lhs = '<Home>', action = 'move_cursor', args = { 'line_boundary', 'home' }, desc = 'Move to line start' },
  { name = 'end', lhs = '<End>', action = 'move_cursor', args = { 'line_boundary', 'end' }, desc = 'Move to line end' },
  { name = 'word_left', lhs = '<C-Left>', action = 'move_cursor', args = { 'word', 'left' }, desc = 'Move one word left' },
  { name = 'word_right', lhs = '<C-Right>', action = 'move_cursor', args = { 'word', 'right' }, desc = 'Move one word right' },
  { name = 'file_start', lhs = '<C-Home>', action = 'move_cursor', args = { 'file_boundary', 'home' }, desc = 'Move to file start' },
  { name = 'file_end', lhs = '<C-End>', action = 'move_cursor', args = { 'file_boundary', 'end' }, desc = 'Move to file end' },
  { name = 'delete_word_left', lhs = '<C-BS>', action = 'delete_word', args = { 'left' }, desc = 'Delete word left' },
  { name = 'delete_word_right', lhs = '<C-Del>', action = 'delete_word', args = { 'right' }, desc = 'Delete word right' },
  { name = 'select_all', lhs = '<C-a>', action = 'select_all', desc = 'Select all' },
  { name = 'copy', lhs = '<C-c>', action = 'copy', desc = 'Copy selection' },
  { name = 'cut', lhs = '<C-x>', action = 'copy', args = { true }, desc = 'Cut selection' },
  { name = 'paste', lhs = '<C-v>', action = 'paste', desc = 'Paste at every cursor' },
  { name = 'undo', lhs = '<C-z>', action = 'undo', desc = 'Undo' },
  { name = 'cursor_undo', lhs = '<C-u>', action = 'undo_cursor_state', desc = 'Undo the last cursor operation' },
  { name = 'redo', lhs = { '<C-y>', '<C-S-z>' }, action = 'redo', desc = 'Redo' },
  { name = 'find', lhs = '<C-f>', action = 'start_search', desc = 'Find' },
  { name = 'save', lhs = '<C-s>', callback = function() M.save() end, desc = 'Save file' },
  { name = 'cancel', lhs = '<Esc>', callback = function() return M.handle_escape() end, desc = 'Dismiss UI or enter Normal mode' },
  { name = 'suspend', lhs = '<C-M-Esc>', callback = function() M.yield_to_neovim() end, desc = 'Suspend aggressive mode for this buffer' },
  { name = 'primary_click', lhs = '<LeftMouse>', action = 'primary_click', desc = 'Move the primary cursor and clear secondary cursors' },
  { name = 'previous_buffer', lhs = '<C-PageUp>', callback = function() M.switch_buffer('previous') end, desc = 'Previous buffer' },
  { name = 'next_buffer', lhs = '<C-PageDown>', callback = function() M.switch_buffer('next') end, desc = 'Next buffer' },
}

local function config()
  return (state and state.config and state.config.aggressive) or {}
end

local function notify(level, message)
  local fn = state and state.config and state.config.notify
  if fn == false then
    return
  end
  fn = fn or vim.notify
  pcall(fn, message, level or vim.log.levels.INFO)
end

local function canonical_lhs(lhs)
  local termcodes = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  local ok, translated = pcall(vim.fn.keytrans, termcodes)
  return ok and translated or lhs
end

local function as_lhs_list(value)
  if type(value) == 'string' then
    return value ~= '' and { value } or {}
  end
  if type(value) ~= 'table' then
    return {}
  end
  local result = {}
  for _, lhs in ipairs(value) do
    if type(lhs) == 'string' and lhs ~= '' then
      result[#result + 1] = lhs
    end
  end
  return result
end

local function keymap_index(maps)
  local result = {}
  for _, map in ipairs(maps or {}) do
    if type(map.lhs) == 'string' and map.lhs ~= '' then
      result[canonical_lhs(map.lhs)] = map
    end
  end
  return result
end

local function buffer_maps(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  local ok, result = pcall(vim.api.nvim_buf_get_keymap, bufnr, 'i')
  return ok and keymap_index(result) or {}
end

local function global_maps()
  local ok, result = pcall(vim.api.nvim_get_keymap, 'i')
  return ok and keymap_index(result) or {}
end

function M.should_attach(bufnr, winid)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  winid = winid or vim.api.nvim_get_current_win()
  if not runtime.enabled or runtime.suspended[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.b[bufnr].vscode_style_aggressive_disable then
    return false
  end

  local cfg = config()
  local forced = vim.b[bufnr].vscode_style_aggressive_enable
  local eligible = true
  if not forced then
    local err
    eligible, err = eligibility.evaluate(runtime.policy, bufnr, winid, 'aggressive')
    if err then
      notify(vim.log.levels.WARN, 'vscode_style buffer policy failed: ' .. tostring(err))
      return false
    end
  end
  if type(cfg.should_attach) == 'function' then
    local ok, decision = pcall(cfg.should_attach, bufnr, winid)
    if not ok then
      notify(vim.log.levels.WARN, 'vscode_style aggressive should_attach failed: ' .. tostring(decision))
      return false
    end
    if decision ~= nil then
      return not not decision
    end
  end
  return eligible
end

function M.is_enabled()
  return runtime.enabled
end

function M.is_active(bufnr, winid)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not (runtime.enabled and runtime.active[bufnr] == true and vim.api.nvim_buf_is_valid(bufnr)) then
    return false
  end
  winid = winid
    or (bufnr == vim.api.nvim_get_current_buf() and vim.api.nvim_get_current_win())
    or eligibility.window_for_buffer(bufnr)
  local windows = runtime.active_windows[bufnr]
  if windows and windows[winid] ~= nil then
    return windows[winid] == true
  end
  local eligible = M.should_attach(bufnr, winid)
  runtime.active_windows[bufnr] = runtime.active_windows[bufnr] or {}
  runtime.active_windows[bufnr][winid] = eligible == true
  return eligible == true
end

function M.is_normal_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return runtime.enabled and runtime.normal_sessions[bufnr] == true
end

local function fallback(lhs)
  local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
  vim.api.nvim_feedkeys(keys, 'n', false)
end

function M.enter_normal_mode(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if bufnr ~= vim.api.nvim_get_current_buf() or not M.is_active(bufnr) then
    return false
  end
  runtime.normal_sessions[bufnr] = true
  runtime.pending_enters[bufnr] = nil
  fallback('<Esc>')
  return true
end

function M.handle_escape()
  if actions.cancel_selection() then
    return true
  end
  if config().escape_to_normal == false then
    return false
  end
  return M.enter_normal_mode()
end

local function resolve_definition(definition)
  local override = config().keymaps and config().keymaps[definition.name]
  if override == false then
    return nil
  end
  local resolved = vim.deepcopy(definition)
  local is_list = vim.islist or vim.tbl_islist
  if type(override) == 'string' or (type(override) == 'table' and is_list(override)) then
    resolved.lhs = override
  elseif type(override) == 'table' then
    if override.enabled == false then
      return nil
    end
    resolved.lhs = override.lhs or resolved.lhs
    resolved.desc = override.desc or resolved.desc
    if type(override.action) == 'string' then
      resolved.action = override.action
      if type(override.callback) ~= 'function' then
        resolved.callback = nil
      end
    end
    resolved.args = type(override.args) == 'table' and vim.deepcopy(override.args) or resolved.args
    resolved.callback = type(override.callback) == 'function' and override.callback or resolved.callback
  end
  resolved.lhs = as_lhs_list(resolved.lhs)
  return #resolved.lhs > 0 and resolved or nil
end

local function callback_for(bufnr, lhs, definition)
  local callback = definition.callback
  if not callback and definition.action and type(actions[definition.action]) == 'function' then
    local fn = actions[definition.action]
    local args = definition.args or {}
    callback = function()
      return fn(unpack(args))
    end
  end
  if not callback then
    return nil
  end
  return function()
    if not M.is_active(bufnr) or bufnr ~= vim.api.nvim_get_current_buf() then
      fallback(lhs)
      return
    end
    local ok, result = pcall(callback)
    if not ok then
      notify(vim.log.levels.ERROR, 'vscode_style aggressive action failed: ' .. tostring(result))
    elseif result == false then
      fallback(lhs)
    end
  end
end

local function detach_buffer(bufnr)
  local entries = runtime.mappings[bufnr]
  runtime.active[bufnr] = nil
  runtime.active_windows[bufnr] = nil
  if not entries then
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.b[bufnr].vscode_style_aggressive_active = false
    end
    return
  end
  local current_maps = buffer_maps(bufnr)
  for _, entry in ipairs(entries) do
    local current = current_maps[entry.identity]
    local owns = current and current.callback == entry.callback
    if owns then
      pcall(vim.keymap.del, 'i', entry.lhs, { buffer = bufnr })
      if entry.restore and vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_call, bufnr, function()
          vim.fn.mapset('i', false, entry.restore)
        end)
      end
    end
  end
  runtime.mappings[bufnr] = nil
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].vscode_style_aggressive_active = false
  end
end

function M.attach_buffer(bufnr, winid)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  winid = winid or vim.api.nvim_get_current_win()
  if not M.should_attach(bufnr, winid) then
    runtime.active_windows[bufnr] = runtime.active_windows[bufnr] or {}
    runtime.active_windows[bufnr][winid] = false
    detach_buffer(bufnr)
    return false
  end
  if runtime.mappings[bufnr] then
    runtime.active[bufnr] = true
    runtime.active_windows[bufnr] = runtime.active_windows[bufnr] or {}
    runtime.active_windows[bufnr][winid] = true
    vim.b[bufnr].vscode_style_aggressive_active = true
    return true
  end

  local entries, seen = {}, {}
  local local_maps = buffer_maps(bufnr)
  local inherited_maps = global_maps()
  runtime.mappings[bufnr] = entries
  for _, base in ipairs(definitions) do
    local definition = resolve_definition(base)
    if definition then
      for _, lhs in ipairs(definition.lhs) do
        local identity = canonical_lhs(lhs)
        if seen[identity] then
          goto continue
        end
        seen[identity] = true
        local existing = local_maps[identity] or inherited_maps[identity]
        if existing and config().mapping_strategy == 'respect' then
          goto continue
        end
        local callback = callback_for(bufnr, lhs, definition)
        if not callback then
          goto continue
        end
        local restore = local_maps[identity]
        local ok, err = pcall(vim.keymap.set, 'i', lhs, callback, {
          buffer = bufnr,
          silent = true,
          desc = 'VS Code aggressive: ' .. definition.desc,
        })
        if ok then
          entries[#entries + 1] = {
            lhs = lhs,
            identity = identity,
            callback = callback,
            restore = restore,
          }
        else
          notify(vim.log.levels.WARN, string.format('vscode_style: failed to map %s (%s)', lhs, err))
        end
        ::continue::
      end
    end
  end
  runtime.active[bufnr] = true
  runtime.active_windows[bufnr] = runtime.active_windows[bufnr] or {}
  runtime.active_windows[bufnr][winid] = true
  vim.b[bufnr].vscode_style_aggressive_active = true
  return true
end

local function schedule_enter(bufnr, kind, callback)
  local pending = runtime.pending_enters[bufnr]
  if pending and pending.kind == kind and pending.generation == runtime.generation then
    return
  end
  local token = { kind = kind, generation = runtime.generation }
  runtime.pending_enters[bufnr] = token
  vim.schedule(function()
    if runtime.pending_enters[bufnr] ~= token then
      return
    end
    runtime.pending_enters[bufnr] = nil
    if token.generation ~= runtime.generation or not runtime.enabled then
      return
    end
    callback()
  end)
end

local function enter_editor(bufnr)
  if not config().auto_insert or runtime.normal_sessions[bufnr] then
    return
  end
  schedule_enter(bufnr, 'editor', function()
    if bufnr ~= vim.api.nvim_get_current_buf() or not M.is_active(bufnr) then
      return
    end
    local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
    if mode ~= 'i' and mode ~= 'R' and mode ~= 'c' and mode ~= 't' then
      pcall(vim.cmd, 'startinsert')
    end
  end)
end

local function enter_terminal(bufnr)
  if not config().terminal_startinsert then
    return
  end
  schedule_enter(bufnr, 'terminal', function()
    if
      vim.api.nvim_buf_is_valid(bufnr)
      and bufnr == vim.api.nvim_get_current_buf()
      and vim.bo[bufnr].buftype == 'terminal'
    then
      pcall(vim.cmd, 'startinsert')
    end
  end)
end

local function emit_changed()
  pcall(vim.api.nvim_exec_autocmds, 'User', {
    pattern = 'VscodeStyleAggressiveModeChanged',
    data = { enabled = runtime.enabled },
  })
end

local function setup_autocommands()
  if runtime.group then
    pcall(vim.api.nvim_del_augroup_by_id, runtime.group)
  end
  runtime.group = vim.api.nvim_create_augroup('VscodeStyleAggressive', { clear = true })
  local function handle_window_buffer(bufnr, winid)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then
      return
    end
    if vim.bo[bufnr].buftype == 'terminal' then
      detach_buffer(bufnr)
      enter_terminal(bufnr)
      return
    end
    if M.attach_buffer(bufnr, winid) then
      enter_editor(bufnr)
    end
  end

  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
    group = runtime.group,
    callback = function(event)
      handle_window_buffer(event.buf, vim.api.nvim_get_current_win())
    end,
  })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = runtime.group,
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      local generation = runtime.generation
      vim.schedule(function()
        if generation == runtime.generation and runtime.enabled and vim.api.nvim_win_is_valid(winid) then
          handle_window_buffer(vim.api.nvim_win_get_buf(winid), winid)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = runtime.group,
    callback = function(event)
      enter_editor(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = runtime.group,
    callback = function(event)
      runtime.normal_sessions[event.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd('BufLeave', {
    group = runtime.group,
    callback = function(event)
      runtime.normal_sessions[event.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd('TermOpen', {
    group = runtime.group,
    callback = function(event)
      detach_buffer(event.buf)
      enter_terminal(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd('OptionSet', {
    group = runtime.group,
    pattern = { 'buftype', 'modifiable', 'readonly' },
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.bo[bufnr].buftype == 'terminal' then
        detach_buffer(bufnr)
        enter_terminal(bufnr)
      elseif M.attach_buffer(bufnr, vim.api.nvim_get_current_win()) then
        enter_editor(bufnr)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = runtime.group,
    callback = function(event)
      runtime.mappings[event.buf] = nil
      runtime.suspended[event.buf] = nil
      runtime.active[event.buf] = nil
      runtime.active_windows[event.buf] = nil
      runtime.normal_sessions[event.buf] = nil
      runtime.pending_enters[event.buf] = nil
    end,
  })
end

function M.enable()
  if runtime.enabled then
    M.attach_buffer()
    enter_editor(vim.api.nvim_get_current_buf())
    return
  end
  runtime.generation = runtime.generation + 1
  runtime.enabled = true
  runtime.suspended = {}
  runtime.normal_sessions = {}
  setup_autocommands()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype == 'terminal' then
    enter_terminal(bufnr)
  elseif M.attach_buffer(bufnr, vim.api.nvim_get_current_win()) then
    enter_editor(bufnr)
  end
  emit_changed()
end

function M.disable()
  if not runtime.enabled then
    return
  end
  runtime.enabled = false
  runtime.generation = runtime.generation + 1
  runtime.pending_enters = {}
  local buffers = vim.tbl_keys(runtime.mappings)
  for _, bufnr in ipairs(buffers) do
    detach_buffer(bufnr)
  end
  runtime.suspended = {}
  runtime.active = {}
  runtime.active_windows = {}
  runtime.normal_sessions = {}
  if runtime.group then
    pcall(vim.api.nvim_del_augroup_by_id, runtime.group)
    runtime.group = nil
  end
  emit_changed()
end

function M.toggle()
  if runtime.enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.suspend(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  runtime.suspended[bufnr] = true
  runtime.normal_sessions[bufnr] = nil
  detach_buffer(bufnr)
end

function M.resume(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  runtime.suspended[bufnr] = nil
  runtime.normal_sessions[bufnr] = nil
  if runtime.enabled and M.attach_buffer(bufnr, eligibility.window_for_buffer(bufnr)) then
    enter_editor(bufnr)
  end
end

function M.yield_to_neovim()
  M.suspend(vim.api.nvim_get_current_buf())
  fallback('<Esc>')
end

function M.switch_buffer(direction)
  vim.schedule(function()
    local command = direction == 'previous' and 'bprevious' or 'bnext'
    local ok, err = pcall(vim.cmd, command)
    if not ok then
      notify(vim.log.levels.WARN, 'vscode_style: ' .. tostring(err))
    end
  end)
end

function M.save()
  vim.schedule(function()
    local ok, err = pcall(vim.cmd, 'silent update')
    if not ok then
      notify(vim.log.levels.ERROR, 'vscode_style: ' .. tostring(err))
    end
  end)
end

local command_definitions = {
  VscodeStyleAggressiveEnable = function() M.enable() end,
  VscodeStyleAggressiveDisable = function() M.disable() end,
  VscodeStyleAggressiveToggle = function() M.toggle() end,
  VscodeStyleAggressiveSuspend = function() M.suspend() end,
  VscodeStyleAggressiveResume = function() M.resume() end,
}

local function create_commands()
  for name, callback in pairs(command_definitions) do
    local existing = vim.api.nvim_get_commands({ builtin = false })[name]
    if existing then
      notify(vim.log.levels.WARN, string.format('vscode_style: command %s already exists; leaving it untouched', name))
    else
      local ok = pcall(vim.api.nvim_create_user_command, name, callback, {})
      if ok then
        runtime.commands[name] = callback
      end
    end
  end
end

function M.setup(plugin_state, action_module)
  M.teardown()
  state = plugin_state
  actions = action_module
  runtime.policy = {
    allow_floating = config().allow_floating,
    excluded_buftypes = eligibility.to_set(config().exclude_buftypes),
    excluded_filetypes = eligibility.to_set(config().exclude_filetypes),
    should_handle = config().should_handle,
  }
  create_commands()
  if config().enabled then
    M.enable()
  end
end

function M.teardown()
  M.disable()
  local commands = vim.api.nvim_get_commands({ builtin = false })
  for name, callback in pairs(runtime.commands) do
    local current = commands[name]
    if current and current.callback == callback then
      pcall(vim.api.nvim_del_user_command, name)
    end
  end
  runtime.commands = {}
  runtime.mappings = {}
  runtime.suspended = {}
  runtime.active = {}
  runtime.active_windows = {}
  runtime.normal_sessions = {}
  runtime.pending_enters = {}
end

function M.get_state()
  return {
    enabled = runtime.enabled,
    suspended = vim.deepcopy(runtime.suspended),
    active = vim.deepcopy(runtime.active),
    normal_sessions = vim.deepcopy(runtime.normal_sessions),
  }
end

return M
