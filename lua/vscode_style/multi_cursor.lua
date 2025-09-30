local M = {}

local state

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

local function clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

local function buf()
  return vim.api.nvim_get_current_buf()
end

local function ensure_namespace()
  if not (state and state.ns) then
    error('vscode_style multi_cursor used before setup')
  end
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
  col = clamp(col or 0, 0, #line_text)

  local mark_id = vim.api.nvim_buf_set_extmark(buf_handle, state.ns, line, col, {
    right_gravity = false,
  })

  local cursor = {
    id = mark_id,
    line = line,
    col = col,
    anchor = nil,
    selection = nil,
    highlight_id = nil,
    selection_stack = {},
    is_primary = opts.is_primary or false,
  }
  return cursor
end

local function delete_highlight(cursor)
  if cursor.highlight_id then
    pcall(vim.api.nvim_buf_del_extmark, buf(), state.ns, cursor.highlight_id)
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
  local col = clamp((pos and pos.col) or 0, 0, #line_text)
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
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf(), state.ns, cursor.id, { details = true })
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
      right_gravity = false,
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
  elseif state.cursors[1] then
    state.cursors[1].is_primary = true
  end
end

local function has_multiple_cursors()
  return state.cursors and #state.cursors > 1
end

local function cursor_has_selection(cursor)
  return cursor and cursor.selection ~= nil
end

local function any_cursor_has_selection()
  if not state.cursors then
    return false
  end
  for _, cursor in ipairs(state.cursors) do
    if cursor_has_selection(cursor) then
      return true
    end
  end
  return false
end

local function ensure_primary()
  if #state.cursors == 0 then
    local pos = vim.api.nvim_win_get_cursor(0)
    local cursor = create_cursor(math.max(pos[1], 1) - 1, math.max(pos[2], 0), { is_primary = true })
    table.insert(state.cursors, cursor)
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
    if primary then
      primary.is_primary = true
    end
  end
  if primary then
    local line, col = sanitize_position({ line = primary.line, col = primary.col })
    if line ~= primary.line or col ~= primary.col then
      primary.line = line
      primary.col = col
      primary.id = vim.api.nvim_buf_set_extmark(buf(), state.ns, line, col, {
        id = primary.id,
        right_gravity = false,
      })
    end
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
  delete_highlight(cursor)
  if not cursor.selection then
    return
  end
  sanitize_selection(cursor)
  local anchor, active = cursor.selection.anchor, cursor.selection.active
  local start_pos, end_pos = normalized_range(anchor, active)

  local hl = state.config and state.config.selection_hl
  if hl == false then
    return
  end
  hl = hl or 'Visual'

  cursor.highlight_id = vim.api.nvim_buf_set_extmark(buf(), state.ns, start_pos.line, start_pos.col, {
    end_row = end_pos.line,
    end_col = end_pos.col,
    hl_group = hl,
    right_gravity = false,
    end_right_gravity = false,
  })
end

function M.setup(plugin_state)
  state = plugin_state
  ensure_namespace()
  state.current_buf = nil
  state.generation = (state.generation or 0) + 1
  state.snapshots = state.snapshots or {}
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
  col = clamp(col, 0, #text)
  cursor.line = line
  cursor.col = col
  cursor.id = vim.api.nvim_buf_set_extmark(buf_handle, state.ns, line, col, {
    id = cursor.id,
    right_gravity = false,
  })
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
  if #state.cursors >= (state.config.max_cursors or 32) then
    return nil, 'Reached maximum cursor count'
  end
  local cursor = create_cursor(line, col, { is_primary = false })
  table.insert(state.cursors, cursor)
  sort_cursors()
  return cursor
end

function M.remove_cursor(cursor)
  ensure_namespace()
  M.switch_buffer()
  for idx, cur in ipairs(state.cursors) do
    if cur == cursor then
      delete_highlight(cur)
      pcall(vim.api.nvim_buf_del_extmark, buf(), state.ns, cur.id)
      table.remove(state.cursors, idx)
      break
    end
  end
  ensure_primary()
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

function M.replace_all_cursors(cursor_defs)
  ensure_namespace()
  M.switch_buffer()
  local current = state.current_buf
  if current then
    pcall(vim.api.nvim_buf_clear_namespace, current, state.ns, 0, -1)
  end
  for _, cursor in ipairs(state.cursors) do
    delete_highlight(cursor)
    pcall(vim.api.nvim_buf_del_extmark, buf(), state.ns, cursor.id)
  end
  state.cursors = {}
  local limit = state.config.max_cursors or 32
  local truncated = #cursor_defs > limit
  for idx = 1, math.min(#cursor_defs, limit) do
    local def = cursor_defs[idx]
    local cursor = create_cursor(def.line, def.col, { is_primary = def.is_primary })
    cursor.anchor = def.anchor and { line = def.anchor.line, col = def.anchor.col } or nil
    cursor.selection = def.selection and {
      anchor = vim.deepcopy(def.selection.anchor),
      active = vim.deepcopy(def.selection.active),
    } or nil
    sanitize_selection(cursor)
    if cursor.selection then
      apply_highlight(cursor)
    end
    table.insert(state.cursors, cursor)
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
  if state.current_buf and vim.api.nvim_buf_is_valid(state.current_buf) then
    pcall(vim.api.nvim_buf_clear_namespace, state.current_buf, state.ns, 0, -1)
  end
  state.current_buf = bufnr
  state.cursors = {}
  state.generation = (state.generation or 0) + 1
end

function M.current_generation()
  return state and state.generation or 0
end

local function cursor_to_snapshot(cursor)
  return {
    line = cursor.line,
    col = cursor.col,
    is_primary = cursor.is_primary,
  }
end

function M.snapshot()
  return {}
end

function M.save_snapshot()
  -- Snapshotting disabled; leave no state behind.
end

function M.restore_snapshot()
  -- No-op until multi-cursor support returns.
end

function M.clear_snapshot()
  -- Nothing to clear when snapshotting is disabled.
end

function M.sync_primary_to_window()
  ensure_namespace()
  if state.current_buf ~= current_buf() then
    M.switch_buffer()
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = math.max(pos[1], 1) - 1
  local col = math.max(pos[2], 0)
  local cursor = state.cursors[1]
  if cursor then
    cursor.line = line
    cursor.col = col
    cursor.is_primary = true
    cursor.id = vim.api.nvim_buf_set_extmark(buf(), state.ns, line, col, {
      id = cursor.id,
      right_gravity = false,
    })
  else
    state.cursors[1] = create_cursor(line, col, { is_primary = true })
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
  local target_col = math.min(cursor.col, #target_text)
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
    apply_highlight(cursor)
  end
end

return M
