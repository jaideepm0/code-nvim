local M = {}

local default_feature_flags = {
  selection = true,
  line_ops = true,
  multi_cursor = true,
  column_selection = true,
  tab = true,
  backspace = true,
  surround = true,
}

local default_autocommands = {
  insert_char_pre = true,
  insert_leave = true,
  buf_enter = true,
  buf_cleanup = true,
  cursor_moved_i = true,
  text_changed = true,
}

local keymap_definitions = {
  {
    name = 'select_character_left',
    group = 'selection',
    lhs = '<S-Left>',
    description = 'Select previous character',
    handler = { fn = 'select_character', args = { 'left' } },
  },
  {
    name = 'select_character_right',
    group = 'selection',
    lhs = '<S-Right>',
    description = 'Select next character',
    handler = { fn = 'select_character', args = { 'right' } },
  },
  {
    name = 'select_line_up',
    group = 'selection',
    lhs = '<S-Up>',
    description = 'Select previous line',
    handler = { fn = 'select_line', args = { 'up' } },
  },
  {
    name = 'select_line_down',
    group = 'selection',
    lhs = '<S-Down>',
    description = 'Select next line',
    handler = { fn = 'select_line', args = { 'down' } },
  },
  {
    name = 'select_word_left',
    group = 'selection',
    lhs = '<C-S-Left>',
    description = 'Select previous word',
    handler = { fn = 'select_word', args = { 'left' } },
  },
  {
    name = 'select_word_right',
    group = 'selection',
    lhs = '<C-S-Right>',
    description = 'Select next word',
    handler = { fn = 'select_word', args = { 'right' } },
  },
  {
    name = 'select_to_line_start',
    group = 'selection',
    lhs = '<S-Home>',
    description = 'Select to beginning of line',
    handler = { fn = 'select_to_line_boundary', args = { 'home' } },
  },
  {
    name = 'select_to_line_end',
    group = 'selection',
    lhs = '<S-End>',
    description = 'Select to end of line',
    handler = { fn = 'select_to_line_boundary', args = { 'end' } },
  },
  {
    name = 'select_to_file_start',
    group = 'selection',
    lhs = '<C-S-Home>',
    description = 'Select to start of file',
    handler = { fn = 'select_to_file_boundary', args = { 'home' } },
  },
  {
    name = 'select_to_file_end',
    group = 'selection',
    lhs = '<C-S-End>',
    description = 'Select to end of file',
    handler = { fn = 'select_to_file_boundary', args = { 'end' } },
  },
  {
    name = 'indent_with_tab',
    group = 'tab',
    lhs = '<Tab>',
    description = 'Indent selection (VS Code style)',
    handler = { fn = 'handle_tab' },
  },
  {
    name = 'dedent_with_shift_tab',
    group = 'tab',
    lhs = '<S-Tab>',
    description = 'Dedent selection (VS Code style)',
    handler = { fn = 'handle_shift_tab' },
  },
  {
    name = 'backspace',
    group = 'backspace',
    lhs = '<BS>',
    description = 'Delete selections or backspace at every cursor',
    handler = { fn = 'handle_backspace' },
  },
  {
    name = 'delete_forward',
    group = 'backspace',
    lhs = '<Del>',
    description = 'Delete selections or delete at every cursor',
    handler = { fn = 'handle_delete' },
  },
  {
    name = 'insert_newline',
    group = 'multi_cursor',
    lhs = '<CR>',
    description = 'Insert a newline at every cursor',
    handler = { fn = 'handle_enter' },
  },
  {
    name = 'move_line_up',
    group = 'line_ops',
    lhs = '<M-Up>',
    description = 'Move current line up',
    handler = { fn = 'move_line', args = { 'up' } },
  },
  {
    name = 'move_line_down',
    group = 'line_ops',
    lhs = '<M-Down>',
    description = 'Move current line down',
    handler = { fn = 'move_line', args = { 'down' } },
  },
  {
    name = 'copy_line_up',
    group = 'line_ops',
    lhs = '<S-M-Up>',
    description = 'Copy current line up',
    handler = { fn = 'copy_line', args = { 'up' } },
  },
  {
    name = 'copy_line_down',
    group = 'line_ops',
    lhs = '<S-M-Down>',
    description = 'Copy current line down',
    handler = { fn = 'copy_line', args = { 'down' } },
  },
  {
    name = 'delete_line',
    group = 'line_ops',
    lhs = '<C-S-K>',
    description = 'Delete current line',
    handler = { fn = 'delete_line' },
  },
  {
    name = 'alt_click_cursor',
    group = 'multi_cursor',
    lhs = '<M-LeftMouse>',
    description = 'Add cursor with Alt+Click',
    handler = { fn = 'alt_click_cursor' },
  },
  {
    name = 'cursor_above',
    group = 'multi_cursor',
    lhs = '<C-M-Up>',
    description = 'Add cursor above',
    handler = { fn = 'add_cursor_vertical', args = { 'up' } },
  },
  {
    name = 'cursor_below',
    group = 'multi_cursor',
    lhs = '<C-M-Down>',
    description = 'Add cursor below',
    handler = { fn = 'add_cursor_vertical', args = { 'down' } },
  },
  {
    name = 'add_selection_next',
    group = 'multi_cursor',
    lhs = '<C-d>',
    description = 'Add selection to next match',
    handler = { fn = 'add_selection_to_next_match' },
  },
  {
    name = 'select_all_occurrences',
    group = 'multi_cursor',
    lhs = '<C-S-l>',
    description = 'Select all occurrences',
    handler = { fn = 'select_all_occurrences' },
  },
  {
    name = 'expand_selection',
    group = 'multi_cursor',
    lhs = '<S-M-Right>',
    description = 'Expand selection',
    handler = { fn = 'expand_selection' },
  },
  {
    name = 'shrink_selection',
    group = 'multi_cursor',
    lhs = '<S-M-Left>',
    description = 'Shrink selection',
    handler = { fn = 'shrink_selection' },
  },
  {
    name = 'column_select_drag',
    group = 'column_selection',
    lhs = { '<S-M-LeftMouse>', '<S-M-LeftDrag>' },
    description = 'Start or update column selection',
    handler = { fn = 'column_selection_drag_start' },
  },
  {
    name = 'column_select_release',
    group = 'column_selection',
    lhs = '<S-M-LeftRelease>',
    description = 'Finish column selection',
    handler = { fn = 'column_selection_drag_end' },
  },
}

