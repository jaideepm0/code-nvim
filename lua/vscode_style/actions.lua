local M = {}

local state
local multi_cursor

local log_levels = vim.log.levels

local backspace_cache

local function backspace_enabled()
  if not (state and state.config) then
    return true
  end
  local flags = state.config.feature_flags or {}
  return flags.backspace ~= false
end

local function canonicalize_backspace(name)
  if type(name) ~= 'string' or name == '' then
    return nil
  end
  -- Drop any terminal capability digits (e.g. <80>kb), symbols, and hyphens.
  local cleaned = name:gsub('%d+', ''):gsub('[<>]', ''):gsub('%-', '')
  cleaned = cleaned:lower()
  if cleaned == '' then
    return nil
  end
  return cleaned
end

local function ensure_backspace_cache()
  if backspace_cache then
    return backspace_cache
  end
  local raw = {
    vim.api.nvim_replace_termcodes('<BS>', true, true, true),
    vim.api.nvim_replace_termcodes('<C-H>', true, true, true),
    vim.api.nvim_replace_termcodes('<kBS>', true, true, true),
    vim.api.nvim_replace_termcodes('<C-BS>', true, true, true),
    string.char(8),
    string.char(127),
  }
  local names = {
    ['<BS>'] = true,
    ['<C-H>'] = true,
    ['<Backspace>'] = true,
    ['<kBS>'] = true,
    ['<C-BS>'] = true,
    ['<kb>'] = true,
  }
  local canonical = {
    bs = true,
    backspace = true,
    ch = true,
    cbs = true,
    ctrlh = true,
    kb = true,
    kbs = true,
    del = true,
    delete = true,
  }
  backspace_cache = { raw = raw, names = names, canonical = canonical }
  return backspace_cache
end

local function is_backspace_key(key)
  if not key or key == '' then
    return false
  end
  local cache = ensure_backspace_cache()
  for _, raw in ipairs(cache.raw) do
    if raw ~= '' and key == raw then
      return true
    end
  end
  local ok, name = pcall(vim.fn.keytrans, key)
  if not ok or not name then
    return false
  end
  if cache.names[name] then
    return true
  end
  if name == '^?' then -- DEL is often produced by terminals for backspace
    return true
  end
  local canonical = canonicalize_backspace(name)
  if canonical and cache.canonical[canonical] then
    return true
  end
  return false
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
  -- Protect against user-provided notification handlers throwing.
  pcall(fn, msg, level or log_levels.INFO)
end

local function buf()
  return vim.api.nvim_get_current_buf()
end

local function clamp(value, min_val, max_val)
  if value < min_val then
    return min_val
  end
  if value > max_val then
    return max_val
  end
  return value
end

local function line_count()
  return vim.api.nvim_buf_line_count(buf())
end

local function get_line(line)
  if line < 0 then
    return ''
  end
  local lines = vim.api.nvim_buf_get_lines(buf(), line, line + 1, true)
  return lines[1] or ''
end

local function copy_pos(pos)
  return { line = pos.line, col = pos.col }
end

local function feedkeys(keys)
  local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcodes, 'n', true)
end

local function move_char(line, col, direction)
  if direction == 'left' then
    if col > 0 then
      return line, col - 1
    end
    if line == 0 then
      return line, col
    end
    local prev_line = line - 1
    local prev_text = get_line(prev_line)
    return prev_line, #prev_text
  else
    local text = get_line(line)
    if col < #text then
      return line, col + 1
    end
    local last_line = line_count() - 1
    if line >= last_line then
      return line, #text
    end
    local next_line = line + 1
    return next_line, 0
  end
end

