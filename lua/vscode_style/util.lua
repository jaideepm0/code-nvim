local M = {}

function M.clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

-- Neovim buffer and extmark columns are byte offsets. Keep every position on a
-- UTF-8 codepoint boundary without depending on version-specific string APIs.
local function is_continuation(byte)
  return byte ~= nil and byte >= 0x80 and byte <= 0xBF
end

function M.codepoint_start(text, col)
  col = M.clamp(math.floor(tonumber(col) or 0), 0, #text)
  while col > 0 and col < #text and is_continuation(text:byte(col + 1)) do
    col = col - 1
  end
  return col
end

function M.prev_codepoint(text, col)
  col = M.codepoint_start(text, col)
  if col == 0 then
    return 0
  end
  col = col - 1
  while col > 0 and is_continuation(text:byte(col + 1)) do
    col = col - 1
  end
  return col
end

function M.next_codepoint(text, col)
  col = M.codepoint_start(text, col)
  if col >= #text then
    return #text
  end
  col = col + 1
  while col < #text and is_continuation(text:byte(col + 1)) do
    col = col + 1
  end
  return col
end

function M.codepoint_at(text, col)
  col = M.codepoint_start(text, col)
  if col >= #text then
    return '', col
  end
  local finish = M.next_codepoint(text, col)
  return text:sub(col + 1, finish), finish
end

function M.mouse_position()
  local ok, mouse = pcall(vim.fn.getmousepos)
  if not ok or type(mouse) ~= 'table' then
    return nil
  end
  local line = tonumber(mouse.line) or 0
  local column = tonumber(mouse.column) or 0
  local winid = tonumber(mouse.winid) or 0
  if line <= 0 or column <= 0 or winid <= 0 or not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  return {
    winid = winid,
    bufnr = vim.api.nvim_win_get_buf(winid),
    line = line - 1,
    -- getmousepos().column is a 1-based byte column and may be one byte past EOL.
    col = column - 1,
    -- v:mouse_col is a 1-based virtual text column, unlike the byte column above.
    vcol = math.max(1, tonumber(vim.v.mouse_col) or column),
  }
end

function M.virtual_to_byte_col(winid, line, vcol, text)
  text = text or ''
  if vim.fn.exists('*virtcol2col') == 1 then
    local ok, col = pcall(vim.fn.virtcol2col, winid, line + 1, math.max(1, vcol))
    if ok and type(col) == 'number' and col > 0 then
      return M.codepoint_start(text, M.clamp(col - 1, 0, #text))
    end
  end
  -- Older Neovim fallback: this is exact for ordinary text and still produces
  -- a safe codepoint boundary for tabs and wide characters.
  return M.codepoint_start(text, M.clamp(vcol - 1, 0, #text))
end

return M