for index, def in ipairs(keymap_definitions) do
  def.index = index
end

local function normalize_lhs(lhs)
  if lhs == nil then
    return {}
  end
  if type(lhs) == 'table' then
    local results = {}
    for _, entry in ipairs(lhs) do
      if type(entry) == 'string' and entry ~= '' then
        table.insert(results, entry)
      end
    end
    return results
  end
  if type(lhs) == 'string' then
    if lhs == '' then
      return {}
    end
    return { lhs }
  end
  return {}
end

local function normalize_notify(notify)
  if notify == false then
    return false
  end
  if type(notify) == 'function' then
    return notify
  end
  return vim.notify
end

local defaults = {
  selection_hl = 'Visual',
  cursor_hl = 'Cursor',
  max_cursors = 32,
  mapping_strategy = 'respect',
  feature_flags = default_feature_flags,
  autocommands = default_autocommands,
  notify = vim.notify,
}

local aggressive_defaults = {
  enabled = false,
  auto_insert = true,
  escape_to_normal = true,
  terminal_startinsert = true,
  allow_floating = false,
  mapping_strategy = 'respect',
  clipboard_register = '+',
  exclude_buftypes = { 'acwrite', 'help', 'nofile', 'nowrite', 'prompt', 'quickfix', 'terminal' },
  exclude_filetypes = {
    'DressingInput',
    'NvimTree',
    'TelescopePrompt',
    'alpha',
    'dashboard',
    'lazy',
    'mason',
    'neo-tree',
    'notify',
    'oil',
  },
}