local function move_line_pos(line, col, direction)
  local target_line = direction == 'up' and (line - 1) or (line + 1)
  target_line = clamp(target_line, 0, line_count() - 1)
  local text = get_line(target_line)
  local new_col = clamp(col, 0, #text)
  return target_line, new_col
end

local function move_to_line_boundary(line, boundary)
  if boundary == 'home' then
    return line, 0
  end
  local text = get_line(line)
  return line, #text
end

local function move_to_file_boundary(boundary)
  if boundary == 'home' then
    return 0, 0
  end
  local last_line = line_count() - 1
  local text = get_line(last_line)
  return last_line, #text
end

local function get_char(line, index)
  local text = get_line(line)
  if index < 0 or index >= #text then
    return ''
  end
  return text:sub(index + 1, index + 1)
end

local function char_kind(ch)
  if ch == '' then
    return nil
  end
  if ch:match('%s') then
    return 'space'
  end
  if ch:match('[%w_]') then
    return 'word'
  end
  return 'symbol'
end

local function step_left(line, col)
  if line == 0 and col == 0 then
    return 0, 0
  end
  if col > 0 then
    return line, col - 1
  end
  if line == 0 then
    return 0, 0
  end
  local prev_line = line - 1
  local prev_text = get_line(prev_line)
  return prev_line, #prev_text
end

local function step_right(line, col)
  local text = get_line(line)
  if col < #text then
    return line, col + 1
  end
  local last_line = line_count() - 1
  if line >= last_line then
    return line, #text
  end
  local next_line = line + 1
  return next_line, 0
end

local function char_kind_left(line, col)
  if line == 0 and col == 0 then
    return nil
  end
  if col == 0 then
    if line == 0 then
      return nil
    end
    local prev_line = line - 1
    local prev_text = get_line(prev_line)
    return char_kind(get_char(prev_line, #prev_text - 1))
  end
  return char_kind(get_char(line, col - 1))
end

local function char_kind_right(line, col)
  local text = get_line(line)
  if col >= #text then
    if line >= line_count() - 1 then
      return nil
    end
    return 'space'
  end
  return char_kind(get_char(line, col))
end

local function sanitize_point(pos)
  local total = line_count()
  if total == 0 then
    return 0, 0
  end
  local line = clamp((pos and pos.line) or 0, 0, total - 1)
  local text = get_line(line)
  local col = clamp((pos and pos.col) or 0, 0, #text)
  return line, col
end

local function move_word_left_position(line, col)
  if line == 0 and col == 0 then
    return 0, 0
  end
  local cur_line, cur_col = line, col
  local kind = char_kind_left(cur_line, cur_col)

  while kind == 'space' do
    local next_line, next_col = step_left(cur_line, cur_col)
    if next_line == cur_line and next_col == cur_col then
      return next_line, next_col
    end
    cur_line, cur_col = next_line, next_col
    kind = char_kind_left(cur_line, cur_col)
    if not kind then
      return cur_line, cur_col
    end
  end

  if not kind then
    return cur_line, cur_col
  end

  while true do
    local next_line, next_col = step_left(cur_line, cur_col)
    if next_line == cur_line and next_col == cur_col then
      return next_line, next_col
    end
    local next_kind = char_kind_left(next_line, next_col)
    if not next_kind or next_kind ~= kind then
      return next_line, next_col
    end
    cur_line, cur_col = next_line, next_col
  end
end

local function move_word_right_position(line, col)
  local cur_line, cur_col = line, col
  local kind = char_kind_right(cur_line, cur_col)

  while kind == 'space' do
    local next_line, next_col = step_right(cur_line, cur_col)
    if next_line == cur_line and next_col == cur_col then
      return next_line, next_col
    end
    cur_line, cur_col = next_line, next_col
    kind = char_kind_right(cur_line, cur_col)
    if not kind then
      return cur_line, cur_col
    end
  end

  if not kind then
    return cur_line, cur_col
  end

  local last_line, last_col = cur_line, cur_col
  while true do
    local next_line, next_col = step_right(cur_line, cur_col)
    if next_line == cur_line and next_col == cur_col then
      return next_line, next_col
    end
    local next_kind = char_kind_right(next_line, next_col)
    if not next_kind or next_kind ~= kind then
      return next_line, next_col
    end
    last_line, last_col = next_line, next_col
    cur_line, cur_col = next_line, next_col
  end
end

local function move_word_right(cursor)
  local line, col = move_word_right_position(cursor.line, cursor.col)
  return line, col
end

local function move_word_left(cursor)
  local line, col = move_word_left_position(cursor.line, cursor.col)
  return line, col
end

local function ensure_cursor_anchor(cursor)
  multi_cursor.ensure_anchor(cursor)
  if not cursor.anchor then
    cursor.anchor = { line = cursor.line, col = cursor.col }
  end
end

local function apply_selection(cursor, new_line, new_col)
  ensure_cursor_anchor(cursor)
  multi_cursor.update_position(cursor, new_line, new_col)
  multi_cursor.set_selection(cursor, cursor.anchor, { line = new_line, col = new_col }, { keep_anchor = true })
end

local function clear_all_selections_if_needed()
  local any_selection = false
  for _, cursor in ipairs(multi_cursor.iter()) do
    if cursor.selection then
      any_selection = true
      break
    end
  end
  if not any_selection then
    multi_cursor.clear_all_selections()
  end
end

local function selection_bounds(selection)
  local anchor = selection.anchor
  local active = selection.active
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

local function get_selection_text(selection)
  local start_pos, end_pos = selection_bounds(selection)
  return vim.api.nvim_buf_get_text(buf(), start_pos.line, start_pos.col, end_pos.line, end_pos.col, {})
end

local function gather_selections()
  local selections = {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    if cursor.selection then
      local start_pos, end_pos = selection_bounds(cursor.selection)
      local start_line, start_col = sanitize_point(start_pos)
      local finish_line, finish_col = sanitize_point(end_pos)
      if finish_line < start_line or (finish_line == start_line and finish_col < start_col) then
        finish_line, finish_col = start_line, start_col
      end
      if not (start_line == finish_line and start_col == finish_col) then
        table.insert(selections, {
          cursor = cursor,
          start = { line = start_line, col = start_col },
          finish = { line = finish_line, col = finish_col },
        })
      end
    end
  end
  return selections
end

local function selection_entries_with_text(selections)
  local entries = {}
  for _, sel in ipairs(selections) do
    local text = vim.api.nvim_buf_get_text(buf(), sel.start.line, sel.start.col, sel.finish.line, sel.finish.col, {})
    table.insert(entries, { selection = sel, text = text })
  end
  return entries
end

local function lines_from_selections(selections)
  local uniq = {}
  local lines = {}
  for _, sel in ipairs(selections) do
    local start_line = sel.start.line
    local finish_line = sel.finish.line
    local start_col = sel.start.col
    local finish_col = sel.finish.col
    if start_line == finish_line and start_col == finish_col then
      goto continue
    end
    if finish_line > start_line and finish_col == 0 then
      finish_line = finish_line - 1
    end
    for line = start_line, finish_line do
      if not uniq[line] then
        uniq[line] = true
        table.insert(lines, line)
      end
    end
    ::continue::
  end
  table.sort(lines)
  return lines
end

local function apply_line_deltas(deltas)
  if not deltas or next(deltas) == nil then
    multi_cursor.update_highlights()
    return
  end
  multi_cursor.for_each(function(cursor)
    local delta = deltas[cursor.line]
    if delta and delta ~= 0 then
      local new_col = cursor.col + delta
      if new_col < 0 then
        new_col = 0
      end
      multi_cursor.update_position(cursor, cursor.line, new_col)
    end
    if cursor.anchor then
      local anchor_delta = deltas[cursor.anchor.line]
      if anchor_delta and anchor_delta ~= 0 then
        local new_col = cursor.anchor.col + anchor_delta
        if new_col < 0 then
          new_col = 0
        end
        cursor.anchor = { line = cursor.anchor.line, col = new_col }
      end
    end
    if cursor.selection then
      local anchor_delta = deltas[cursor.selection.anchor.line] or 0
      local active_delta = deltas[cursor.selection.active.line] or 0
      if anchor_delta ~= 0 or active_delta ~= 0 then
        local anchor_col = cursor.selection.anchor.col + anchor_delta
        if anchor_col < 0 then
          anchor_col = 0
        end
        local active_col = cursor.selection.active.col + active_delta
        if active_col < 0 then
          active_col = 0
        end
        local anchor = { line = cursor.selection.anchor.line, col = anchor_col }
        local active = { line = cursor.selection.active.line, col = active_col }
        multi_cursor.set_selection(cursor, anchor, active)
      else
        multi_cursor.set_selection(cursor, cursor.selection.anchor, cursor.selection.active, { keep_anchor = true })
      end
    end
  end)
  multi_cursor.update_highlights()
end

local function apply_selection_entries(entries)
  table.sort(entries, function(a, b)
    local sa = a.selection.start
    local sb = b.selection.start
    if sa.line == sb.line then
      return sa.col > sb.col
    end
    return sa.line > sb.line
  end)
  for _, entry in ipairs(entries) do
    local sel = entry.selection
    vim.api.nvim_buf_set_text(buf(), sel.start.line, sel.start.col, sel.finish.line, sel.finish.col, entry.text)
  end
end

local function selection_active_from_text(start_line, start_col, text)
  local end_line = start_line
  local end_col = start_col
  if #text == 0 then
    return end_line, end_col
  end
  end_line = start_line + (#text - 1)
  if #text == 1 then
    end_col = start_col + #text[1]
  else
    end_col = #text[#text]
  end
  return end_line, end_col
end

local function dedupe_ranges(ranges)
  local seen = {}
  local unique = {}
  for _, range in ipairs(ranges) do
    local key = string.format('%d:%d', range.start_line, range.end_line)
    if not seen[key] then
      seen[key] = true
      table.insert(unique, range)
    end
  end
  return unique
end

local function normalize_ranges_for_direction(ranges, direction)
  table.sort(ranges, function(a, b)
    if a.start_line == b.start_line then
      return a.end_line < b.end_line
    end
    if direction == 'up' then
      return a.start_line < b.start_line
    else
      return a.start_line > b.start_line
    end
  end)
  return ranges
end

local function collect_active_ranges()
  local ranges = {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    if cursor.selection then
      local start_pos, end_pos = selection_bounds(cursor.selection)
      table.insert(ranges, {
        start_line = start_pos.line,
        end_line = math.max(start_pos.line, end_pos.line - (end_pos.col == 0 and 1 or 0)),
      })
    else
      table.insert(ranges, { start_line = cursor.line, end_line = cursor.line })
    end
  end
  return dedupe_ranges(ranges)
end

local function snapshot_cursors_in_range(range)
  local snapshot = {}
  multi_cursor.for_each(function(cursor)
    if cursor.line >= range.start_line and cursor.line <= range.end_line then
      table.insert(snapshot, {
        cursor = cursor,
        line_offset = cursor.line - range.start_line,
        col = cursor.col,
      })
    end
  end)
  return snapshot
end

local function adjust_selections_for_move(range, delta)
  local max_line = math.max(line_count() - 1, 0)
  local function shift_point(point)
    if point.line >= range.start_line and point.line <= range.end_line then
      point.line = clamp(point.line + delta, 0, max_line)
    end
  end
  multi_cursor.for_each(function(cursor)
    if cursor.anchor and not cursor.selection then
      shift_point(cursor.anchor)
    end
    if cursor.selection then
      shift_point(cursor.selection.anchor)
      shift_point(cursor.selection.active)
      local anchor = { line = cursor.selection.anchor.line, col = cursor.selection.anchor.col }
      local active = { line = cursor.selection.active.line, col = cursor.selection.active.col }
      multi_cursor.set_selection(cursor, anchor, active)
    end
  end)
end

local function apply_move_line(range, direction)
  local start_line = range.start_line
  local end_line = range.end_line
  local total_lines = line_count()
  if direction == 'up' then
    if start_line == 0 then
      return
    end
    local block = vim.api.nvim_buf_get_lines(buf(), start_line, end_line + 1, false)
    vim.api.nvim_buf_set_lines(buf(), start_line, end_line + 1, false, {})
    vim.api.nvim_buf_set_lines(buf(), start_line - 1, start_line - 1, false, block)
  else
    if end_line >= total_lines - 1 then
      return
    end
    local block = vim.api.nvim_buf_get_lines(buf(), start_line, end_line + 1, false)
    vim.api.nvim_buf_set_lines(buf(), start_line, end_line + 1, false, {})
    vim.api.nvim_buf_set_lines(buf(), start_line + 1, start_line + 1, false, block)
  end
end

local function apply_copy_line(range, direction)
  local start_line = range.start_line
  local end_line = range.end_line
  local block = vim.api.nvim_buf_get_lines(buf(), start_line, end_line + 1, false)
  if direction == 'up' then
    vim.api.nvim_buf_set_lines(buf(), start_line, start_line, false, block)
  else
    vim.api.nvim_buf_set_lines(buf(), end_line + 1, end_line + 1, false, block)
  end
end

local function apply_delete_line(range)
  vim.api.nvim_buf_set_lines(buf(), range.start_line, range.end_line + 1, false, {})
  if range.start_line >= line_count() then
    local target = line_count()
    if target == 0 then
      target = 1
    end
    vim.api.nvim_buf_set_lines(buf(), target - 1, target - 1, false, { '' })
  end
end

local function reposition_cursors_after_line_change(direction)
  multi_cursor.sync_cursors()
  for _, cursor in ipairs(multi_cursor.iter()) do
    if direction == 'up' or direction == 'down' then
      local line, col = cursor.line, cursor.col
      local text = get_line(line)
      if col > #text then
        multi_cursor.update_position(cursor, line, #text)
      end
    end
  end
end

local function get_cursor_word(cursor)
  local ok, result = multi_cursor.with_cursor_position(cursor, function()
    local word = vim.fn.expand('<cword>')
    local start_pos = vim.fn.searchpos('\\<', 'bnW')
    local end_pos = vim.fn.searchpos('\\>', 'nW')
    return { word = word or '', start_pos = start_pos, end_pos = end_pos }
  end)
  if not ok or not result then
    return '', { start_line = cursor.line, start_col = cursor.col }, { end_line = cursor.line, end_col = cursor.col }
  end
  local word = result.word or ''
  local start_pos = result.start_pos or { cursor.line + 1, cursor.col + 1 }
  local end_pos = result.end_pos or { cursor.line + 1, cursor.col + 1 }
  local start_line = (start_pos[1] or (cursor.line + 1)) - 1
  local start_col = (start_pos[2] or (cursor.col + 1)) - 1
  local end_line = (end_pos[1] or (cursor.line + 1)) - 1
  local end_col = (end_pos[2] or (cursor.col + 1)) - 1
  return word, { start_line = start_line, start_col = start_col }, { end_line = end_line, end_col = end_col }
end

local function get_selection_string(selection)
  local chunks = get_selection_text(selection)
  return table.concat(chunks, '\n')
end

local function find_next_occurrence(needle, start_line, start_col)
  local search_start_line = start_line
  local search_start_col = start_col
  local total_lines = line_count()
  for line = search_start_line, total_lines - 1 do
    local text = get_line(line)
    local col_start = 1
    if line == search_start_line then
      col_start = search_start_col + 1
    end
    local found = text:find(vim.pesc(needle), col_start, true)
    if found then
      return { line = line, col = found - 1 }, { line = line, col = found - 1 + #needle }
    end
  end
  return nil
end

local function collect_all_occurrences(needle)
  local matches = {}
  for line = 0, line_count() - 1 do
    local text = get_line(line)
    local search_col = 1
    while true do
      local s = text:find(vim.pesc(needle), search_col, true)
      if not s then
        break
      end
      table.insert(matches, {
        anchor = { line = line, col = s - 1 },
        active = { line = line, col = s - 1 + #needle },
      })
      search_col = s + #needle
    end
  end
  return matches
end

local function unique_cursor_key(cursor)
  return string.format('%d:%d', cursor.line, cursor.col)
end

function M.setup(plugin_state, mc)
  state = plugin_state
  multi_cursor = mc
end

function M.select_character(direction)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_char(cursor.line, cursor.col, direction)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
end

function M.select_line(direction)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_line_pos(cursor.line, cursor.col, direction)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
end

function M.select_word(direction)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col
    if direction == 'left' then
      new_line, new_col = move_word_left(cursor)
    else
      new_line, new_col = move_word_right(cursor)
    end
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
end

function M.select_to_line_boundary(boundary)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_to_line_boundary(cursor.line, boundary)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
end

function M.select_to_file_boundary(boundary)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_to_file_boundary(boundary)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
end

function M.move_line(direction)
  multi_cursor.sync_cursors()
  local ranges = normalize_ranges_for_direction(collect_active_ranges(), direction)
  for _, range in ipairs(ranges) do
    local total = line_count()
    if direction == 'up' and range.start_line == 0 then
      goto continue
    end
    if direction == 'down' and range.end_line >= total - 1 then
      goto continue
    end
    local snapshot = snapshot_cursors_in_range(range)
    local delta = direction == 'up' and -1 or 1
    apply_move_line(range, direction)
    local max_line = math.max(line_count() - 1, 0)
    local new_start = clamp(range.start_line + delta, 0, max_line)
    for _, item in ipairs(snapshot) do
      local target_line = clamp(new_start + item.line_offset, 0, max_line)
      multi_cursor.update_position(item.cursor, target_line, item.col)
    end
    adjust_selections_for_move(range, delta)
    ::continue::
  end
  multi_cursor.update_highlights()
  multi_cursor.sync_cursors()
end

function M.copy_line(direction)
  multi_cursor.sync_cursors()
  local ranges = normalize_ranges_for_direction(collect_active_ranges(), direction)
  for _, range in ipairs(ranges) do
    apply_copy_line(range, direction)
  end
  reposition_cursors_after_line_change(direction)
end

function M.delete_line()
  multi_cursor.sync_cursors()
  local ranges = collect_active_ranges()
  for _, range in ipairs(ranges) do
    apply_delete_line(range)
  end
  reposition_cursors_after_line_change()
end

function M.alt_click_cursor()
  local mouse_line = vim.v.mouse_lnum
  local mouse_col = vim.v.mouse_col
  if mouse_line == 0 then
    return
  end
  local line = mouse_line - 1
  local col = math.max(0, mouse_col - 1)
  local text = get_line(line)
  col = clamp(col, 0, #text)
  local _, err = multi_cursor.add_cursor_at(line, col)
  if err then
    notify(log_levels.WARN, err)
  end
end

function M.add_cursor_vertical(direction)
  multi_cursor.sync_cursors()
  local delta = direction == 'up' and -1 or 1
  local new_cursors = {}
  local snapshot = {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    table.insert(snapshot, cursor)
  end
  for _, cursor in ipairs(snapshot) do
    local new_cursor, err = multi_cursor.add_cursor_relative(cursor, delta)
    if not new_cursor and err then
      notify(log_levels.WARN, err)
      break
    elseif new_cursor then
      table.insert(new_cursors, new_cursor)
    end
  end
  if #new_cursors == 0 and direction == 'up' then
    local primary = multi_cursor.primary()
    if primary and primary.line == 0 then
      notify(log_levels.INFO, 'Cannot add cursor above the first line')
    end
  end
end

function M.add_selection_to_next_match()
  multi_cursor.sync_cursors()
  local primary = multi_cursor.primary()
  if not primary then
    notify(log_levels.WARN, 'No active cursor available for multi-selection')
    return
  end
  local needle
  if primary.selection then
    needle = get_selection_string(primary.selection)
  else
    local word = get_cursor_word(primary)
    needle = word
  end
  if not needle or needle == '' then
    return
  end
  local cursors = multi_cursor.get_positions()
  local last = cursors[#cursors]
  local start_line = last.line
  local start_col = last.col
  if last.cursor.selection then
    local _, end_pos = selection_bounds(last.cursor.selection)
    start_line = end_pos.line
    start_col = end_pos.col
  end
  local next_start, next_end = find_next_occurrence(needle, start_line, start_col)
  if not next_start then
    notify(log_levels.INFO, 'No further matches for "' .. needle .. '"')
    return
  end
  local cursor, err = multi_cursor.add_cursor_at(next_start.line, next_end.col)
  if not cursor then
    if err then
      notify(log_levels.WARN, err)
    end
    return
  end
  cursor.anchor = { line = next_start.line, col = next_start.col }
  cursor.selection = {
    anchor = copy_pos(cursor.anchor),
    active = { line = next_end.line, col = next_end.col },
  }
  multi_cursor.update_position(cursor, next_end.line, next_end.col)
  multi_cursor.update_highlights()
end

function M.select_all_occurrences()
  multi_cursor.sync_cursors()
  local primary = multi_cursor.primary()
  if not primary then
    notify(log_levels.WARN, 'No active cursor available for multi-selection')
    return
  end
  local needle
  if primary.selection then
    needle = get_selection_string(primary.selection)
  else
    needle = get_cursor_word(primary)
  end
  if not needle or needle == '' then
    return
  end
  local matches = collect_all_occurrences(needle)
  if #matches == 0 then
    return
  end
  local cursor_defs = {}
  for idx, match in ipairs(matches) do
    cursor_defs[idx] = {
      line = match.active.line,
      col = match.active.col,
      anchor = copy_pos(match.anchor),
      selection = {
        anchor = copy_pos(match.anchor),
        active = copy_pos(match.active),
      },
      is_primary = idx == 1,
    }
  end
  multi_cursor.replace_all_cursors(cursor_defs)
  multi_cursor.update_highlights()
end

function M.expand_selection()
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    if not cursor.selection then
      -- No selection: expand to word
      local line, col = move_word_left(cursor)
      cursor.anchor = { line = line, col = col }
      local end_line, end_col = move_word_right(cursor)
      multi_cursor.update_position(cursor, end_line, end_col)
      cursor.selection = {
        anchor = { line = line, col = col },
        active = { line = end_line, col = end_col },
      }
      multi_cursor.set_selection(cursor, cursor.selection.anchor, cursor.selection.active)
      return
    end
    multi_cursor.push_selection(cursor)
    local start_pos, end_pos = selection_bounds(cursor.selection)
    if start_pos.col ~= 0 or end_pos.col ~= #get_line(end_pos.line) then
      -- Expand to full lines
      cursor.selection = {
        anchor = { line = start_pos.line, col = 0 },
        active = { line = end_pos.line, col = #get_line(end_pos.line) },
      }
      multi_cursor.set_selection(cursor, cursor.selection.anchor, cursor.selection.active)
      multi_cursor.update_position(cursor, cursor.selection.active.line, cursor.selection.active.col)
      return
    end
    -- Expand to indentation block
    local target_indent = vim.fn.indent(start_pos.line)
    local top = start_pos.line
    while top > 0 and vim.fn.indent(top - 1) >= target_indent do
      top = top - 1
    end
    local bottom = end_pos.line
    local total = line_count()
    while bottom < total - 1 and vim.fn.indent(bottom + 1) >= target_indent do
      bottom = bottom + 1
    end
    cursor.selection = {
      anchor = { line = top, col = 0 },
      active = { line = bottom, col = #get_line(bottom) },
    }
    multi_cursor.set_selection(cursor, cursor.selection.anchor, cursor.selection.active)
    multi_cursor.update_position(cursor, cursor.selection.active.line, cursor.selection.active.col)
  end)
  multi_cursor.update_highlights()
end

function M.shrink_selection()
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    if cursor.selection then
      multi_cursor.pop_selection(cursor)
      if cursor.selection then
        local _, end_pos = selection_bounds(cursor.selection)
        multi_cursor.update_position(cursor, end_pos.line, end_pos.col)
      end
    end
  end)
  multi_cursor.update_highlights()
end

local function delete_selections(selections)
  table.sort(selections, function(a, b)
    if a.start.line == b.start.line then
      return a.start.col > b.start.col
    end
    return a.start.line > b.start.line
  end)
  for _, sel in ipairs(selections) do
    vim.api.nvim_buf_set_text(buf(), sel.start.line, sel.start.col, sel.finish.line, sel.finish.col, {})
  end
end

local function collapse_deleted_selections(selections)
  for _, sel in ipairs(selections) do
    multi_cursor.clear_selection(sel.cursor)
    multi_cursor.update_position(sel.cursor, sel.start.line, sel.start.col)
  end
end

local function sort_points_desc(points)
  table.sort(points, function(a, b)
    if a.line == b.line then
      return a.col > b.col
    end
    return a.line > b.line
  end)
end

local function char_to_text_lines(char)
  if char == '\r' or char == '\n' then
    return { '', '' }
  end
  return { char }
end

local function indent_string()
  local sw = vim.bo.shiftwidth
  if sw == 0 then
    sw = vim.bo.tabstop
  end
  if not sw or sw <= 0 then
    sw = 2
  end
  if vim.bo.expandtab then
    return string.rep(' ', sw)
  end
  return '\t'
end

local function remove_indent_prefix(text, indent)
  if indent == '' then
    return text, 0
  end
  if indent:sub(1, 1) == '\t' then
    if text:sub(1, 1) == '\t' then
      return text:sub(2), 1
    end
    return text, 0
  end
  if text:sub(1, 1) == '\t' then
    return text:sub(2), 1
  end
  local max_remove = #indent
  local idx = 0
  while idx < max_remove and text:sub(idx + 1, idx + 1) == ' ' do
    idx = idx + 1
  end
  if idx == 0 then
    return text, 0
  end
  return text:sub(idx + 1), idx
end

local function process_backspace(snapshot)
  multi_cursor.sync_cursors()
  local selections = snapshot or gather_selections()
  if #selections == 0 then
    return false
  end
  delete_selections(selections)
  multi_cursor.sync_cursors()
  collapse_deleted_selections(selections)
  multi_cursor.update_highlights()
  return true
end

function M.handle_backspace()
  if not process_backspace() then
    feedkeys('<BS>')
  end
end

function M.backspace_expr()
  multi_cursor.sync_cursors()
  local snapshot = gather_selections()
  if #snapshot == 0 then
    return vim.api.nvim_replace_termcodes('<BS>', true, false, true)
  end
  local target_buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_buf_call(target_buf, function()
      pcall(vim.cmd, 'undojoin')
      process_backspace(snapshot)
    end)
  end
  return ''
end

function M.handle_tab()
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 then
    feedkeys('<Tab>')
    return
  end
  local lines = lines_from_selections(selections)
  if #lines == 0 then
    feedkeys('<Tab>')
    return
  end
  local indent = indent_string()
  local indent_len = #indent
  local deltas = {}
  local bufnr = buf()
  pcall(vim.cmd, 'undojoin')
  for _, line in ipairs(lines) do
    local text = get_line(line)
    vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { indent .. text })
    deltas[line] = (deltas[line] or 0) + indent_len
  end
  apply_line_deltas(deltas)
end

function M.handle_shift_tab()
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 then
    feedkeys('<S-Tab>')
    return
  end
  local lines = lines_from_selections(selections)
  if #lines == 0 then
    feedkeys('<S-Tab>')
    return
  end
  local indent = indent_string()
  local bufnr = buf()
  local deltas = {}
  local changed = false
  pcall(vim.cmd, 'undojoin')
  for _, line in ipairs(lines) do
    local text = get_line(line)
    local updated, removed = remove_indent_prefix(text, indent)
    if removed > 0 then
      vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { updated })
      deltas[line] = (deltas[line] or 0) - removed
      changed = true
    end
  end
  if not changed then
    return
  end
  apply_line_deltas(deltas)
end

function M.on_insert_pre()
  local char = vim.v.char
  local key = vim.v.key
  if backspace_enabled() and is_backspace_key(key) then
    multi_cursor.sync_cursors()
    local snapshot = gather_selections()
    if #snapshot > 0 then
      vim.v.char = ''
      local ok, err = pcall(function()
        pcall(vim.cmd, 'undojoin')
        process_backspace(snapshot)
      end)
      if not ok then
        notify(log_levels.ERROR, 'vscode_style backspace failed: ' .. err)
      end
      return
    end
    return -- allow native backspace when nothing is selected
  end
  if key == 'Tab' or key == 'S-Tab' then
    return
  end
  if not char or char == '' then
    return
  end
  vim.v.char = ''
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 then
    vim.v.char = char
    return
  end
  local snapshot = {}
  for _, sel in ipairs(selections) do
    snapshot[#snapshot + 1] = {
      cursor = sel.cursor,
      start = { line = sel.start.line, col = sel.start.col },
      finish = { line = sel.finish.line, col = sel.finish.col },
    }
  end
  local insert_char = char
  local target_buf = vim.api.nvim_get_current_buf()
  local generation = multi_cursor.current_generation and multi_cursor.current_generation() or nil
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(target_buf) then
      return
    end
    if generation and multi_cursor.current_generation and multi_cursor.current_generation() ~= generation then
      return
    end
    vim.api.nvim_buf_call(target_buf, function()
      if vim.api.nvim_get_mode().mode:sub(1, 1) ~= 'i' then
        return
      end
      if #snapshot == 0 then
        return
      end
      delete_selections(snapshot)
      multi_cursor.sync_cursors()
      collapse_deleted_selections(snapshot)
      multi_cursor.update_highlights()
      local text_lines = char_to_text_lines(insert_char)
      local points = {}
      for _, cursor in ipairs(multi_cursor.iter()) do
        table.insert(points, { cursor = cursor, line = cursor.line, col = cursor.col })
      end
      if #points == 0 then
        return
      end
      sort_points_desc(points)
      for _, point in ipairs(points) do
        vim.api.nvim_buf_set_text(target_buf, point.line, point.col, point.line, point.col, text_lines)
      end
      local line_delta = #text_lines - 1
      local tail_len = #text_lines[#text_lines]
      local head_len = #text_lines[1]
      for _, point in ipairs(points) do
        local cursor = point.cursor
        local new_line = point.line + line_delta
        local new_col
        if line_delta == 0 then
          new_col = point.col + head_len
        else
          new_col = tail_len
        end
        multi_cursor.update_position(cursor, new_line, new_col)
      end
      multi_cursor.update_highlights()
    end)
  end)
end

function M.column_selection_drag_start()
  state.column_selecting = true
  local anchor_line = vim.v.mouse_lnum
  local anchor_col = vim.v.mouse_col
  if anchor_line == 0 then
    state.column_anchor = nil
    return
  end
  state.column_anchor = { line = anchor_line - 1, col = math.max(0, anchor_col - 1) }
  multi_cursor.replace_all_cursors({
    {
      line = state.column_anchor.line,
      col = state.column_anchor.col,
      anchor = copy_pos(state.column_anchor),
      selection = nil,
      is_primary = true,
    },
  })
end

function M.column_selection_drag_end()
  if not state.column_selecting or not state.column_anchor then
    return
  end
  local target_line = vim.v.mouse_lnum
  local target_col = vim.v.mouse_col
  if target_line == 0 then
    return
  end
  target_line = target_line - 1
  target_col = math.max(0, target_col - 1)
  local start_line = math.min(state.column_anchor.line, target_line)
  local end_line = math.max(state.column_anchor.line, target_line)
  local col = state.column_anchor.col
  local cursor_defs = {}
  local index = 1
  for line = start_line, end_line do
    local text = get_line(line)
    local effective_col = clamp(col, 0, #text)
    cursor_defs[index] = {
      line = line,
      col = effective_col,
      anchor = { line = line, col = col <= #text and col or #text },
      selection = {
        anchor = { line = line, col = math.min(col, #text) },
        active = { line = line, col = clamp(target_col, 0, #text) },
      },
      is_primary = line == start_line,
    }
    index = index + 1
  end
  multi_cursor.replace_all_cursors(cursor_defs)
  multi_cursor.update_highlights()
  state.column_selecting = false
  state.column_anchor = nil
end

return M
