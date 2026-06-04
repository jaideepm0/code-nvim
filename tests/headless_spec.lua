local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local tests = {}

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function fail(message)
  error(message, 2)
end

local function inspect(value)
  return vim.inspect(value)
end

local function assert_eq(actual, expected, context)
  if not vim.deep_equal(actual, expected) then
    fail((context or 'values differ') .. '\nexpected: ' .. inspect(expected) .. '\nactual:   ' .. inspect(actual))
  end
end

local function assert_true(value, context)
  if not value then
    fail(context or 'expected truthy value')
  end
end

local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function get_buf_map(bufnr, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'i')) do
    if map.lhs == lhs then
      return map
    end
  end
  return nil
end

local function cleanup_buf_maps(bufnr, lhses)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  for _, lhs in ipairs(lhses) do
    pcall(vim.keymap.del, 'i', lhs, { buffer = bufnr })
  end
end

local function fresh_plugin()
  for _, name in ipairs({
    'vscode_style',
    'vscode_style.actions',
    'vscode_style.config',
    'vscode_style.multi_cursor',
  }) do
    package.loaded[name] = nil
  end
  local plugin = require('vscode_style')
  return plugin, require('vscode_style.actions'), require('vscode_style.multi_cursor')
end

local function setup_buffer(text, opts)
  opts = opts or {}
  local plugin, actions, multi_cursor = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, text)
  vim.api.nvim_win_set_cursor(0, opts.cursor or { 1, 0 })
  plugin.setup(vim.tbl_extend('force', {
    mapping_strategy = 'skip',
    notify = false,
    max_cursors = 64,
  }, opts.config or {}))
  return {
    bufnr = bufnr,
    plugin = plugin,
    actions = actions,
    multi_cursor = multi_cursor,
  }
end

local function selected_cursor(start_line, start_col, end_line, end_col, is_primary)
  return {
    line = end_line,
    col = end_col,
    anchor = { line = start_line, col = start_col },
    selection = {
      anchor = { line = start_line, col = start_col },
      active = { line = end_line, col = end_col },
    },
    is_primary = is_primary ~= false,
  }
end

local function cursor_positions(multi_cursor)
  local positions = {}
  for _, cursor in ipairs(multi_cursor.get_positions()) do
    positions[#positions + 1] = { line = cursor.line, col = cursor.col }
  end
  return positions
end

test('Ctrl+Shift+L treats punctuation selections literally instead of as escaped Lua patterns', function()
  local env = setup_buffer({
    'foo.bar fooXbar foo.bar',
    'a[b] aXb a[b]',
    '(weird)+? (weird)+?',
  }, { cursor = { 1, 7 } })

  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 7, true),
  })
  env.actions.select_all_occurrences()

  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 7 },
    { line = 0, col = 23 },
  }, 'dot-containing literal should select only exact foo.bar matches')
end)

test('Ctrl+D can add the next selected punctuation match without inventing backslashes', function()
  local env = setup_buffer({
    'a[b] -- a[b] -- a-b',
  }, { cursor = { 1, 4 } })

  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 4, true),
  })
  env.actions.add_selection_to_next_match()

  local cursors = env.multi_cursor.get_positions()
  assert_eq(#cursors, 2, 'Ctrl+D should add one cursor for the next a[b] match')
  local second = cursors[2].cursor.selection
  assert_eq({ second.anchor.line, second.anchor.col, second.active.line, second.active.col }, {
    0,
    8,
    0,
    12,
  }, 'second selected range should be the next exact a[b]')
end)

test('typing with same-line multi-cursors leaves every cursor after its own inserted text', function()
  local env = setup_buffer({ 'abcdefghi' }, { cursor = { 1, 3 } })
  env.multi_cursor.add_cursor_at(0, 6)

  assert_true(type(env.actions.insert_text_at_cursors) == 'function', 'actions should expose the cursor insertion primitive')
  env.actions.insert_text_at_cursors('X')

  assert_eq(lines(), { 'abcXdefXghi' }, 'both cursors should insert one X')
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 4 },
    { line = 0, col = 8 },
  }, 'same-line cursor columns should include earlier insert offsets')
end)

