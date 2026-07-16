local M = {}

local state
local util = require('vscode_style.util')

local log_levels = vim.log.levels

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
  pcall(fn, msg, level or log_levels.INFO)
end

local function current_buf()
  return vim.api.nvim_get_current_buf()
end

local clamp = util.clamp

local function buf()
  return vim.api.nvim_get_current_buf()
end

local function ensure_namespace()
  if not (state and state.ns) then
    error('vscode_style multi_cursor used before setup')
  end
end

local function cursor_mark_opts(is_primary, line_text, col, id)
  local opts = {
    right_gravity = true,
  }
  if id then
    opts.id = id
  end
  local hl = state.config and state.config.cursor_hl
  if not is_primary and hl ~= false then
    local char = util.codepoint_at(line_text, col)
    opts.virt_text = { { char ~= '' and char or ' ', hl or 'Cursor' } }
    opts.virt_text_pos = 'overlay'
    opts.hl_mode = 'combine'
    opts.priority = 200
  else
    opts.virt_text = {}
  end
  return opts
end

local function render_cursor(cursor)
  local bufnr = cursor.bufnr or buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local line_text = vim.api.nvim_buf_get_lines(bufnr, cursor.line, cursor.line + 1, true)[1] or ''
  cursor.id = vim.api.nvim_buf_set_extmark(
    bufnr,
    state.ns,
    cursor.line,
    cursor.col,
    cursor_mark_opts(cursor.is_primary, line_text, cursor.col, cursor.id)
  )
end

