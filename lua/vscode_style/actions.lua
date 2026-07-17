local M = {}

local state
local multi_cursor
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
  -- Protect against user-provided notification handlers throwing.
  pcall(fn, msg, level or log_levels.INFO)
end

local function buf()
  return vim.api.nvim_get_current_buf()
end

local clamp = util.clamp

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
  local text = get_line(line)
  col = util.codepoint_start(text, col)
  if direction == 'left' then
    if col > 0 then
      return line, util.prev_codepoint(text, col)
    end
    if line == 0 then
      return line, col
    end
    local prev_line = line - 1
    local prev_text = get_line(prev_line)
    return prev_line, #prev_text
  else
    if col < #text then
      return line, util.next_codepoint(text, col)
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
  local new_col
  local ok, vcol = pcall(vim.fn.virtcol, { line + 1, col + 1 })
  if ok and type(vcol) == 'number' then
    new_col = util.virtual_to_byte_col(0, target_line, vcol, text)
  else
    new_col = util.codepoint_start(text, clamp(col, 0, #text))
  end
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
  return util.codepoint_at(text, index)
end

local function char_kind(ch)
  if ch == '' then
    return nil
  end
  if ch:match('%s') then
    return 'space'
  end
  if ch:match('[%w_]') or ch:byte(1) >= 0x80 then
    return 'word'
  end
  return 'symbol'
end

local function step_left(line, col)
  if line == 0 and col == 0 then
    return 0, 0
  end
  if col > 0 then
    return line, util.prev_codepoint(get_line(line), col)
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
    return line, util.next_codepoint(text, col)
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
    return char_kind(get_char(prev_line, util.prev_codepoint(prev_text, #prev_text)))
  end
  return char_kind(get_char(line, util.prev_codepoint(get_line(line), col)))
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
  local col = util.codepoint_start(text, clamp((pos and pos.col) or 0, 0, #text))
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

  while true do
    local next_line, next_col = step_right(cur_line, cur_col)
    if next_line == cur_line and next_col == cur_col then
      return next_line, next_col
    end
    local next_kind = char_kind_right(next_line, next_col)
    if not next_kind or next_kind ~= kind then
      return next_line, next_col
    end
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

local function collect_selection_lines(selections)
  local seen = {}
  local lines = {}
  for _, sel in ipairs(selections) do
    local start_line = sel.start.line
    local start_col = sel.start.col
    local finish_line = sel.finish.line
    local finish_col = sel.finish.col
    if finish_line < start_line or (finish_line == start_line and finish_col < start_col) then
      start_line, finish_line = finish_line, start_line
      start_col, finish_col = finish_col, start_col
    end
    if start_line == finish_line and start_col == finish_col then
      finish_line = start_line
    end
    if finish_line > start_line and finish_col == 0 then
      finish_line = finish_line - 1
    end
    for line = start_line, finish_line do
      if not seen[line] then
        seen[line] = true
        lines[#lines + 1] = line
      end
    end
  end
  table.sort(lines)
  return lines
end

local function adjust_cursor_columns(deltas)
  if not deltas or next(deltas) == nil then
    multi_cursor.update_highlights()
    return
  end
  multi_cursor.for_each(function(cursor)
    local delta = deltas[cursor.line] or 0
    if delta ~= 0 then
      local new_col = cursor.col + delta
      if new_col < 0 then new_col = 0 end
      multi_cursor.update_position(cursor, cursor.line, new_col)
    end
    if cursor.selection then
      local anchor_line = cursor.selection.anchor.line
      local active_line = cursor.selection.active.line
      local anchor_delta = deltas[anchor_line] or 0
      local active_delta = deltas[active_line] or 0
      if anchor_delta ~= 0 or active_delta ~= 0 then
        local anchor_col = cursor.selection.anchor.col + anchor_delta
        if anchor_col < 0 then anchor_col = 0 end
        local active_col = cursor.selection.active.col + active_delta
        if active_col < 0 then active_col = 0 end
        multi_cursor.set_selection(cursor, { line = anchor_line, col = anchor_col }, { line = active_line, col = active_col })
      else
        multi_cursor.set_selection(cursor, cursor.selection.anchor, cursor.selection.active, { keep_anchor = true })
      end
    end
  end)
  multi_cursor.update_highlights()
end

local function merge_ranges(ranges)
  table.sort(ranges, function(a, b)
    if a.start_line == b.start_line then
      return a.end_line < b.end_line
    end
    return a.start_line < b.start_line
  end)
  local merged = {}
  for _, range in ipairs(ranges) do
    local previous = merged[#merged]
    if previous and range.start_line <= previous.end_line + 1 then
      previous.end_line = math.max(previous.end_line, range.end_line)
    else
      merged[#merged + 1] = { start_line = range.start_line, end_line = range.end_line }
    end
  end
  return merged
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
  return merge_ranges(ranges)
end

local function transform_cursor_lines(transform, selection_shifts)
  multi_cursor.for_each(function(cursor)
    local shift = selection_shifts and selection_shifts[cursor]
    local function transform_line(line)
      return shift and (line + shift) or transform(line)
    end
    cursor.line = transform_line(cursor.line)
    if cursor.anchor then
      cursor.anchor.line = transform_line(cursor.anchor.line)
    end
    if cursor.selection then
      cursor.selection.anchor.line = transform_line(cursor.selection.anchor.line)
      cursor.selection.active.line = transform_line(cursor.selection.active.line)
    end
    for _, selection in ipairs(cursor.selection_stack or {}) do
      selection.anchor.line = transform_line(selection.anchor.line)
      selection.active.line = transform_line(selection.active.line)
    end
    multi_cursor.update_position(cursor, cursor.line, cursor.col)
  end)
end

local function transform_for_move(range, direction)
  local length = range.end_line - range.start_line + 1
  return function(line)
    if direction == 'up' then
      if line >= range.start_line and line <= range.end_line then
        return line - 1
      elseif line == range.start_line - 1 then
        return line + length
      end
    else
      if line >= range.start_line and line <= range.end_line then
        return line + 1
      elseif line == range.end_line + 1 then
        return line - length
      end
    end
    return line
  end
end

local function apply_move_line(range, direction)
  local start_line = range.start_line
  local end_line = range.end_line
  local total_lines = line_count()
  local selection_shifts = {}
  local delta = direction == 'up' and -1 or 1
  multi_cursor.for_each(function(cursor)
    if cursor.selection then
      local start_pos, end_pos = selection_bounds(cursor.selection)
      local selection_end = math.max(start_pos.line, end_pos.line - (end_pos.col == 0 and 1 or 0))
      if start_pos.line >= range.start_line and selection_end <= range.end_line then
        selection_shifts[cursor] = delta
      end
    end
  end)
  if direction == 'up' then
    if start_line == 0 then
      return false
    end
    local chunk = vim.api.nvim_buf_get_lines(buf(), start_line - 1, end_line + 1, false)
    local replacement = {}
    for index = 2, #chunk do
      replacement[#replacement + 1] = chunk[index]
    end
    replacement[#replacement + 1] = chunk[1]
    vim.api.nvim_buf_set_lines(buf(), start_line - 1, end_line + 1, false, replacement)
  else
    if end_line >= total_lines - 1 then
      return false
    end
    local chunk = vim.api.nvim_buf_get_lines(buf(), start_line, end_line + 2, false)
    local replacement = { chunk[#chunk] }
    for index = 1, #chunk - 1 do
      replacement[#replacement + 1] = chunk[index]
    end
    vim.api.nvim_buf_set_lines(buf(), start_line, end_line + 2, false, replacement)
  end
  transform_cursor_lines(transform_for_move(range, direction), selection_shifts)
  return true
end

local function apply_copy_line(range, direction)
  local start_line = range.start_line
  local end_line = range.end_line
  local block = vim.api.nvim_buf_get_lines(buf(), start_line, end_line + 1, false)
  if direction == 'up' then
    vim.api.nvim_buf_set_lines(buf(), start_line, start_line, false, block)
    return start_line, #block
  else
    vim.api.nvim_buf_set_lines(buf(), end_line + 1, end_line + 1, false, block)
    return end_line + 1, #block
  end
end

local function get_cursor_word(cursor)
  local text = get_line(cursor.line)
  local col = util.codepoint_start(text, cursor.col)
  local probe = col
  local char = util.codepoint_at(text, probe)
  if char_kind(char) ~= 'word' and probe > 0 then
    local previous = util.prev_codepoint(text, probe)
    if char_kind(util.codepoint_at(text, previous)) == 'word' then
      probe = previous
    end
  end
  if char_kind(util.codepoint_at(text, probe)) ~= 'word' then
    local pos = { line = cursor.line, col = col }
    return '', pos, pos
  end

  local start_col = probe
  while start_col > 0 do
    local previous = util.prev_codepoint(text, start_col)
    if char_kind(util.codepoint_at(text, previous)) ~= 'word' then
      break
    end
    start_col = previous
  end

  local end_col = probe
  while end_col < #text and char_kind(util.codepoint_at(text, end_col)) == 'word' do
    end_col = util.next_codepoint(text, end_col)
  end
  return text:sub(start_col + 1, end_col),
    { line = cursor.line, col = start_col },
    { line = cursor.line, col = end_col }
end

local function get_selection_string(selection)
  local chunks = get_selection_text(selection)
  return table.concat(chunks, '\n')
end

local function document_index()
  local lines = vim.api.nvim_buf_get_lines(buf(), 0, -1, false)
  local offsets = {}
  local offset = 0
  for index, text in ipairs(lines) do
    offsets[index] = offset
    offset = offset + #text
    if index < #lines then
      offset = offset + 1
    end
  end
  return lines, offsets, table.concat(lines, '\n')
end

local function offset_to_position(lines, offsets, offset)
  local low, high = 1, #offsets
  while low <= high do
    local middle = math.floor((low + high) / 2)
    if offsets[middle] <= offset then
      low = middle + 1
    else
      high = middle - 1
    end
  end
  local index = clamp(high, 1, #lines)
  return { line = index - 1, col = clamp(offset - offsets[index], 0, #lines[index]) }
end

local function find_next_occurrence(needle, start_line, start_col)
  local lines, offsets, document = document_index()
  local line_index = clamp(start_line + 1, 1, #lines)
  local start_offset = offsets[line_index] + clamp(start_col, 0, #lines[line_index])
  local found_start, found_end = document:find(needle, start_offset + 1, true)
  if not found_start then
    return nil
  end
  return offset_to_position(lines, offsets, found_start - 1), offset_to_position(lines, offsets, found_end)
end

local function collect_all_occurrences(needle, limit)
  local lines, offsets, document = document_index()
  local matches = {}
  local search_offset = 1
  while #matches < limit do
    local found_start, found_end = document:find(needle, search_offset, true)
    if not found_start then
      break
    end
    matches[#matches + 1] = {
      anchor = offset_to_position(lines, offsets, found_start - 1),
      active = offset_to_position(lines, offsets, found_end),
    }
    search_offset = found_end + 1
  end
  return matches
end

function M.setup(plugin_state, mc)
  state = plugin_state
  multi_cursor = mc
end

local function save_cursor_state()
  if multi_cursor.save_snapshot then
    multi_cursor.save_snapshot()
  end
end

local function discard_cursor_state()
  if multi_cursor.discard_snapshot then
    multi_cursor.discard_snapshot()
  end
end

function M.undo_cursor_state()
  if not multi_cursor.restore_snapshot or not multi_cursor.restore_snapshot() then
    notify(log_levels.INFO, 'No cursor operation to undo')
    return false
  end
  local has_selection = false
  for _, cursor in ipairs(multi_cursor.iter()) do
    has_selection = has_selection or cursor.selection ~= nil
  end
  if has_selection then
    require('vscode_style').activate_selection_keymaps()
  else
    require('vscode_style').deactivate_selection_keymaps()
  end
  return true
end

local function collapse_selection(cursor, direction)
  if not cursor.selection then
    return nil
  end
  local start_pos, end_pos = selection_bounds(cursor.selection)
  local use_start = direction == 'left' or direction == 'up' or direction == 'home'
  local target = use_start and start_pos or end_pos
  multi_cursor.clear_selection(cursor)
  return target.line, target.col
end

-- Non-modal movement used by aggressive mode. Every logical cursor moves in
-- the same transaction; an existing selection collapses in the arrow's
-- direction, matching desktop-editor behavior.
function M.move_cursor(unit, direction)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = collapse_selection(cursor, direction)
    if new_line == nil then
      if unit == 'character' then
        new_line, new_col = move_char(cursor.line, cursor.col, direction)
      elseif unit == 'line' then
        new_line, new_col = move_line_pos(cursor.line, cursor.col, direction)
      elseif unit == 'word' then
        if direction == 'left' then
          new_line, new_col = move_word_left(cursor)
        else
          new_line, new_col = move_word_right(cursor)
        end
      elseif unit == 'line_boundary' then
        new_line, new_col = move_to_line_boundary(cursor.line, direction)
      elseif unit == 'file_boundary' then
        new_line, new_col = move_to_file_boundary(direction)
      else
        new_line, new_col = cursor.line, cursor.col
      end
    end
    multi_cursor.update_position(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
  require('vscode_style').deactivate_selection_keymaps()
end

function M.select_all()
  multi_cursor.sync_cursors()
  save_cursor_state()
  local last_line, last_col = move_to_file_boundary('end')
  multi_cursor.replace_all_cursors({
    {
      line = last_line,
      col = last_col,
      anchor = { line = 0, col = 0 },
      selection = {
        anchor = { line = 0, col = 0 },
        active = { line = last_line, col = last_col },
      },
      is_primary = true,
    },
  })
  multi_cursor.update_position(multi_cursor.primary(), last_line, last_col)
  multi_cursor.update_highlights()
  require('vscode_style').activate_selection_keymaps()
end

function M.cancel_selection()
  if vim.fn.pumvisible() == 1 then
    feedkeys('<C-e>')
    return true
  end

  if vim.snippet and type(vim.snippet.active) == 'function' and type(vim.snippet.stop) == 'function' then
    local ok, active = pcall(vim.snippet.active)
    if ok and active then
      pcall(vim.snippet.stop)
      return true
    end
  end

  multi_cursor.sync_cursors()
  local cursors = multi_cursor.iter()
  local had_extra_state = #cursors > 1
  local primary = multi_cursor.primary()
  if primary and primary.selection then
    had_extra_state = true
  end
  if had_extra_state and primary then
    local line, col = primary.line, primary.col
    multi_cursor.replace_all_cursors({ { line = line, col = col, is_primary = true } })
    multi_cursor.update_position(multi_cursor.primary(), line, col)
    multi_cursor.update_highlights()
    multi_cursor.clear_snapshot()
    require('vscode_style').deactivate_selection_keymaps()
    return true
  end
  vim.cmd('nohlsearch')
  return false
end

function M.select_character(direction)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_char(cursor.line, cursor.col, direction)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
  require('vscode_style').activate_selection_keymaps()
end

function M.select_line(direction)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_line_pos(cursor.line, cursor.col, direction)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
  require('vscode_style').activate_selection_keymaps()
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
  require('vscode_style').activate_selection_keymaps()
end

function M.select_to_line_boundary(boundary)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_to_line_boundary(cursor.line, boundary)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
  require('vscode_style').activate_selection_keymaps()
end

function M.select_to_file_boundary(boundary)
  multi_cursor.sync_cursors()
  multi_cursor.for_each(function(cursor)
    local new_line, new_col = move_to_file_boundary(boundary)
    apply_selection(cursor, new_line, new_col)
  end)
  multi_cursor.update_highlights()
  require('vscode_style').activate_selection_keymaps()
end

function M.move_line(direction)
  multi_cursor.sync_cursors()
  multi_cursor.clear_snapshot()
  local ranges = normalize_ranges_for_direction(collect_active_ranges(), direction)
  local changed = false
  for _, range in ipairs(ranges) do
    local total = line_count()
    if direction == 'up' and range.start_line == 0 then
      goto continue
    end
    if direction == 'down' and range.end_line >= total - 1 then
      goto continue
    end
    if changed then
      pcall(vim.cmd, 'silent! undojoin')
    end
    changed = apply_move_line(range, direction) or changed
    ::continue::
  end
  multi_cursor.update_highlights()
end

function M.copy_line(direction)
  multi_cursor.sync_cursors()
  multi_cursor.clear_snapshot()
  local ranges = collect_active_ranges()
  table.sort(ranges, function(a, b)
    return a.start_line > b.start_line
  end)
  for index, range in ipairs(ranges) do
    if index > 1 then
      pcall(vim.cmd, 'silent! undojoin')
    end
    local copy_shifts = {}
    multi_cursor.for_each(function(cursor)
      local cursor_start, cursor_end = cursor.line, cursor.line
      if cursor.selection then
        local start_pos, end_pos = selection_bounds(cursor.selection)
        cursor_start = start_pos.line
        cursor_end = math.max(start_pos.line, end_pos.line - (end_pos.col == 0 and 1 or 0))
      end
      if cursor_start >= range.start_line and cursor_end <= range.end_line then
        copy_shifts[cursor] = direction == 'down' and (range.end_line - range.start_line + 1) or 0
      end
    end)
    local insert_at, length = apply_copy_line(range, direction)
    transform_cursor_lines(function(line)
      return line >= insert_at and line + length or line
    end, copy_shifts)
  end
  multi_cursor.update_highlights()
end

function M.delete_line()
  multi_cursor.sync_cursors()
  multi_cursor.clear_snapshot()
  local ranges = collect_active_ranges()
  local cursor_defs = {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    cursor_defs[#cursor_defs + 1] = {
      line = cursor.line,
      col = cursor.col,
      is_primary = cursor.is_primary,
    }
  end
  table.sort(ranges, function(a, b)
    if a.start_line == b.start_line then
      return a.end_line > b.end_line
    end
    return a.start_line > b.start_line
  end)
  for index, range in ipairs(ranges) do
    if index > 1 then
      pcall(vim.cmd, 'silent! undojoin')
    end
    vim.api.nvim_buf_set_lines(buf(), range.start_line, range.end_line + 1, false, {})
  end

  local ascending = vim.deepcopy(ranges)
  table.sort(ascending, function(a, b)
    return a.start_line < b.start_line
  end)
  local max_line = math.max(line_count() - 1, 0)
  for _, def in ipairs(cursor_defs) do
    local removed_before = 0
    local target = def.line
    for _, range in ipairs(ascending) do
      local length = range.end_line - range.start_line + 1
      if def.line > range.end_line then
        removed_before = removed_before + length
      elseif def.line >= range.start_line then
        target = range.start_line
        break
      else
        break
      end
    end
    def.line = clamp(target - removed_before, 0, max_line)
  end
  multi_cursor.replace_all_cursors(cursor_defs)
  multi_cursor.refresh_from_extmarks()
  require('vscode_style').deactivate_selection_keymaps()
end

function M.alt_click_cursor()
  local mouse = util.mouse_position()
  if not mouse or mouse.bufnr ~= buf() then
    return
  end
  local text = get_line(mouse.line)
  local col = util.codepoint_start(text, clamp(mouse.col, 0, #text))
  save_cursor_state()
  local cursor, err = multi_cursor.add_cursor_at(mouse.line, col)
  if err then
    discard_cursor_state()
    notify(log_levels.WARN, err)
  elseif not cursor then
    discard_cursor_state()
  end
end

function M.primary_click()
  local mouse = util.mouse_position()
  if not mouse then
    feedkeys('<LeftMouse>')
    return
  end
  if mouse.bufnr ~= buf() then
    feedkeys('<LeftMouse>')
    return
  end
  if mouse.winid ~= vim.api.nvim_get_current_win() then
    vim.api.nvim_set_current_win(mouse.winid)
  end
  local text = get_line(mouse.line)
  local col = util.codepoint_start(text, clamp(mouse.col, 0, #text))
  multi_cursor.replace_all_cursors({ { line = mouse.line, col = col, is_primary = true } })
  multi_cursor.update_position(multi_cursor.primary(), mouse.line, col)
  multi_cursor.update_highlights()
  multi_cursor.clear_snapshot()
  require('vscode_style').deactivate_selection_keymaps()
end

function M.add_cursor_vertical(direction)
  multi_cursor.sync_cursors()
  save_cursor_state()
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
  if #new_cursors == 0 then
    discard_cursor_state()
  end
end

function M.add_selection_to_next_match()
  multi_cursor.sync_cursors()
  local primary = multi_cursor.primary()
  if not primary then
    notify(log_levels.WARN, 'No active cursor available for multi-selection')
    return
  end
  save_cursor_state()
  local needle
  local selected_primary = false
  if primary.selection then
    needle = get_selection_string(primary.selection)
  else
    local word, word_start, word_end = get_cursor_word(primary)
    needle = word
    if needle and needle ~= '' then
      primary.anchor = copy_pos(word_start)
      primary.selection = { anchor = copy_pos(word_start), active = copy_pos(word_end) }
      multi_cursor.update_position(primary, word_end.line, word_end.col)
      multi_cursor.set_selection(primary, word_start, word_end)
      selected_primary = true
    end
  end
  if not needle or needle == '' then
    discard_cursor_state()
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
  local existing = {}
  for _, item in ipairs(cursors) do
    if item.cursor.selection then
      local selection_start, selection_end = selection_bounds(item.cursor.selection)
      existing[string.format(
        '%d:%d-%d:%d',
        selection_start.line,
        selection_start.col,
        selection_end.line,
        selection_end.col
      )] = true
    end
  end

  local next_start, next_end
  local wrapped = false
  for _ = 0, #cursors do
    next_start, next_end = find_next_occurrence(needle, start_line, start_col)
    if not next_start and not wrapped then
      wrapped = true
      start_line, start_col = 0, 0
      next_start, next_end = find_next_occurrence(needle, start_line, start_col)
    end
    if not next_start then
      break
    end
    local key = string.format('%d:%d-%d:%d', next_start.line, next_start.col, next_end.line, next_end.col)
    if not existing[key] then
      break
    end
    start_line, start_col = next_end.line, next_end.col
    next_start, next_end = nil, nil
  end
  if not next_start then
    if not selected_primary then
      discard_cursor_state()
    end
    notify(log_levels.INFO, 'All matches are already selected for "' .. needle .. '"')
    return
  end
  local cursor, err = multi_cursor.add_cursor_at(next_start.line, next_end.col)
  if not cursor then
    if not selected_primary then
      discard_cursor_state()
    end
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
  require('vscode_style').activate_selection_keymaps()
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
  local matches = collect_all_occurrences(needle, (state.config.max_cursors or 32) + 1)
  if #matches == 0 then
    return
  end
  save_cursor_state()
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
  require('vscode_style').activate_selection_keymaps()
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
    local target_indent = vim.fn.indent(start_pos.line + 1)
    local top = start_pos.line
    while top > 0 and vim.fn.indent(top) >= target_indent do
      top = top - 1
    end
    local bottom = end_pos.line
    local total = line_count()
    while bottom < total - 1 and vim.fn.indent(bottom + 2) >= target_indent do
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
  require('vscode_style').activate_selection_keymaps()
end

function M.shrink_selection()
  multi_cursor.sync_cursors()
  local has_selection = false
  multi_cursor.for_each(function(cursor)
    if cursor.selection then
      multi_cursor.pop_selection(cursor)
      if cursor.selection then
        has_selection = true
        local _, end_pos = selection_bounds(cursor.selection)
        multi_cursor.update_position(cursor, end_pos.line, end_pos.col)
      end
    end
  end)
  multi_cursor.update_highlights()
  if has_selection then
    require('vscode_style').activate_selection_keymaps()
  else
    require('vscode_style').deactivate_selection_keymaps()
  end
end

M.selection_bounds = selection_bounds

local function delete_selections(selections)
  multi_cursor.clear_snapshot()
  local function position_before_or_equal(a, b)
    return a.line < b.line or (a.line == b.line and a.col <= b.col)
  end
  local function later_position(a, b)
    if position_before_or_equal(a, b) then
      return b
    end
    return a
  end

  for _, sel in ipairs(selections) do
    sel.collapse_mark = vim.api.nvim_buf_set_extmark(buf(), state.ns, sel.start.line, sel.start.col, {
      right_gravity = false,
    })
  end

  local ascending = vim.deepcopy(selections)
  table.sort(ascending, function(a, b)
    if a.start.line == b.start.line then
      return a.start.col < b.start.col
    end
    return a.start.line < b.start.line
  end)
  local edits = {}
  for _, sel in ipairs(ascending) do
    local previous = edits[#edits]
    if previous and position_before_or_equal(sel.start, previous.finish) then
      previous.finish = copy_pos(later_position(previous.finish, sel.finish))
    else
      edits[#edits + 1] = { start = copy_pos(sel.start), finish = copy_pos(sel.finish) }
    end
  end
  table.sort(edits, function(a, b)
    if a.start.line == b.start.line then
      return a.start.col > b.start.col
    end
    return a.start.line > b.start.line
  end)
  for index, edit in ipairs(edits) do
    if index > 1 then
      pcall(vim.cmd, 'silent! undojoin')
    end
    vim.api.nvim_buf_set_text(buf(), edit.start.line, edit.start.col, edit.finish.line, edit.finish.col, {})
  end

  for _, sel in ipairs(selections) do
    local position = vim.api.nvim_buf_get_extmark_by_id(buf(), state.ns, sel.collapse_mark, {})
    if position and position[1] then
      sel.collapse = { line = position[1], col = position[2] }
    else
      sel.collapse = copy_pos(sel.start)
    end
    pcall(vim.api.nvim_buf_del_extmark, buf(), state.ns, sel.collapse_mark)
    sel.collapse_mark = nil
  end
end

local function collapse_deleted_selections(selections)
  for _, sel in ipairs(selections) do
    multi_cursor.clear_selection(sel.cursor)
    local position = sel.collapse or sel.start
    multi_cursor.update_position(sel.cursor, position.line, position.col)
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

local function text_to_lines(text)
  text = tostring(text or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
  return vim.split(text, '\n', { plain = true })
end

local function insert_text_at_points(target_buf, points, text_lines)
  if not points or #points == 0 then
    return
  end
  multi_cursor.clear_snapshot()
  sort_points_desc(points)
  for index, point in ipairs(points) do
    if index > 1 then
      pcall(vim.cmd, 'silent! undojoin')
    end
    vim.api.nvim_buf_set_text(
      target_buf,
      point.line,
      point.col,
      point.line,
      point.col,
      point.text_lines or text_lines
    )
  end
  if multi_cursor.refresh_from_extmarks then
    multi_cursor.refresh_from_extmarks()
  else
    multi_cursor.sync_cursors()
  end
  multi_cursor.update_highlights()
end

function M.insert_text_at_cursors(text)
  multi_cursor.sync_cursors()
  local points = {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    points[#points + 1] = { cursor = cursor, line = cursor.line, col = cursor.col }
  end
  insert_text_at_points(buf(), points, text_to_lines(text))
end

local function clipboard_register()
  local aggressive = state and state.config and state.config.aggressive
  return (aggressive and aggressive.clipboard_register) or '+'
end

local function set_clipboard(text, regtype)
  local register = clipboard_register()
  local ok = pcall(vim.fn.setreg, register, text, regtype)
  if not ok and register ~= '"' then
    ok = pcall(vim.fn.setreg, '"', text, regtype)
  end
  if not ok then
    notify(log_levels.WARN, 'vscode_style: clipboard provider is unavailable')
  end
  return ok
end

local function selected_text(selections)
  table.sort(selections, function(a, b)
    if a.start.line == b.start.line then
      return a.start.col < b.start.col
    end
    return a.start.line < b.start.line
  end)
  local chunks = {}
  for _, selection in ipairs(selections) do
    chunks[#chunks + 1] = table.concat(
      vim.api.nvim_buf_get_text(
        buf(),
        selection.start.line,
        selection.start.col,
        selection.finish.line,
        selection.finish.col,
        {}
      ),
      '\n'
    )
  end
  return table.concat(chunks, '\n'), chunks
end

function M.copy(cut)
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections > 0 then
    local text, chunks = selected_text(selections)
    if not set_clipboard(text, 'v') then
      return
    end
    state.clipboard_payload = { text = text, chunks = chunks }
    if cut then
      delete_selections(selections)
      collapse_deleted_selections(selections)
      multi_cursor.update_highlights()
      require('vscode_style').deactivate_selection_keymaps()
    end
    return
  end

  local seen, selected_lines = {}, {}
  state.clipboard_payload = nil
  for _, cursor in ipairs(multi_cursor.iter()) do
    if not seen[cursor.line] then
      seen[cursor.line] = true
      selected_lines[#selected_lines + 1] = cursor.line
    end
  end
  table.sort(selected_lines)
  local chunks = {}
  for _, line in ipairs(selected_lines) do
    chunks[#chunks + 1] = get_line(line)
  end
  if not set_clipboard(table.concat(chunks, '\n') .. '\n', 'V') then
    return
  end
  if cut then
    M.delete_line()
  end
end

local function paste_lines_at_cursors(lines)
  multi_cursor.clear_snapshot()
  local target_lines, seen = {}, {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    if not seen[cursor.line] then
      seen[cursor.line] = true
      target_lines[#target_lines + 1] = cursor.line
    end
  end
  table.sort(target_lines, function(a, b) return a > b end)
  for index, line in ipairs(target_lines) do
    if index > 1 then
      pcall(vim.cmd, 'silent! undojoin')
    end
    vim.api.nvim_buf_set_lines(buf(), line, line, false, lines)
  end
  multi_cursor.refresh_from_extmarks()
  multi_cursor.update_highlights()
end

function M.paste()
  local register = clipboard_register()
  local ok, value = pcall(vim.fn.getreg, register, 1, true)
  if not ok then
    register = '"'
    ok, value = pcall(vim.fn.getreg, '"', 1, true)
  end
  if not ok then
    notify(log_levels.WARN, 'vscode_style: clipboard provider is unavailable')
    return
  end
  local type_ok, regtype = pcall(vim.fn.getregtype, register)
  regtype = type_ok and regtype or 'v'
  local text = type(value) == 'table' and table.concat(value, '\n') or tostring(value or '')
  if text == '' then
    return
  end

  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 and regtype:sub(1, 1) == 'V' and type(value) == 'table' then
    paste_lines_at_cursors(value)
    return
  end
  if #selections > 0 then
    delete_selections(selections)
    collapse_deleted_selections(selections)
    require('vscode_style').deactivate_selection_keymaps()
    pcall(vim.cmd, 'silent! undojoin')
  end
  local payload = state.clipboard_payload
  local cursors = multi_cursor.iter()
  if payload and payload.text == text and #payload.chunks == #cursors and #cursors > 1 then
    local points = {}
    for index, cursor in ipairs(cursors) do
      points[#points + 1] = {
        cursor = cursor,
        line = cursor.line,
        col = cursor.col,
        text_lines = text_to_lines(payload.chunks[index]),
      }
    end
    insert_text_at_points(buf(), points, { '' })
    return
  end
  M.insert_text_at_cursors(text)
end

local surround_pairs = {
  ["'"] = "'",
  ['"'] = '"',
  ['('] = ')',
  ['['] = ']',
  ['{'] = '}',
  ['<'] = '>',
}

local function surround_pair_for(char)
  if not (state and state.config and state.config.feature_flags) then
    return surround_pairs[char]
  end
  if state.config.feature_flags.surround == false then
    return nil
  end
  return surround_pairs[char]
end

local function apply_surround_to_selections(open_char, close_char, selections)
  if not selections or #selections == 0 then
    return {}
  end
  multi_cursor.clear_snapshot()
  local entries, seen = {}, {}
  for _, sel in ipairs(selections) do
    local start_line, start_col = sanitize_point(sel.start)
    local finish_line, finish_col = sanitize_point(sel.finish)
    if finish_line < start_line or (finish_line == start_line and finish_col < start_col) then
      start_line, finish_line = finish_line, start_line
      start_col, finish_col = finish_col, start_col
    end
    local key = string.format('%d:%d-%d:%d', start_line, start_col, finish_line, finish_col)
    local existing = seen[key]
    if existing then
      existing.cursors[#existing.cursors + 1] = sel.cursor
    else
      local text = vim.api.nvim_buf_get_text(buf(), start_line, start_col, finish_line, finish_col, {})
      if #text == 0 then
        text = { '' }
      end
      text[1] = open_char .. (text[1] or '')
      text[#text] = (text[#text] or '') .. close_char
      local entry = {
        selection = {
          start = { line = start_line, col = start_col },
          finish = { line = finish_line, col = finish_col },
        },
        cursors = { sel.cursor },
        text = text,
      }
      seen[key] = entry
      entries[#entries + 1] = entry
    end
  end
  if #entries == 0 then
    return {}
  end
  table.sort(entries, function(a, b)
    local sa, sb = a.selection.start, b.selection.start
    if sa.line == sb.line then
      return sa.col > sb.col
    end
    return sa.line > sb.line
  end)
  for index, entry in ipairs(entries) do
    if index > 1 then
      pcall(vim.cmd, 'silent! undojoin')
    end
    local sel = entry.selection
    vim.api.nvim_buf_set_text(buf(), sel.start.line, sel.start.col, sel.finish.line, sel.finish.col, entry.text)
    local target_line = sel.start.line + (#entry.text - 1)
    local target_col = #entry.text == 1 and (sel.start.col + #entry.text[1]) or #entry.text[#entry.text]
    entry.target_mark = vim.api.nvim_buf_set_extmark(buf(), state.ns, target_line, target_col, {
      right_gravity = true,
    })
  end
  multi_cursor.sync_cursors()
  local handled = {}
  for _, entry in ipairs(entries) do
    local target = vim.api.nvim_buf_get_extmark_by_id(buf(), state.ns, entry.target_mark, {})
    local new_line = target[1] or entry.selection.start.line
    local new_col = target[2] or entry.selection.start.col
    pcall(vim.api.nvim_buf_del_extmark, buf(), state.ns, entry.target_mark)
    for _, cursor in ipairs(entry.cursors) do
      handled[cursor] = true
      multi_cursor.clear_selection(cursor)
      multi_cursor.update_position(cursor, new_line, new_col)
    end
  end
  multi_cursor.update_highlights()
  return handled
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

local function delete_at_cursors(direction)
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 then
    local cursors = multi_cursor.iter()
    if #cursors <= 1 then
      return false
    end
    for _, cursor in ipairs(cursors) do
      local start_line, start_col = cursor.line, cursor.col
      local finish_line, finish_col = cursor.line, cursor.col
      if direction == 'left' then
        start_line, start_col = move_char(cursor.line, cursor.col, 'left')
      else
        finish_line, finish_col = move_char(cursor.line, cursor.col, 'right')
      end
      if start_line ~= finish_line or start_col ~= finish_col then
        selections[#selections + 1] = {
          cursor = cursor,
          start = { line = start_line, col = start_col },
          finish = { line = finish_line, col = finish_col },
        }
      end
    end
  end
  if #selections == 0 then
    return false
  end
  delete_selections(selections)
  collapse_deleted_selections(selections)
  multi_cursor.update_highlights()
  return true
end

function M.handle_backspace()
  if not delete_at_cursors('left') then
    feedkeys('<BS>')
  end
end

function M.handle_delete()
  if not delete_at_cursors('right') then
    feedkeys('<Del>')
  end
end

function M.delete_word(direction)
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 then
    for _, cursor in ipairs(multi_cursor.iter()) do
      local start_line, start_col = cursor.line, cursor.col
      local finish_line, finish_col = cursor.line, cursor.col
      if direction == 'left' then
        start_line, start_col = move_word_left_position(cursor.line, cursor.col)
      else
        finish_line, finish_col = move_word_right_position(cursor.line, cursor.col)
      end
      if start_line ~= finish_line or start_col ~= finish_col then
        selections[#selections + 1] = {
          cursor = cursor,
          start = { line = start_line, col = start_col },
          finish = { line = finish_line, col = finish_col },
        }
      end
    end
  end
  if #selections == 0 then
    return
  end
  delete_selections(selections)
  collapse_deleted_selections(selections)
  multi_cursor.update_highlights()
  require('vscode_style').deactivate_selection_keymaps()
end

function M.undo()
  feedkeys('<C-o>u')
end

function M.redo()
  feedkeys('<C-o><C-r>')
end

function M.start_search()
  feedkeys('<C-o>/')
end

function M.handle_enter()
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 and #multi_cursor.iter() <= 1 then
    feedkeys('<CR>')
    return
  end
  if #selections > 0 then
    delete_selections(selections)
    collapse_deleted_selections(selections)
    require('vscode_style').deactivate_selection_keymaps()
    pcall(vim.cmd, 'silent! undojoin')
  end
  local points = {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    local indent = get_line(cursor.line):match('^[ \t]*') or ''
    points[#points + 1] = {
      cursor = cursor,
      line = cursor.line,
      col = cursor.col,
      text_lines = { '', indent },
    }
  end
  insert_text_at_points(buf(), points, { '', '' })
end

function M.handle_tab()
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 then
    if #multi_cursor.iter() > 1 then
      M.insert_text_at_cursors(indent_string())
      return
    end
    feedkeys('<Tab>')
    return
  end
  local lines = collect_selection_lines(selections)
  if #lines == 0 then
    return
  end
  local indent = indent_string()
  local indent_len = #indent
  if indent_len == 0 then
    return
  end
  local bufnr = buf()
  local deltas = {}
  multi_cursor.clear_snapshot()
  for index, line in ipairs(lines) do
    if index > 1 then
      pcall(vim.cmd, 'silent! undojoin')
    end
    local text = get_line(line)
    vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { indent .. text })
    deltas[line] = (deltas[line] or 0) + indent_len
  end
  adjust_cursor_columns(deltas)
end

function M.handle_shift_tab()
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  local lines
  if #selections == 0 and #multi_cursor.iter() > 1 then
    local seen = {}
    lines = {}
    for _, cursor in ipairs(multi_cursor.iter()) do
      if not seen[cursor.line] then
        seen[cursor.line] = true
        lines[#lines + 1] = cursor.line
      end
    end
    table.sort(lines)
  elseif #selections == 0 then
    feedkeys('<S-Tab>')
    return
  else
    lines = collect_selection_lines(selections)
  end
  if #lines == 0 then
    return
  end
  local indent = indent_string()
  local bufnr = buf()
  local deltas = {}
  local changed = false
  local edit_index = 0
  for _, line in ipairs(lines) do
    local text = get_line(line)
    local updated, removed = remove_indent_prefix(text, indent)
    if removed > 0 then
      edit_index = edit_index + 1
      if edit_index == 1 then
        multi_cursor.clear_snapshot()
      end
      if edit_index > 1 then
        pcall(vim.cmd, 'silent! undojoin')
      end
      vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { updated })
      deltas[line] = (deltas[line] or 0) - removed
      changed = true
    end
  end
  if not changed then
    return
  end
  adjust_cursor_columns(deltas)
end

local function insert_at_live_cursors(target_buf, text, skip)
  local points = {}
  for _, cursor in ipairs(multi_cursor.iter()) do
    if not skip or not skip[cursor] then
      points[#points + 1] = { cursor = cursor, line = cursor.line, col = cursor.col }
    end
  end
  insert_text_at_points(target_buf, points, text_to_lines(text))
end

local function flush_pending_insert(target_buf, pending)
  if not vim.api.nvim_buf_is_valid(target_buf) then
    return
  end
  if not state.pending_inserts or state.pending_inserts[target_buf] ~= pending then
    return
  end
  state.pending_inserts[target_buf] = nil
  vim.api.nvim_buf_call(target_buf, function()
    local ok, err = pcall(function()
      if pending.primary then
        multi_cursor.ensure_primary_cursor_at(pending.primary.line, pending.primary.col)
      end
      multi_cursor.refresh_from_extmarks()
      local selections = pending.selections or gather_selections()
      local first = table.remove(pending.chars, 1)
      if not first then
        return
      end

      if #selections > 0 then
        require('vscode_style').deactivate_selection_keymaps(target_buf)
        local close = surround_pair_for(first)
        if close then
          local handled = apply_surround_to_selections(first, close, selections)
          insert_at_live_cursors(target_buf, first, handled)
        else
          delete_selections(selections)
          collapse_deleted_selections(selections)
          pcall(vim.cmd, 'silent! undojoin')
          insert_at_live_cursors(target_buf, first)
        end
      else
        insert_at_live_cursors(target_buf, first)
      end

      if #pending.chars > 0 then
        insert_at_live_cursors(target_buf, table.concat(pending.chars))
      end
    end)
    if not ok then
      notify(log_levels.ERROR, 'vscode_style insert failed: ' .. tostring(err))
    end
  end)
end

local function queue_insert(char)
  local target_buf = buf()
  state.pending_inserts = state.pending_inserts or {}
  local pending = state.pending_inserts[target_buf]
  if pending then
    pending.chars[#pending.chars + 1] = char
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  pending = {
    chars = { char },
    primary = { line = cursor[1] - 1, col = cursor[2] },
    selections = gather_selections(),
  }
  state.pending_inserts[target_buf] = pending
  vim.schedule(function()
    flush_pending_insert(target_buf, pending)
  end)
end

function M.on_insert_pre()
  local char = vim.v.char
  local key = vim.v.key
  if key == 'Tab' or key == 'S-Tab' or not char or char == '' then
    return
  end
  if not multi_cursor.requires_insert_handling() then
    return
  end
  vim.v.char = ''
  queue_insert(char)
end

function M.column_selection_drag_start()
  local mouse = util.mouse_position()
  if not mouse or mouse.bufnr ~= buf() then
    return
  end
  if not state.column_selecting then
    save_cursor_state()
    state.column_selecting = true
    state.column_anchor = {
      line = mouse.line,
      vcol = mouse.vcol,
      winid = mouse.winid,
      bufnr = mouse.bufnr,
    }
  end

  local anchor = state.column_anchor
  if not anchor or anchor.bufnr ~= mouse.bufnr then
    return
  end
  local start_line = math.min(anchor.line, mouse.line)
  local end_line = math.max(anchor.line, mouse.line)
  local cursor_defs = {}
  for line = start_line, end_line do
    local text = get_line(line)
    local anchor_col = util.virtual_to_byte_col(anchor.winid, line, anchor.vcol, text)
    local active_col = util.virtual_to_byte_col(mouse.winid, line, mouse.vcol, text)
    cursor_defs[#cursor_defs + 1] = {
      line = line,
      col = active_col,
      anchor = { line = line, col = anchor_col },
      selection = {
        anchor = { line = line, col = anchor_col },
        active = { line = line, col = active_col },
      },
      is_primary = line == start_line,
    }
  end
  multi_cursor.replace_all_cursors(cursor_defs)
  multi_cursor.update_highlights()
end

function M.column_selection_drag_end()
  if not state.column_selecting then
    return
  end
  M.column_selection_drag_start()
  state.column_selecting = false
  state.column_anchor = nil
end

function M.delete_selection_and_cleanup(direction)
  multi_cursor.sync_cursors()
  local selections = gather_selections()
  if #selections == 0 then
    -- This should not happen if keymaps are managed correctly, but as a fallback:
    require('vscode_style').deactivate_selection_keymaps()
    local fallback = direction == 'right' and '<Del>' or '<BS>'
    local keys = vim.api.nvim_replace_termcodes(fallback, true, false, true)
    vim.api.nvim_feedkeys(keys, 'n', false)
    return
  end

  local ok, err = pcall(function()
    delete_selections(selections)
    multi_cursor.sync_cursors()
    collapse_deleted_selections(selections)
    multi_cursor.update_highlights()
  end)

  if not ok then
    notify(log_levels.ERROR, 'vscode_style delete_selection failed: ' .. err)
  end

  -- Crucially, clean up the keymaps *after* the deletion
  require('vscode_style').deactivate_selection_keymaps()
end

function M.on_cursor_moved_i()
  local primary = multi_cursor.peek_primary()
  if not (primary and primary.selection) then
    return
  end
  local start_pos, end_pos = M.selection_bounds(primary.selection)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1] - 1
  local cursor_col = cursor_pos[2]

  if
    cursor_line < start_pos.line
    or cursor_line > end_pos.line
    or (cursor_line == start_pos.line and cursor_col < start_pos.col)
    or (cursor_line == end_pos.line and cursor_col > end_pos.col)
  then
    multi_cursor.clear_all_selections()
    multi_cursor.update_highlights()
    require('vscode_style').deactivate_selection_keymaps()
  end
end

return M