test('temporary selection delete keymaps are activated per buffer, not by one global latch', function()
  local plugin, actions = fresh_plugin()
  local buf_a = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_a)
  vim.api.nvim_buf_set_lines(buf_a, 0, -1, false, { 'alpha' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  plugin.setup({ mapping_strategy = 'skip', notify = false })
  actions.select_character('right')
  assert_true(get_buf_map(buf_a, '<BS>'), 'buffer A should receive a temporary Backspace map')

  local buf_b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_b)
  vim.api.nvim_buf_set_lines(buf_b, 0, -1, false, { 'bravo' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  plugin.setup({ mapping_strategy = 'skip', notify = false })
  actions.select_character('right')

  assert_true(get_buf_map(buf_b, '<BS>'), 'buffer B should receive its own temporary Backspace map')

  cleanup_buf_maps(buf_a, { '<BS>', '<Del>' })
  cleanup_buf_maps(buf_b, { '<BS>', '<Del>' })
end)

test('temporary selection delete keymaps restore pre-existing buffer-local mappings', function()
  local plugin, actions = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.keymap.set('i', '<BS>', '<C-o>:let g:vscode_style_original_bs = 1<CR>', {
    buffer = bufnr,
    desc = 'original-bs',
  })

  plugin.setup({ mapping_strategy = 'skip', notify = false })
  actions.select_character('right')
  assert_true(get_buf_map(bufnr, '<BS>'), 'temporary Backspace map should exist while selection is active')

  plugin.deactivate_selection_keymaps(bufnr)

  assert_eq(get_buf_map(bufnr, '<BS>').desc, 'original-bs', 'existing buffer-local Backspace map should be restored')
  cleanup_buf_maps(bufnr, { '<BS>', '<Del>' })
end)

test('re-running setup from another buffer cleans and restores buffer-local forced mappings in the original buffer', function()
  local plugin = fresh_plugin()
  local buf_a = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_a)
  vim.api.nvim_buf_set_lines(buf_a, 0, -1, false, { 'alpha' })
  vim.keymap.set('i', '<F20>', '<C-o>:let g:vscode_style_original_a = 1<CR>', {
    buffer = buf_a,
    desc = 'original-a',
  })

  plugin.setup({
    mapping_strategy = 'force',
    notify = false,
    keymaps = {
      move_line_up = {
        lhs = '<F20>',
        opts = { buffer = true, desc = 'plugin-buffer-a' },
      },
    },
  })
  assert_eq(get_buf_map(buf_a, '<F20>').desc, 'plugin-buffer-a', 'fixture should install forced plugin map')

  local buf_b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_b)
  vim.api.nvim_buf_set_lines(buf_b, 0, -1, false, { 'bravo' })
  plugin.setup({ mapping_strategy = 'skip', notify = false })

  vim.api.nvim_set_current_buf(buf_a)
  assert_eq(get_buf_map(buf_a, '<F20>').desc, 'original-a', 'original buffer-local map should be restored in buffer A')

  cleanup_buf_maps(buf_a, { '<F20>' })
  cleanup_buf_maps(buf_b, { '<F20>' })
end)

test('documented keymap opts.buf gets concrete-buffer cleanup instead of leaking maps', function()
  local plugin = fresh_plugin()
  local buf_a = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_a)
  vim.api.nvim_buf_set_lines(buf_a, 0, -1, false, { 'alpha' })

  plugin.setup({
    mapping_strategy = 'force',
    notify = false,
    keymaps = {
      move_line_down = {
        lhs = '<F21>',
        opts = { buf = 0, desc = 'plugin-buf-zero' },
      },
    },
  })
  assert_eq(get_buf_map(buf_a, '<F21>').desc, 'plugin-buf-zero', 'fixture should install buffer-local opts.buf mapping')

  local buf_b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_b)
  vim.api.nvim_buf_set_lines(buf_b, 0, -1, false, { 'bravo' })
  plugin.setup({ mapping_strategy = 'skip', notify = false })

  assert_eq(get_buf_map(buf_a, '<F21>'), nil, 'setup cleanup should delete the opts.buf mapping from buffer A')
  cleanup_buf_maps(buf_a, { '<F21>' })
  cleanup_buf_maps(buf_b, { '<F21>' })
end)

test('Ctrl+Shift+K deletes non-contiguous cursor lines without line-number shift lies', function()
  local env = setup_buffer({
    'one',
    'two',
    'three',
    'four',
  }, { cursor = { 1, 0 } })
  env.multi_cursor.add_cursor_at(2, 0)

  env.actions.delete_line()

  assert_eq(lines(), { 'two', 'four' }, 'delete-line should remove original lines one and three')
end)

local failures = {}

for _, entry in ipairs(tests) do
  local ok, err = xpcall(entry.fn, debug.traceback)
  if ok then
    print('ok - ' .. entry.name)
  else
    failures[#failures + 1] = { name = entry.name, err = err }
    print('not ok - ' .. entry.name)
    print(err)
  end
end

if #failures > 0 then
  print(string.format('%d/%d tests failed', #failures, #tests))
  os.exit(1)
end

print(string.format('%d tests passed', #tests))
