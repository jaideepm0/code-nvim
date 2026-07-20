local M = {}

function M.to_set(values)
  local result = {}
  for _, value in ipairs(values or {}) do
    result[value] = true
  end
  return result
end

function M.window_is_floating(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end
  local ok, win_config = pcall(vim.api.nvim_win_get_config, winid)
  return ok and win_config.relative and win_config.relative ~= ''
end

function M.window_for_buffer(bufnr)
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current) == bufnr then
    return current
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
  return 0
end

function M.evaluate(policy, bufnr, winid, context)
  policy = policy or {}
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end

  local eligible = vim.bo[bufnr].modifiable and not vim.bo[bufnr].readonly
  local excluded_buftypes = policy.excluded_buftypes or M.to_set(policy.exclude_buftypes)
  local excluded_filetypes = policy.excluded_filetypes or M.to_set(policy.exclude_filetypes)
  if excluded_buftypes[vim.bo[bufnr].buftype] or excluded_filetypes[vim.bo[bufnr].filetype] then
    eligible = false
  end
  if not policy.allow_floating and M.window_is_floating(winid) then
    eligible = false
  end

  if type(policy.should_handle) == 'function' then
    local ok, decision = pcall(policy.should_handle, bufnr, winid, context)
    if not ok then
      return false, decision
    end
    if decision ~= nil then
      eligible = not not decision
    end
  end
  return eligible
end

return M