local function create_cursor(line, col, opts)
  opts = opts or {}
  local buf_handle = buf()
  local total_lines = vim.api.nvim_buf_line_count(buf_handle)
  if total_lines == 0 then
    vim.api.nvim_buf_set_lines(buf_handle, 0, -1, false, { '' })
    total_lines = 1
  end
  line = clamp(line or 0, 0, total_lines - 1)
  local line_text = vim.api.nvim_buf_get_lines(buf_handle, line, line + 1, true)[1] or ''
  col = util.codepoint_start(line_text, clamp(col or 0, 0, #line_text))

  local mark_id = vim.api.nvim_buf_set_extmark(
    buf_handle,
    state.ns,
    line,
    col,
    cursor_mark_opts(opts.is_primary or false, line_text, col)
  )

  local cursor = {
    id = mark_id,
    line = line,
    col = col,
    anchor = nil,
    selection = nil,
    highlight_id = nil,
    selection_stack = {},
    is_primary = opts.is_primary or false,
    bufnr = buf_handle,
  }
  return cursor
end

local function delete_highlight(cursor)
  if cursor.highlight_id then
    local bufnr = cursor.bufnr or buf()
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns, cursor.highlight_id)
    end
    cursor.highlight_id = nil
  end
end

local function sanitize_position(pos)
  local buf_handle = buf()
  local total_lines = vim.api.nvim_buf_line_count(buf_handle)
  if total_lines == 0 then
    vim.api.nvim_buf_set_lines(buf_handle, 0, -1, false, { '' })
    total_lines = 1
  end
  local line = clamp((pos and pos.line) or 0, 0, total_lines - 1)
  local line_text = vim.api.nvim_buf_get_lines(buf_handle, line, line + 1, true)[1] or ''
  local col = util.codepoint_start(line_text, clamp((pos and pos.col) or 0, 0, #line_text))
  return line, col
end

local function sanitize_selection(cursor)
  if not cursor.selection then
    return
  end
  local anchor_line, anchor_col = sanitize_position(cursor.selection.anchor)
  local active_line, active_col = sanitize_position(cursor.selection.active)
  cursor.selection.anchor = { line = anchor_line, col = anchor_col }
  cursor.selection.active = { line = active_line, col = active_col }
  if cursor.anchor then
    local sanitized_anchor_line, sanitized_anchor_col = sanitize_position(cursor.anchor)
    cursor.anchor = { line = sanitized_anchor_line, col = sanitized_anchor_col }
  end
end

local function sync_cursor_from_extmark(cursor)
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf(), state.ns, cursor.id, {})
  if pos and pos[1] then
    cursor.line = pos[1]
    cursor.col = pos[2]
  else
    -- Extmark missing; recreate at win cursor
    local current = vim.api.nvim_win_get_cursor(0)
    cursor.line = current[1] - 1
    cursor.col = current[2]
    cursor.id = vim.api.nvim_buf_set_extmark(buf(), state.ns, cursor.line, cursor.col, {
      id = cursor.id,
      right_gravity = true,
    })
  end
end

local function sort_cursors()
  local primary_cursor
  for _, cur in ipairs(state.cursors) do
    if cur.is_primary then
      primary_cursor = cur
      break
    end
  end
  table.sort(state.cursors, function(a, b)
    if a.line == b.line then
      return a.col < b.col
    end
    return a.line < b.line
  end)
  if primary_cursor then
    for _, cur in ipairs(state.cursors) do
      cur.is_primary = (cur == primary_cursor)
    end
  end
end

local function ensure_primary()
  if #state.cursors == 0 then
    local pos = vim.api.nvim_win_get_cursor(0)
    local cursor = create_cursor(math.max(pos[1], 1) - 1, math.max(pos[2], 0), { is_primary = true })
    table.insert(state.cursors, cursor)
  end
  sort_cursors()
  local primary
  local primary_changed = false
  for _, cur in ipairs(state.cursors) do
    if cur.is_primary then
      primary = cur
      break
    end
  end
  if not primary then
    primary = state.cursors[1]
    if primary then
      primary.is_primary = true
      primary_changed = true
    end
  end
  if primary then
    local line, col = sanitize_position({ line = primary.line, col = primary.col })
    if line ~= primary.line or col ~= primary.col then
      primary.line = line
      primary.col = col
      render_cursor(primary)
    end
  end
  if primary_changed and primary then
    render_cursor(primary)
  end
end

local function normalized_range(anchor, active)
  if anchor.line < active.line then
    return anchor, active
  elseif anchor.line > active.line then
    return active, anchor
  elseif anchor.col <= active.col then
    return anchor, active
  else
    return active, anchor
  end
end

local function apply_highlight(cursor)
  if not cursor.selection then
    delete_highlight(cursor)
    return
  end
  sanitize_selection(cursor)
  local anchor, active = cursor.selection.anchor, cursor.selection.active
  local start_pos, end_pos = normalized_range(anchor, active)

  local hl = state.config and state.config.selection_hl
  if hl == false then
    delete_highlight(cursor)
    return
  end
  hl = hl or 'Visual'

  local opts = {
    end_row = end_pos.line,
    end_col = end_pos.col,
    hl_group = hl,
    right_gravity = false,
    end_right_gravity = false,
  }
  if cursor.highlight_id then
    opts.id = cursor.highlight_id
  end
  cursor.highlight_id = vim.api.nvim_buf_set_extmark(buf(), state.ns, start_pos.line, start_pos.col, opts)
end

function M.setup(plugin_state)
  state = plugin_state
  ensure_namespace()
  state.buffer_states = {}
  state.current_buf = nil
  state.cursors = {}
  state.generation = (state.generation or 0) + 1
end

function M.teardown()
  if not (state and state.ns) then
    return
  end
  for bufnr in pairs(state.buffer_states or {}) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.ns, 0, -1)
    end
  end
  state.buffer_states = {}
  state.current_buf = nil
  state.cursors = {}
  state.generation = (state.generation or 0) + 1
end

function M.iter()
  ensure_namespace()
  M.switch_buffer()
  ensure_primary()
  return state.cursors
end

function M.primary()
  ensure_namespace()
  M.switch_buffer()
  ensure_primary()
  for _, cursor in ipairs(state.cursors) do
    if cursor.is_primary then
      return cursor
    end
  end
  return state.cursors[1]
end

-- Cheap state probes for high-frequency InsertCharPre/CursorMovedI callbacks.
-- They deliberately do not create a primary cursor or query every extmark.
function M.peek_primary()
  ensure_namespace()
  M.switch_buffer()
  for _, cursor in ipairs(state.cursors) do
    if cursor.is_primary then
      return cursor
    end
  end
  return state.cursors[1]
end

function M.requires_insert_handling()
  ensure_namespace()
  M.switch_buffer()
  if #state.cursors > 1 then
    return true
  end
  for _, cursor in ipairs(state.cursors) do
    if cursor.selection then
      return true
    end
  end
  return false
end

function M.sync_cursors()
  ensure_namespace()
  M.switch_buffer()
  local win_pos = vim.api.nvim_win_get_cursor(0)
  ensure_primary()
  local win_line = math.max(win_pos[1], 1) - 1
  local win_col = math.max(win_pos[2], 0)
  M.ensure_primary_cursor_at(win_line, win_col)
  for _, cursor in ipairs(state.cursors) do
    sync_cursor_from_extmark(cursor)
  end
  sort_cursors()
  local primary
  for _, cur in ipairs(state.cursors) do
    if cur.is_primary then
      primary = cur
      break
    end
  end
  if not primary then
    primary = state.cursors[1]
  end
  if primary then
    vim.api.nvim_win_set_cursor(0, { primary.line + 1, primary.col })
  end
end

function M.refresh_from_extmarks()
  ensure_namespace()
  M.switch_buffer()
  if #state.cursors == 0 then
    ensure_primary()
  end
  for _, cursor in ipairs(state.cursors) do
    sync_cursor_from_extmark(cursor)
  end
  sort_cursors()
  local primary
  for _, cur in ipairs(state.cursors) do
    if cur.is_primary then
      primary = cur
      break
    end
  end
  primary = primary or state.cursors[1]
  if primary then
    local line, col = sanitize_position({ line = primary.line, col = primary.col })
    primary.line = line
    primary.col = col
    vim.api.nvim_win_set_cursor(0, { line + 1, col })
  end
end

function M.update_position(cursor, line, col)
  ensure_namespace()
  M.switch_buffer()
  local buf_handle = buf()
  local total_lines = vim.api.nvim_buf_line_count(buf_handle)
  if total_lines == 0 then
    vim.api.nvim_buf_set_lines(buf_handle, 0, -1, false, { '' })
    total_lines = 1
  end
  line = clamp(line, 0, total_lines - 1)
  local text = vim.api.nvim_buf_get_lines(buf_handle, line, line + 1, true)[1] or ''
  col = util.codepoint_start(text, clamp(col, 0, #text))
  cursor.line = line
  cursor.col = col
  cursor.id = vim.api.nvim_buf_set_extmark(
    buf_handle,
    state.ns,
    line,
    col,
    cursor_mark_opts(cursor.is_primary, text, col, cursor.id)
  )
  if cursor.is_primary then
    vim.api.nvim_win_set_cursor(0, { line + 1, col })
  end
end

function M.clear_selection(cursor)
  cursor.anchor = nil
  cursor.selection = nil
  cursor.selection_stack = {}
  delete_highlight(cursor)
end

function M.clear_all_selections()
  for _, cursor in ipairs(M.iter()) do
    M.clear_selection(cursor)
  end
end

function M.set_selection(cursor, anchor, active, opts)
  opts = opts or {}
  cursor.anchor = opts.keep_anchor and cursor.anchor or { line = anchor.line, col = anchor.col }
  cursor.selection = {
    anchor = { line = cursor.anchor.line, col = cursor.anchor.col },
    active = { line = active.line, col = active.col },
  }
  sanitize_selection(cursor)
  apply_highlight(cursor)
end

function M.push_selection(cursor)
  if cursor.selection then
    sanitize_selection(cursor)
    table.insert(cursor.selection_stack, vim.deepcopy(cursor.selection))
  end
end

function M.pop_selection(cursor)
  local last = table.remove(cursor.selection_stack)
  if last then
    cursor.selection = last
    cursor.anchor = { line = last.anchor.line, col = last.anchor.col }
    sanitize_selection(cursor)
    apply_highlight(cursor)
  else
    M.clear_selection(cursor)
  end
end

function M.ensure_anchor(cursor)
  if not cursor.anchor then
    cursor.anchor = { line = cursor.line, col = cursor.col }
    cursor.selection = {
      anchor = { line = cursor.anchor.line, col = cursor.anchor.col },
      active = { line = cursor.line, col = cursor.col },
    }
    sanitize_selection(cursor)
    apply_highlight(cursor)
  end
end

function M.add_cursor_at(line, col)
  ensure_namespace()
  M.switch_buffer()
  ensure_primary()
  line, col = sanitize_position({ line = line, col = col })
  for _, existing in ipairs(state.cursors) do
    if existing.line == line and existing.col == col then
      return nil, nil
    end
  end
  if #state.cursors >= (state.config.max_cursors or 32) then
    return nil, 'Reached maximum cursor count'
  end
  local cursor = create_cursor(line, col, { is_primary = false })
  table.insert(state.cursors, cursor)
  sort_cursors()
  return cursor
end

M.add_cursor = M.add_cursor_at

function M.remove_cursor(cursor, col)
  ensure_namespace()
  M.switch_buffer()
  if type(cursor) == 'number' then
    local line = cursor
    cursor = nil
    for _, candidate in ipairs(state.cursors) do
      if candidate.line == line and candidate.col == col then
        cursor = candidate
        break
      end
    end
    if not cursor then
      return false
    end
  end
  for idx, cur in ipairs(state.cursors) do
    if cur == cursor then
      delete_highlight(cur)
      pcall(vim.api.nvim_buf_del_extmark, buf(), state.ns, cur.id)
      table.remove(state.cursors, idx)
      ensure_primary()
      return true
    end
  end
  ensure_primary()
  return false
end

function M.ensure_primary_cursor_at(line, col)
  ensure_namespace()
  M.switch_buffer()
  line, col = sanitize_position({ line = line, col = col })
  local primary = M.primary()
  if not primary then
    primary = create_cursor(line, col, { is_primary = true })
    table.insert(state.cursors, 1, primary)
  end
  primary.is_primary = true
  M.update_position(primary, line, col)
  return primary
end

function M.for_each(fn)
  ensure_namespace()
  M.switch_buffer()
  ensure_primary()
  for idx, cursor in ipairs(state.cursors) do
    fn(cursor, idx)
  end
end

function M.get_positions()
  ensure_namespace()
  M.switch_buffer()
  ensure_primary()
  local positions = {}
  for _, cursor in ipairs(state.cursors) do
    table.insert(positions, { line = cursor.line, col = cursor.col, cursor = cursor })
  end
  return positions
end

function M.get_cursors()
  return M.snapshot()
end

function M.replace_all_cursors(cursor_defs)
  ensure_namespace()
  M.switch_buffer()
  local current = state.current_buf
  if current and vim.api.nvim_buf_is_valid(current) then
    pcall(vim.api.nvim_buf_clear_namespace, current, state.ns, 0, -1)
  end
  state.cursors = {}
  if state.buffer_states and current then
    state.buffer_states[current] = { cursors = state.cursors }
  end
  local limit = state.config.max_cursors or 32
  local truncated = #cursor_defs > limit
  local seen = {}
  for idx = 1, #cursor_defs do
    if #state.cursors >= limit then
      truncated = true
      break
    end
    local def = cursor_defs[idx]
    local line, col = sanitize_position(def)
    local key = string.format('%d:%d', line, col)
    if not seen[key] then
      seen[key] = true
      local cursor = create_cursor(line, col, { is_primary = def.is_primary })
      cursor.anchor = def.anchor and { line = def.anchor.line, col = def.anchor.col } or nil
      cursor.selection = def.selection and {
        anchor = vim.deepcopy(def.selection.anchor),
        active = vim.deepcopy(def.selection.active),
      } or nil
      cursor.selection_stack = type(def.selection_stack) == 'table' and vim.deepcopy(def.selection_stack) or {}
      sanitize_selection(cursor)
      if cursor.selection then
        apply_highlight(cursor)
      end
      table.insert(state.cursors, cursor)
    end
  end
  if truncated then
    notify(log_levels.WARN, 'Reached maximum cursor count; extra cursors were ignored')
  end
  sort_cursors()
  ensure_primary()
end

function M.switch_buffer()
  ensure_namespace()
  local bufnr = current_buf()
  if state.current_buf == bufnr then
    return
  end
  state.buffer_states = state.buffer_states or {}
  state.current_buf = bufnr
  local buffer_state = state.buffer_states[bufnr]
  if not buffer_state then
    buffer_state = { cursors = {} }
    state.buffer_states[bufnr] = buffer_state
  end
  state.cursors = buffer_state.cursors
  state.generation = (state.generation or 0) + 1
end

function M.cleanup_buffer(bufnr)
  if not (state and state.ns and bufnr) then
    return
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.ns, 0, -1)
  end
  if state.buffer_states then
    state.buffer_states[bufnr] = nil
  end
  if state.current_buf == bufnr then
    state.current_buf = nil
    state.cursors = {}
  end
  if state.snapshots then
    state.snapshots[bufnr] = nil
  end
  state.generation = (state.generation or 0) + 1
end

function M.current_generation()
  return state and state.generation or 0
end

function M.snapshot()
  local snapshot = {}
  for _, cursor in ipairs(M.iter()) do
    snapshot[#snapshot + 1] = {
      line = cursor.line,
      col = cursor.col,
      anchor = cursor.anchor and vim.deepcopy(cursor.anchor) or nil,
      selection = cursor.selection and vim.deepcopy(cursor.selection) or nil,
      selection_stack = vim.deepcopy(cursor.selection_stack or {}),
      is_primary = cursor.is_primary,
    }
  end
  return snapshot
end

function M.save_snapshot()
  state.snapshots = state.snapshots or {}
  state.snapshots[current_buf()] = M.snapshot()
end

function M.restore_snapshot()
  state.snapshots = state.snapshots or {}
  local snapshot = state.snapshots[current_buf()]
  if snapshot and #snapshot > 0 then
    M.replace_all_cursors(vim.deepcopy(snapshot))
    M.update_highlights()
    return true
  end
  return false
end

function M.clear_snapshot()
  if state and state.snapshots then
    state.snapshots[current_buf()] = nil
  end
end

function M.add_cursor_relative(cursor, delta_line)
  ensure_namespace()
  M.switch_buffer()
  ensure_primary()
  local buf_handle = buf()
  local target_line = cursor.line + delta_line
  local line_count = vim.api.nvim_buf_line_count(buf_handle)
  if target_line < 0 or target_line >= line_count then
    return nil, 'Out of bounds'
  end
  local target_text = vim.api.nvim_buf_get_lines(buf_handle, target_line, target_line + 1, true)[1] or ''
  local target_col = util.codepoint_start(target_text, math.min(cursor.col, #target_text))
  local new_cursor, err = M.add_cursor_at(target_line, target_col)
  if not new_cursor then
    return nil, err
  end
  if cursor.selection then
    local anchor_line, anchor_col = sanitize_position({
      line = cursor.selection.anchor.line + delta_line,
      col = cursor.selection.anchor.col,
    })
    local active_line, active_col = sanitize_position({
      line = cursor.selection.active.line + delta_line,
      col = cursor.selection.active.col,
    })
    new_cursor.anchor = { line = anchor_line, col = anchor_col }
    new_cursor.selection = {
      anchor = { line = anchor_line, col = anchor_col },
      active = { line = active_line, col = active_col },
    }
    sanitize_selection(new_cursor)
    apply_highlight(new_cursor)
  end
  return new_cursor
end

function M.with_cursor_position(cursor, fn)
  ensure_namespace()
  M.switch_buffer()
  local current = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_win_set_cursor(0, { cursor.line + 1, cursor.col })
  local ok, res = pcall(fn)
  vim.api.nvim_win_set_cursor(0, current)
  return ok, res
end

function M.update_highlights()
  ensure_namespace()
  M.switch_buffer()
  for _, cursor in ipairs(state.cursors) do
    render_cursor(cursor)
    apply_highlight(cursor)
  end
end

return M
