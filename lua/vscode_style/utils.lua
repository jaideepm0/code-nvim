-- Shared utility functions for vscode_style plugin
local M = {}

--- Get the current buffer handle
---@return number Buffer handle
function M.buf()
  return vim.api.nvim_get_current_buf()
end

--- Clamp a value between min and max
---@param value number Value to clamp
---@param min_val number Minimum value
---@param max_val number Maximum value
---@return number Clamped value
function M.clamp(value, min_val, max_val)
  if value < min_val then
    return min_val
  end
  if value > max_val then
    return max_val
  end
  return value
end

--- Safe buffer operation with error handling
---@param fn function Function to execute
---@param error_msg string Error message prefix
---@return boolean success, any result_or_error
function M.safe_buf_op(fn, error_msg)
  local ok, result = pcall(fn)
  if not ok then
    local msg = string.format('%s: %s', error_msg or 'Buffer operation failed', tostring(result))
    vim.notify(msg, vim.log.levels.ERROR)
    return false, result
  end
  return true, result
end

--- Check if a keymap exists
---@param lhs string Left-hand side of mapping
---@param mode string Mode ('i', 'n', etc.)
---@return boolean
function M.keymap_exists(lhs, mode)
  return vim.fn.maparg(lhs, mode) ~= ''
end

--- Deep merge two tables
---@param base table Base table
---@param override table Override table
---@return table Merged table
function M.deep_merge(base, override)
  local result = vim.deepcopy(base)
  for key, value in pairs(override) do
    if type(value) == 'table' and type(result[key]) == 'table' then
      result[key] = M.deep_merge(result[key], value)
    else
      result[key] = value
    end
  end
  return result
end

--- Check if buffer should be excluded based on filetype
---@param exclude_filetypes table List of filetypes to exclude
---@param include_filetypes table List of filetypes to include (empty = all)
---@return boolean Should exclude
function M.should_exclude_buffer(exclude_filetypes, include_filetypes)
  local ft = vim.bo.filetype
  local bt = vim.bo.buftype
  
  -- Exclude special buffer types
  if bt ~= '' and bt ~= 'acwrite' then
    return true
  end
  
  -- Check include list (if specified, only these are allowed)
  if include_filetypes and #include_filetypes > 0 then
    for _, included_ft in ipairs(include_filetypes) do
      if ft == included_ft then
        return false
      end
    end
    return true
  end
  
  -- Check exclude list
  if exclude_filetypes then
    for _, excluded_ft in ipairs(exclude_filetypes) do
      if ft == excluded_ft then
        return true
      end
    end
  end
  
  return false
end

--- Validate configuration options
---@param config table Configuration to validate
---@return boolean valid, string|nil error_message
function M.validate_config(config)
  if config.max_cursors and (type(config.max_cursors) ~= 'number' or config.max_cursors < 1) then
    return false, 'max_cursors must be a positive number'
  end
  
  if config.selection_hl and type(config.selection_hl) ~= 'string' then
    return false, 'selection_hl must be a string'
  end
  
  if config.enabled ~= nil and type(config.enabled) ~= 'boolean' then
    return false, 'enabled must be a boolean'
  end
  
  if config.features and type(config.features) ~= 'table' then
    return false, 'features must be a table'
  end
  
  if config.keymaps and type(config.keymaps) ~= 'table' then
    return false, 'keymaps must be a table'
  end
  
  return true, nil
end

--- Execute callback safely
---@param callback function|nil Callback function
---@param ... any Arguments to pass to callback
---@return boolean success
function M.safe_callback(callback, ...)
  if not callback or type(callback) ~= 'function' then
    return false
  end
  
  local ok, err = pcall(callback, ...)
  if not ok then
    vim.notify(
      string.format('Callback error: %s', tostring(err)),
      vim.log.levels.WARN
    )
    return false
  end
  
  return true
end

--- Get line count for current buffer
---@return number
function M.line_count()
  return vim.api.nvim_buf_line_count(M.buf())
end

--- Get line text safely
---@param line number Line number (0-indexed)
---@return string Line text or empty string
function M.get_line(line)
  if line < 0 then
    return ''
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, M.buf(), line, line + 1, true)
  if not ok or not lines or #lines == 0 then
    return ''
  end
  return lines[1] or ''
end

--- Sanitize position to be within buffer bounds
---@param pos table|nil Position {line, col}
---@return number line, number col
function M.sanitize_position(pos)
  local total = M.line_count()
  if total == 0 then
    return 0, 0
  end
  
  local line = M.clamp((pos and pos.line) or 0, 0, total - 1)
  local text = M.get_line(line)
  local col = M.clamp((pos and pos.col) or 0, 0, #text)
  
  return line, col
end

--- Create a copy of a position
---@param pos table Position {line, col}
---@return table Copied position
function M.copy_pos(pos)
  return { line = pos.line, col = pos.col }
end

--- Check if plugin is enabled for current buffer
---@param config table Plugin configuration
---@return boolean
function M.is_enabled_for_buffer(config)
  if not config.enabled then
    return false
  end
  
  if config.buffer_local then
    -- Check buffer-local variable
    local buf_enabled = vim.b.vscode_style_enabled
    if buf_enabled ~= nil then
      return buf_enabled
    end
  end
  
  return not M.should_exclude_buffer(config.exclude_filetypes, config.include_filetypes)
end

return M