local function normalize_string_list(value, fallback)
  if type(value) ~= 'table' then
    return vim.deepcopy(fallback)
  end
  local result, seen = {}, {}
  for _, entry in ipairs(value) do
    if type(entry) == 'string' and entry ~= '' and not seen[entry] then
      seen[entry] = true
      result[#result + 1] = entry
    end
  end
  return result
end

local function normalize_aggressive(value)
  local cfg = vim.deepcopy(aggressive_defaults)
  if value == true then
    cfg.enabled = true
    return cfg
  end
  if type(value) ~= 'table' then
    return cfg
  end

  -- Supplying an options table is itself an opt-in unless explicitly disabled.
  cfg.enabled = value.enabled ~= false
  for _, key in ipairs({ 'auto_insert', 'escape_to_normal', 'terminal_startinsert', 'allow_floating' }) do
    if value[key] ~= nil then
      cfg[key] = not not value[key]
    end
  end
  if value.mapping_strategy == 'force' or value.mapping_strategy == 'respect' then
    cfg.mapping_strategy = value.mapping_strategy
  end
  if type(value.clipboard_register) == 'string' and value.clipboard_register ~= '' then
    cfg.clipboard_register = value.clipboard_register
  end
  cfg.exclude_buftypes = normalize_string_list(value.exclude_buftypes, aggressive_defaults.exclude_buftypes)
  cfg.exclude_filetypes = normalize_string_list(value.exclude_filetypes, aggressive_defaults.exclude_filetypes)
  cfg.should_attach = type(value.should_attach) == 'function' and value.should_attach or nil
  cfg.keymaps = type(value.keymaps) == 'table' and vim.deepcopy(value.keymaps) or {}
  return cfg
end

local function normalize_feature_flags(mappings, feature_flags)
  local flags = vim.deepcopy(default_feature_flags)
  local function apply(tbl)
    if type(tbl) ~= 'table' then
      return
    end
    for key, value in pairs(tbl) do
      if flags[key] ~= nil then
        flags[key] = not not value
      end
    end
  end
  apply(mappings)
  apply(feature_flags)
  return flags
end

local function normalize_autocommands(user)
  local autocmds = vim.deepcopy(default_autocommands)
  if type(user) ~= 'table' then
    return autocmds
  end
  for key, value in pairs(user) do
    if autocmds[key] ~= nil and value ~= nil then
      autocmds[key] = not not value
    end
  end
  return autocmds
end

local function resolve_handler(def, override)
  if type(override) == 'table' then
    if type(override.callback) == 'function' then
      return nil, override.callback
    end
    local handler = type(override.handler) == 'table' and override.handler or {}
    local fn = override.action or handler.fn or (override.fn)
    if type(fn) == 'string' then
      local args = override.args or handler.args
      return { fn = fn, args = type(args) == 'table' and vim.deepcopy(args) or nil }, nil
    end
    if type(override.args) == 'table' and def.handler then
      local base = vim.deepcopy(def.handler)
      base.args = vim.deepcopy(override.args)
      return base, nil
    end
  end
  return def.handler and vim.deepcopy(def.handler) or nil, nil
end

local function resolve_keymaps(config, overrides)
  local resolved = {}
  local order = {}
  overrides = type(overrides) == 'table' and overrides or {}
  for _, def in ipairs(keymap_definitions) do
    local override = overrides[def.name]
    local enabled = config.feature_flags[def.group] ~= false
    local lhs = normalize_lhs(def.lhs)
    local opts = def.opts and vim.deepcopy(def.opts) or {}
    local description = def.description
    local handler = def.handler and vim.deepcopy(def.handler) or nil
    local callback = nil

    if override ~= nil then
      if override == false then
        enabled = false
      elseif override == true then
        -- keep defaults
      elseif type(override) == 'string' then
        lhs = normalize_lhs(override)
      elseif type(override) == 'table' then
        if override.enabled ~= nil then
          enabled = not not override.enabled
        end
        if override.lhs ~= nil then
          lhs = normalize_lhs(override.lhs)
        end
        if type(override.opts) == 'table' then
          opts = vim.tbl_deep_extend('force', {}, opts, override.opts)
        end
        if override.desc ~= nil then
          description = override.desc
        end
        handler, callback = resolve_handler(def, override)
      end
    end

    if #lhs == 0 then
      enabled = false
    end

    resolved[def.name] = {
      name = def.name,
      group = def.group,
      enabled = enabled,
      lhs = lhs,
      opts = opts,
      handler = handler,
      callback = callback,
      description = description,
    }
    table.insert(order, def.name)
  end
  return resolved, order
end

function M.normalize(user_config)
  local cfg = {}
  user_config = type(user_config) == 'table' and user_config or {}

  local selection_hl = user_config.selection_hl
  if selection_hl == nil then
    cfg.selection_hl = defaults.selection_hl
  elseif selection_hl == false then
    cfg.selection_hl = false
  elseif type(selection_hl) == 'string' then
    cfg.selection_hl = selection_hl
  else
    cfg.selection_hl = defaults.selection_hl
  end

  local max_cursors = tonumber(user_config.max_cursors)
  if max_cursors and max_cursors >= 1 and max_cursors < math.huge then
    cfg.max_cursors = math.floor(max_cursors)
  else
    cfg.max_cursors = defaults.max_cursors
  end

  local cursor_hl = user_config.cursor_hl
  if cursor_hl == nil then
    cfg.cursor_hl = defaults.cursor_hl
  elseif cursor_hl == false then
    cfg.cursor_hl = false
  elseif type(cursor_hl) == 'string' then
    cfg.cursor_hl = cursor_hl
  else
    cfg.cursor_hl = defaults.cursor_hl
  end

  local mapping_strategy = user_config.mapping_strategy
  if not mapping_strategy and type(user_config.mappings) == 'table' then
    mapping_strategy = user_config.mappings.strategy
  end
  if mapping_strategy ~= 'force' and mapping_strategy ~= 'respect' and mapping_strategy ~= 'skip' then
    mapping_strategy = defaults.mapping_strategy
  end
  cfg.mapping_strategy = mapping_strategy

  cfg.feature_flags = normalize_feature_flags(user_config.mappings, user_config.feature_flags)
  cfg.autocommands = normalize_autocommands(user_config.autocommands)
  cfg.notify = normalize_notify(user_config.notify)
  cfg.aggressive = normalize_aggressive(user_config.aggressive)

  local overrides = user_config.keymaps
  if overrides == nil and type(user_config.mappings) == 'table' then
    overrides = user_config.mappings.keymaps
  end

  cfg.keymaps, cfg.keymap_order = resolve_keymaps(cfg, overrides)

  return cfg
end

function M.keymap_definitions()
  local defs = {}
  for _, def in ipairs(keymap_definitions) do
    defs[def.name] = vim.deepcopy(def)
  end
  return defs
end

return M
