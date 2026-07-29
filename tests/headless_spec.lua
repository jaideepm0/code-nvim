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

local function get_global_map(lhs)
  for _, map in ipairs(vim.api.nvim_get_keymap('i')) do
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
  local loaded = package.loaded['vscode_style']
  if type(loaded) == 'table' and type(loaded.disable) == 'function' then
    pcall(loaded.disable)
  end
  for _, command in ipairs({
    'VscodeStyleAggressiveEnable',
    'VscodeStyleAggressiveDisable',
    'VscodeStyleAggressiveToggle',
    'VscodeStyleAggressiveSuspend',
    'VscodeStyleAggressiveResume',
  }) do
    pcall(vim.api.nvim_del_user_command, command)
  end
  for _, name in ipairs({
    'vscode_style',
    'vscode_style.actions',
    'vscode_style.aggressive',
    'vscode_style.config',
    'vscode_style.eligibility',
    'vscode_style.multi_cursor',
    'vscode_style.util',
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

test('Ctrl+D wraps to the first unmatched occurrence', function()
  local env = setup_buffer({ 'foo foo foo tail' }, { cursor = { 1, 11 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 8, 0, 11, true),
  })

  env.actions.add_selection_to_next_match()

  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 3 },
    { line = 0, col = 11 },
  })
  local first = env.multi_cursor.get_positions()[1].cursor.selection
  assert_eq({ first.anchor.col, first.active.col }, { 0, 3 })
end)

test('Ctrl+D advances from the primary cursor instead of the last sorted cursor', function()
  local env = setup_buffer({ 'foo foo foo foo' }, { cursor = { 1, 0 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 3, true),
    selected_cursor(0, 8, 0, 11, false),
  })

  env.actions.add_selection_to_next_match()

  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 3 },
    { line = 0, col = 7 },
    { line = 0, col = 11 },
  })
end)

test('Ctrl+Shift+L keeps the current occurrence as the primary cursor', function()
  local env = setup_buffer({ 'foo foo foo' }, { cursor = { 1, 5 } })

  env.actions.select_all_occurrences()

  local primary = env.multi_cursor.primary()
  assert_eq({ primary.line, primary.col }, { 0, 7 })
  assert_eq({ primary.selection.anchor.col, primary.selection.active.col }, { 4, 7 })
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

test('one undo reverses an entire multi-cursor insertion', function()
  local env = setup_buffer({ 'abcdef' }, { cursor = { 1, 1 } })
  -- Establish the fixture as an undoable baseline before the operation under test.
  vim.cmd('silent undo')
  vim.cmd('silent redo')
  env.multi_cursor.add_cursor_at(0, 4)
  env.actions.insert_text_at_cursors('X')

  vim.cmd('silent undo')

  assert_eq(lines(), { 'abcdef' }, 'multi-cursor edits should share an undo transaction')
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

test('character selections stay on UTF-8 codepoint boundaries', function()
  local env = setup_buffer({ 'aé🙂b' }, { cursor = { 1, 7 } })

  env.actions.select_character('left')

  local selection = env.multi_cursor.primary().selection
  assert_eq({ selection.anchor.col, selection.active.col }, { 7, 3 }, 'left should select the entire emoji')
  assert_eq(
    vim.api.nvim_buf_get_text(env.bufnr, 0, selection.active.col, 0, selection.anchor.col, {}),
    { '🙂' },
    'selection must not split a multibyte character'
  )
end)

test('Ctrl+D selects the current Unicode word and its next occurrence', function()
  local env = setup_buffer({ 'café café' }, { cursor = { 1, 3 } })

  env.actions.add_selection_to_next_match()

  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 5 },
    { line = 0, col = 11 },
  }, 'both complete UTF-8 words should be selected')
  for _, item in ipairs(env.multi_cursor.get_positions()) do
    assert_true(item.cursor.selection ~= nil, 'every Ctrl+D cursor should own a selection')
  end
end)

test('replacing same-line occurrence selections preserves every collapse position', function()
  local env = setup_buffer({ 'foo foo' }, { cursor = { 1, 1 } })
  env.actions.select_all_occurrences()

  env.actions.delete_selection_and_cleanup()
  env.actions.insert_text_at_cursors('X')

  assert_eq(lines(), { 'X X' }, 'both occurrences should be replaced at their transformed positions')
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 1 },
    { line = 0, col = 3 },
  })
end)

test('Ctrl+Shift+L supports literal selections spanning lines', function()
  local env = setup_buffer({
    'one',
    'two',
    'one',
    'two',
  }, { cursor = { 2, 3 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 1, 3, true),
  })

  env.actions.select_all_occurrences()

  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 1, col = 3 },
    { line = 3, col = 3 },
  }, 'both multiline matches should be selected')
end)

test('multi-cursor Backspace deletes one complete character at every cursor', function()
  local env = setup_buffer({ 'aé b🙂' }, { cursor = { 1, 3 } })
  env.multi_cursor.add_cursor_at(0, 9)

  env.actions.handle_backspace()

  assert_eq(lines(), { 'a b' })
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 1 },
    { line = 0, col = 3 },
  })
end)

test('multi-cursor Enter preserves each line indentation', function()
  local env = setup_buffer({ '  aa', '\tb' }, { cursor = { 1, 3 } })
  env.multi_cursor.add_cursor_at(1, 2)

  env.actions.handle_enter()

  assert_eq(lines(), { '  a', '  a', '\tb', '\t' })
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 1, col = 2 },
    { line = 3, col = 1 },
  })
end)

test('copy-line handles disjoint ranges and moves cursors onto the copies', function()
  local env = setup_buffer({ 'a', 'b', 'c', 'd' }, { cursor = { 2, 0 } })
  env.multi_cursor.add_cursor_at(3, 0)

  env.actions.copy_line('up')

  assert_eq(lines(), { 'a', 'b', 'b', 'c', 'd', 'd' })
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 1, col = 0 },
    { line = 4, col = 0 },
  })
end)

test('copy-line-up keeps a cursor inside the newly inserted copy', function()
  local env = setup_buffer({ 'a', 'b', 'c' }, { cursor = { 2, 0 } })

  env.actions.copy_line('up')

  assert_eq(lines(), { 'a', 'b', 'b', 'c' })
  assert_eq(cursor_positions(env.multi_cursor), { { line = 1, col = 0 } })
end)

test('move-line merges adjacent cursor lines into one stable block', function()
  local env = setup_buffer({ 'a', 'b', 'c', 'd' }, { cursor = { 2, 0 } })
  env.multi_cursor.add_cursor_at(2, 0)

  env.actions.move_line('up')

  assert_eq(lines(), { 'b', 'c', 'a', 'd' })
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 0 },
    { line = 1, col = 0 },
  })
end)

test('move-line keeps exclusive full-line selection endpoints attached to the block', function()
  local env = setup_buffer({ 'a', 'b', 'c', 'd' }, { cursor = { 4, 0 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(1, 0, 3, 0, true),
  })

  env.actions.move_line('up')

  assert_eq(lines(), { 'b', 'c', 'a', 'd' })
  local selection = env.multi_cursor.primary().selection
  assert_eq({ selection.anchor.line, selection.active.line }, { 0, 2 })
  assert_eq(cursor_positions(env.multi_cursor), { { line = 2, col = 0 } })
end)

test('multi-cursor state is isolated and retained per buffer', function()
  local env = setup_buffer({ 'alpha', 'beta' }, { cursor = { 1, 1 } })
  env.multi_cursor.add_cursor_at(1, 1)
  local first_buf = env.bufnr
  vim.bo[first_buf].bufhidden = 'hide'

  local second_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(second_buf)
  vim.api.nvim_buf_set_lines(second_buf, 0, -1, false, { 'other' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  assert_eq(#env.multi_cursor.iter(), 1, 'second buffer should start with only its primary cursor')

  vim.api.nvim_set_current_buf(first_buf)
  vim.api.nvim_win_set_cursor(0, { 1, 1 })
  assert_eq(#env.multi_cursor.iter(), 2, 'first buffer cursors should not be discarded by a buffer switch')
  assert_eq(vim.api.nvim_win_get_cursor(0), { 1, 1 }, 'buffer switch should restore its primary caret')
end)

test('buffer cleanup discards deferred inserts for the destroyed buffer', function()
  local env = setup_buffer({ 'alpha' }, { cursor = { 1, 1 } })
  local pending = { chars = { 'x' } }
  env.plugin.get_state().pending_inserts[env.bufnr] = pending

  env.multi_cursor.cleanup_buffer(env.bufnr)

  assert_eq(env.plugin.get_state().pending_inserts[env.bufnr], nil)
end)

test('secondary cursors have a visible extmark overlay', function()
  local env = setup_buffer({ 'alpha' }, { cursor = { 1, 1 } })
  local secondary = env.multi_cursor.add_cursor_at(0, 3)
  local details = vim.api.nvim_buf_get_extmark_by_id(
    env.bufnr,
    env.plugin.get_state().ns,
    secondary.id,
    { details = true }
  )[3]

  assert_eq(details.virt_text[1][2], 'Cursor')
  assert_eq(details.virt_text_pos, 'overlay')
end)

test('cursor refresh batches extmark position reads', function()
  local env = setup_buffer({ string.rep('x', 80) }, { cursor = { 1, 0 } })
  for col = 2, 40, 2 do
    env.multi_cursor.add_cursor_at(0, col)
  end

  local original_bulk = vim.api.nvim_buf_get_extmarks
  local original_single = vim.api.nvim_buf_get_extmark_by_id
  local bulk_reads, single_reads = 0, 0
  vim.api.nvim_buf_get_extmarks = function(...)
    bulk_reads = bulk_reads + 1
    return original_bulk(...)
  end
  vim.api.nvim_buf_get_extmark_by_id = function(...)
    single_reads = single_reads + 1
    return original_single(...)
  end
  env.multi_cursor.refresh_from_extmarks()
  vim.api.nvim_buf_get_extmarks = original_bulk
  vim.api.nvim_buf_get_extmark_by_id = original_single

  assert_eq(bulk_reads, 1, 'one namespace traversal should synchronize every cursor')
  assert_eq(single_reads, 0, 'cursor synchronization should not issue one API call per cursor')
end)

test('cursor refresh follows extmark gravity after external edits', function()
  local env = setup_buffer({ 'abcdef' }, { cursor = { 1, 1 } })
  env.multi_cursor.add_cursor_at(0, 4)
  vim.api.nvim_buf_set_text(env.bufnr, 0, 0, 0, 0, { 'ZZ' })

  env.multi_cursor.refresh_from_extmarks()

  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 3 },
    { line = 0, col = 6 },
  })
end)

test('cursor refresh clamps every cursor after external truncation', function()
  local env = setup_buffer({ 'abcdef' }, { cursor = { 1, 1 } })
  env.multi_cursor.add_cursor_at(0, 5)

  vim.api.nvim_buf_set_lines(env.bufnr, 0, -1, false, { '' })
  env.multi_cursor.refresh_from_extmarks()
  env.actions.insert_text_at_cursors('X')

  assert_eq(lines(), { 'X' })
  assert_eq(cursor_positions(env.multi_cursor), { { line = 0, col = 1 } })
end)

test('selection endpoints follow extmark gravity after external edits', function()
  local env = setup_buffer({ 'abcdef' }, { cursor = { 1, 2 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 2, 0, 4, true),
  })
  vim.api.nvim_buf_set_text(env.bufnr, 0, 0, 0, 0, { 'ZZ' })

  env.multi_cursor.refresh_from_extmarks()

  local selection = env.multi_cursor.primary().selection
  assert_eq({ selection.anchor.col, selection.active.col }, { 4, 6 })
  assert_eq(vim.api.nvim_buf_get_text(env.bufnr, 0, 4, 0, 6, {}), { 'cd' })
end)

test('deleting one selection keeps unrelated cursors attached to edited text', function()
  local env = setup_buffer({ 'abcdef' }, {
    cursor = { 1, 1 },
    config = { aggressive = { enabled = false, clipboard_register = '"' } },
  })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 1, true),
    { line = 0, col = 4, is_primary = false },
  })

  local original_single_read = vim.api.nvim_buf_get_extmark_by_id
  local single_reads = 0
  vim.api.nvim_buf_get_extmark_by_id = function(...)
    single_reads = single_reads + 1
    return original_single_read(...)
  end
  env.actions.copy(true)
  vim.api.nvim_buf_get_extmark_by_id = original_single_read

  assert_eq(lines(), { 'bcdef' })
  assert_eq(single_reads, 0, 'selection deletion should resolve collapse marks in one bulk traversal')
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 0 },
    { line = 0, col = 3 },
  })
end)

test('disabling backspace feature disables both temporary deletion mappings', function()
  local env = setup_buffer({ 'abc' }, {
    config = { feature_flags = { backspace = false } },
  })
  env.actions.select_character('right')

  assert_eq(get_buf_map(env.bufnr, '<BS>'), nil)
  assert_eq(get_buf_map(env.bufnr, '<Del>'), nil)
end)

test('mixed selection and cursor backspace edits every cursor', function()
  local env = setup_buffer({ 'abcd' }, { cursor = { 1, 1 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 1, true),
    { line = 0, col = 3, is_primary = false },
  })

  env.actions.handle_backspace()

  assert_eq(lines(), { 'bd' })
end)

test('mixed selection and cursor delete edits every cursor', function()
  local env = setup_buffer({ 'abcd' }, { cursor = { 1, 1 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 1, true),
    { line = 0, col = 2, is_primary = false },
  })

  env.actions.handle_delete()

  assert_eq(lines(), { 'bd' })
end)

test('native movement inside a simulated selection collapses it', function()
  local env = setup_buffer({ 'abcd' }, { cursor = { 1, 1 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 3, true),
  })
  vim.api.nvim_win_set_cursor(0, { 1, 1 })

  env.actions.on_cursor_moved_i()

  assert_eq(env.multi_cursor.primary().selection, nil)
end)

test('disable does not delete a mapping replaced by the user after setup', function()
  local plugin = fresh_plugin()
  plugin.setup({
    mapping_strategy = 'force',
    notify = false,
    keymaps = {
      move_line_up = { lhs = '<F22>', desc = 'plugin-map' },
    },
  })
  vim.keymap.set('i', '<F22>', '<C-o>:let g:vscode_style_user_map = 1<CR>', { desc = 'user-map' })

  plugin.disable()

  local map
  for _, candidate in ipairs(vim.api.nvim_get_keymap('i')) do
    if candidate.lhs == '<F22>' then
      map = candidate
      break
    end
  end
  assert_eq(map and map.desc, 'user-map', 'teardown should preserve a newer user mapping')
  pcall(vim.keymap.del, 'i', '<F22>')
end)

test('disable removes modifier-order-normalized default mappings', function()
  local plugin = fresh_plugin()
  plugin.setup({ mapping_strategy = 'force', notify = false })
  assert_true(vim.fn.maparg('<M-S-Up>', 'i') ~= '', 'copy-line mapping should be installed')

  plugin.disable()

  assert_eq(vim.fn.maparg('<M-S-Up>', 'i'), '', 'canonicalized Alt+Shift mapping should be removed')
  assert_eq(vim.fn.maparg('<CR>', 'i'), '', 'plugin newline mapping should be removed')
end)

test('setup tolerates a non-table configuration value', function()
  local plugin = fresh_plugin()
  plugin.setup('invalid configuration')
  assert_eq(plugin.get_state().config.max_cursors, 32)
  plugin.disable()
end)

test('regular global mappings yield safely in excluded buffers', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'plugin prompt' })
  plugin.setup({
    mapping_strategy = 'force',
    notify = false,
    keymaps = { select_character_right = { lhs = '<F18>' } },
  })
  local map = get_global_map('<F18>')
  assert_true(map and type(map.callback) == 'function')
  local original_feedkeys = vim.api.nvim_feedkeys
  local fallback_calls = 0
  vim.api.nvim_feedkeys = function(...)
    fallback_calls = fallback_calls + 1
    return original_feedkeys(...)
  end

  map.callback()
  vim.api.nvim_feedkeys = original_feedkeys
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })
  vim.api.nvim_exec_autocmds('CursorMovedI', { buffer = bufnr })
  vim.api.nvim_exec_autocmds('InsertLeave', { buffer = bufnr })
  assert_eq(plugin.get_cursors(), {})
  assert_eq(plugin.get_cursor_count(), 0)

  assert_eq(fallback_calls, 1, 'excluded regular buffers should receive native fallback input')
  assert_eq(#plugin.get_state().cursors, 0, 'fallback dispatch should not initialize simulated cursor state')
  assert_eq(plugin.get_state().buffer_states[bufnr], nil, 'core autocmds should leave excluded buffers untouched')
  assert_true(not plugin.is_buffer_active(bufnr))
  plugin.disable()
end)

test('shared buffer policy can opt a regular special buffer in without hot-path reevaluation', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'special editor' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local policy_calls = 0
  plugin.setup({
    mapping_strategy = 'force',
    notify = false,
    buffer_policy = {
      should_handle = function(candidate, _, context)
        policy_calls = policy_calls + 1
        return candidate == bufnr and context == 'regular'
      end,
    },
    keymaps = { select_character_right = { lhs = '<F18>' } },
  })
  local calls_after_setup = policy_calls
  local map = get_global_map('<F18>')

  map.callback()
  map.callback()

  assert_eq(policy_calls, calls_after_setup, 'cached regular dispatch should not rerun user policy on every key')
  assert_true(plugin.get_cursors()[1].selection ~= nil)
  assert_true(plugin.is_buffer_active(bufnr))
  plugin.disable()
end)

test('shared buffer policy is applied consistently to regular and aggressive lifecycles', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  local contexts = {}
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    buffer_policy = {
      should_handle = function(_, _, context)
        contexts[context] = true
      end,
    },
    aggressive = { enabled = true, auto_insert = false },
  })

  assert_true(contexts.regular, 'regular lifecycle should consult the shared policy')
  assert_true(contexts.aggressive, 'aggressive lifecycle should consult the shared policy')
  assert_true(plugin.is_buffer_active(bufnr))
  plugin.disable()
end)

test('regular eligibility cache follows editable option changes', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  plugin.setup({ mapping_strategy = 'skip', notify = false })
  assert_true(plugin.is_buffer_active(bufnr))

  vim.bo[bufnr].readonly = true
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'readonly' })
  assert_true(not plugin.is_buffer_active(bufnr))

  vim.bo[bufnr].readonly = false
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'readonly' })
  assert_true(plugin.is_buffer_active(bufnr))
  plugin.disable()
end)

test('regular policy resolves a window belonging to a non-current buffer', function()
  local plugin = fresh_plugin()
  local file_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(file_buf)
  vim.api.nvim_buf_set_lines(file_buf, 0, -1, false, { 'alpha' })
  plugin.setup({ mapping_strategy = 'skip', notify = false })
  plugin.get_state().regular_buffers[file_buf] = nil

  local ui_buf = vim.api.nvim_create_buf(false, true)
  local floating = vim.api.nvim_open_win(ui_buf, true, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = 20,
    height = 2,
    style = 'minimal',
  })

  assert_true(plugin.is_buffer_active(file_buf), 'target file should use its own non-floating window')
  vim.api.nvim_win_close(floating, true)
  plugin.disable()
end)

test('regular eligibility is scoped to the active window', function()
  local plugin = fresh_plugin()
  local file_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(file_buf)
  vim.api.nvim_buf_set_lines(file_buf, 0, -1, false, { 'alpha' })
  local main_win = vim.api.nvim_get_current_win()
  plugin.setup({ mapping_strategy = 'skip', notify = false })

  local floating = vim.api.nvim_open_win(file_buf, true, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = 20,
    height = 2,
    style = 'minimal',
  })
  assert_true(not plugin.is_buffer_active(file_buf), 'floating windows should not activate regular editing')
  vim.api.nvim_set_current_win(main_win)
  assert_true(plugin.is_buffer_active(file_buf), 'the same buffer remains active in its normal window')
  vim.api.nvim_win_close(floating, true)
  plugin.disable()
end)

test('wiped buffers are cleaned even when optional cleanup is disabled', function()
  local env = setup_buffer({ 'alpha' }, {
    config = { autocommands = { buf_cleanup = false } },
  })
  env.multi_cursor.add_cursor_at(0, 3)
  local bufnr = env.bufnr

  vim.api.nvim_buf_delete(bufnr, { force = true })

  assert_eq(env.plugin.get_state().buffer_states[bufnr], nil)
  assert_eq(env.plugin.get_state().regular_buffers[bufnr], nil)
end)

test('disabled public probes do not recreate cursor state or aggressive mode', function()
  local env = setup_buffer({ 'alpha' }, { cursor = { 1, 1 } })
  env.multi_cursor.add_cursor_at(0, 3)
  env.plugin.disable()

  assert_true(not env.plugin.is_enabled())
  assert_eq(env.plugin.get_cursors(), {})
  assert_eq(env.plugin.get_cursor_count(), 0)
  assert_true(not env.plugin.is_buffer_active(env.bufnr))
  assert_true(not env.plugin.enable_aggressive_mode())
  assert_true(not env.plugin.disable_aggressive_mode())
  assert_true(not env.plugin.toggle_aggressive_mode())
  assert_true(not env.plugin.suspend_aggressive_mode(env.bufnr))
  assert_true(not env.plugin.resume_aggressive_mode(env.bufnr))
  assert_true(not env.plugin.is_aggressive_mode())
  assert_eq(next(env.plugin.get_state().buffer_states), nil, 'read-only probes must not recreate buffer state')
end)

test('select-all occurrence scanning respects max_cursors', function()
  local env = setup_buffer({ string.rep('x ', 200) }, {
    cursor = { 1, 0 },
    config = { max_cursors = 7 },
  })

  env.actions.select_all_occurrences()

  assert_eq(#env.multi_cursor.get_positions(), 7, 'large match sets should be capped during collection')
end)

test('select-all occurrence scanning retains the active match at the cap', function()
  local env = setup_buffer({ 'foo foo foo' }, {
    cursor = { 1, 9 },
    config = { max_cursors = 2 },
  })

  env.actions.select_all_occurrences()

  local primary = env.multi_cursor.primary()
  assert_eq({ primary.line, primary.col }, { 0, 11 })
  assert_eq(#env.multi_cursor.get_positions(), 2)
end)

test('single-line occurrence scanning finds adjacent matches across lines', function()
  local env = setup_buffer({ 'foofoo', 'xfoo', 'foo' }, { cursor = { 1, 3 } })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 3, true),
  })

  env.actions.select_all_occurrences()

  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 3 },
    { line = 0, col = 6 },
    { line = 1, col = 4 },
    { line = 2, col = 3 },
  })
end)

test('aggressive mode attaches ordinary Insert-mode shortcuts only to editable file buffers', function()
  local plugin = fresh_plugin()
  local file_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(file_buf)
  vim.api.nvim_buf_set_lines(file_buf, 0, -1, false, { 'editable' })
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = false, terminal_startinsert = false },
  })

  assert_true(get_buf_map(file_buf, '<Left>'), 'editable file buffer should receive aggressive navigation')
  assert_true(get_buf_map(file_buf, '<C-A>'), 'editable file buffer should receive select-all')
  assert_true(plugin.is_aggressive_mode(), 'aggressive controller should report enabled')
  assert_true(plugin.is_aggressive_buffer(file_buf), 'file buffer should report active')

  local main_win = vim.api.nvim_get_current_win()
  local floating_file = vim.api.nvim_open_win(file_buf, true, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = 20,
    height = 2,
    style = 'minimal',
  })
  assert_true(not plugin.is_aggressive_buffer(file_buf), 'aggressive editing should yield in floating windows')
  vim.api.nvim_set_current_win(main_win)
  assert_true(plugin.is_aggressive_buffer(file_buf), 'aggressive editing should remain active in normal windows')
  vim.api.nvim_win_close(floating_file, true)

  local ui_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[ui_buf].buftype = 'nofile'
  vim.api.nvim_set_current_buf(ui_buf)
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = ui_buf })
  assert_eq(get_buf_map(ui_buf, '<Left>'), nil, 'nofile UI should not receive aggressive mappings')
  assert_true(not plugin.is_aggressive_buffer(ui_buf), 'nofile UI should not report active')

  plugin.disable()
end)

test('aggressive respect strategy leaves plugin mappings untouched', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  vim.keymap.set('i', '<C-s>', '<C-o>:let g:vscode_style_existing_save = 1<CR>', {
    buffer = bufnr,
    desc = 'existing-save',
  })

  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = false },
  })

  assert_eq(get_buf_map(bufnr, '<C-S>').desc, 'existing-save')
  plugin.disable()
  assert_eq(get_buf_map(bufnr, '<C-S>').desc, 'existing-save', 'existing mapping should survive teardown')
  cleanup_buf_maps(bufnr, { '<C-s>' })
end)

test('aggressive force strategy restores a displaced buffer mapping', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  vim.keymap.set('i', '<F23>', '<C-o>:let g:vscode_style_original_f23 = 1<CR>', {
    buffer = bufnr,
    desc = 'original-f23',
  })

  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = {
      enabled = true,
      auto_insert = false,
      mapping_strategy = 'force',
      keymaps = { save = { lhs = '<F23>', desc = 'aggressive-save' } },
    },
  })

  assert_eq(get_buf_map(bufnr, '<F23>').desc, 'VS Code aggressive: aggressive-save')
  plugin.disable_aggressive_mode()
  assert_eq(get_buf_map(bufnr, '<F23>').desc, 'original-f23')
  cleanup_buf_maps(bufnr, { '<F23>' })
  plugin.disable()
end)

test('aggressive buffers can be suspended and resumed without touching core state', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = false },
  })

  plugin.suspend_aggressive_mode(bufnr)
  assert_eq(get_buf_map(bufnr, '<Left>'), nil)
  assert_true(not plugin.is_aggressive_buffer(bufnr))

  plugin.resume_aggressive_mode(bufnr)
  assert_true(get_buf_map(bufnr, '<Left>'))
  assert_true(plugin.is_aggressive_buffer(bufnr))
  plugin.disable()
end)

test('aggressive Escape dismisses cursor state before opening a Normal-mode session', function()
  local plugin, _, multi_cursor = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha', 'beta' })
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = false },
  })
  multi_cursor.add_cursor_at(1, 0)
  local escape = get_buf_map(bufnr, '<Esc>')
  assert_true(escape and type(escape.callback) == 'function')

  escape.callback()
  assert_eq(#multi_cursor.iter(), 1, 'first Escape should remove secondary cursors')
  assert_true(not plugin.is_aggressive_normal_mode(bufnr))

  escape.callback()
  assert_true(plugin.is_aggressive_normal_mode(bufnr), 'second Escape should yield to real Normal mode')
  assert_true(plugin.is_aggressive_buffer(bufnr), 'temporary Normal mode should keep aggressive attachment ready')

  vim.api.nvim_exec_autocmds('InsertEnter', { buffer = bufnr })
  assert_true(not plugin.is_aggressive_normal_mode(bufnr), 'native Insert entry should restore aggressive editing')
  plugin.disable()
end)

test('aggressive Normal-mode API is safe when inactive and configurable', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = false, escape_to_normal = false },
  })

  local escape = get_buf_map(bufnr, '<Esc>')
  local original_feedkeys = vim.api.nvim_feedkeys
  local feed_count = 0
  vim.api.nvim_feedkeys = function(...)
    feed_count = feed_count + 1
    return original_feedkeys(...)
  end
  escape.callback()
  vim.api.nvim_feedkeys = original_feedkeys
  assert_eq(feed_count, 1, 'disabled Normal-mode entry should forward Escape natively')
  assert_true(not plugin.is_aggressive_normal_mode(bufnr), 'escape_to_normal=false should preserve legacy behavior')

  plugin.disable_aggressive_mode()
  assert_true(not plugin.enter_normal_mode(bufnr), 'inactive aggressive mode should reject Normal-mode sessions')
  plugin.disable()
end)

test('clean aggressive Escape suppresses auto-insert without allocating cursor state', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  local original_cmd = vim.cmd
  local startinsert_calls = 0
  vim.cmd = function(command)
    if command == 'startinsert' then
      startinsert_calls = startinsert_calls + 1
      return
    end
    return original_cmd(command)
  end

  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = true },
  })
  local escape = get_buf_map(bufnr, '<Esc>')
  escape.callback()
  vim.api.nvim_exec_autocmds('InsertLeave', { buffer = bufnr })
  vim.wait(10)
  vim.cmd = original_cmd

  assert_true(plugin.is_aggressive_normal_mode(bufnr))
  assert_eq(startinsert_calls, 0, 'temporary Normal mode must suppress scheduled aggressive re-entry')
  assert_eq(plugin.get_state().buffer_states[bufnr], nil, 'clean Escape should not allocate multi-cursor state')
  plugin.disable()
end)

test('Ctrl+U walks back cursor additions without undoing text', function()
  local env = setup_buffer({ 'one', 'two', 'three' }, { cursor = { 1, 0 } })
  env.actions.add_cursor_vertical('down')
  env.actions.add_cursor_vertical('down')
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 0 },
    { line = 1, col = 0 },
    { line = 2, col = 0 },
  })

  assert_true(env.actions.undo_cursor_state())
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 0 },
    { line = 1, col = 0 },
  })
  assert_true(env.actions.undo_cursor_state())
  assert_eq(cursor_positions(env.multi_cursor), { { line = 0, col = 0 } })
  assert_eq(lines(), { 'one', 'two', 'three' })
end)

test('external text changes invalidate raw cursor-history positions', function()
  local env = setup_buffer({ 'one', 'two' }, { cursor = { 1, 0 } })
  env.actions.add_cursor_vertical('down')
  vim.api.nvim_buf_set_lines(env.bufnr, 0, 0, false, { 'inserted externally' })
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = env.bufnr })

  assert_true(not env.actions.undo_cursor_state())
  assert_eq(#env.multi_cursor.iter(), 2)
end)

test('completion-menu text changes invalidate raw cursor-history positions', function()
  local env = setup_buffer({ 'one', 'two' }, { cursor = { 1, 0 } })
  env.actions.add_cursor_vertical('down')
  vim.api.nvim_exec_autocmds('TextChangedP', { buffer = env.bufnr })

  assert_true(not env.actions.undo_cursor_state())
  assert_eq(#env.multi_cursor.iter(), 2)
end)

test('external text changes invalidate expansion history safely', function()
  local env = setup_buffer({ 'if', '  child', 'outside' }, { cursor = { 2, 4 } })
  env.actions.expand_selection()
  env.actions.expand_selection()
  env.actions.expand_selection()
  vim.api.nvim_buf_set_lines(env.bufnr, 0, 1, false, { 'else' })
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = env.bufnr })

  env.actions.shrink_selection()

  assert_eq(env.multi_cursor.primary().selection, nil)
end)

test('empty cursor-history stacks are harmless and cleaned up', function()
  local env = setup_buffer({ 'one' }, { cursor = { 1, 0 } })
  local snapshots = env.plugin.get_state().snapshots
  snapshots[env.bufnr] = {}

  assert_true(not env.multi_cursor.restore_snapshot())
  assert_eq(snapshots[env.bufnr], nil)

  snapshots[env.bufnr] = {}
  env.multi_cursor.discard_snapshot()
  assert_eq(snapshots[env.bufnr], nil)
end)

test('aggressive cursor movement operates on every cursor and collapses selections', function()
  local env = setup_buffer({ 'abcdef' }, { cursor = { 1, 1 } })
  env.multi_cursor.add_cursor_at(0, 4)
  env.actions.move_cursor('character', 'right')
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 2 },
    { line = 0, col = 5 },
  })

  env.multi_cursor.for_each(function(cursor)
    env.multi_cursor.set_selection(cursor, { line = 0, col = cursor.col - 1 }, { line = 0, col = cursor.col })
  end)
  env.actions.move_cursor('character', 'left')
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 1 },
    { line = 0, col = 4 },
  }, 'left should collapse each selection to its own start')
end)

test('aggressive paste replaces every active selection from a regular register', function()
  local env = setup_buffer({ 'foo foo' }, {
    cursor = { 1, 3 },
    config = { aggressive = { enabled = false, clipboard_register = '"' } },
  })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 3, true),
    selected_cursor(0, 4, 0, 7, false),
  })
  vim.fn.setreg('"', 'X', 'v')

  env.actions.paste()

  assert_eq(lines(), { 'X X' })
  assert_eq(cursor_positions(env.multi_cursor), {
    { line = 0, col = 1 },
    { line = 0, col = 3 },
  })
end)

test('multi-selection clipboard payload pastes one-to-one at matching cursors', function()
  local env = setup_buffer({ 'aa bb' }, {
    cursor = { 1, 2 },
    config = { aggressive = { enabled = false, clipboard_register = '"' } },
  })
  env.multi_cursor.replace_all_cursors({
    selected_cursor(0, 0, 0, 2, true),
    selected_cursor(0, 3, 0, 5, false),
  })

  env.actions.copy(true)
  assert_eq(lines(), { ' ' })
  env.actions.paste()

  assert_eq(lines(), { 'aa bb' })
end)

test('aggressive linewise paste preserves copied-line semantics', function()
  local env = setup_buffer({ 'one', 'two' }, {
    cursor = { 2, 1 },
    config = { aggressive = { enabled = false, clipboard_register = '"' } },
  })
  vim.fn.setreg('"', { 'copied' }, 'V')

  env.actions.paste()

  assert_eq(lines(), { 'one', 'copied', 'two' })
  assert_eq(cursor_positions(env.multi_cursor), { { line = 2, col = 1 } })
end)

test('aggressive should_attach can explicitly opt an excluded buffer in', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'special editor' })
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = {
      enabled = true,
      auto_insert = false,
      should_attach = function(candidate)
        return candidate == bufnr
      end,
    },
  })

  assert_true(plugin.is_aggressive_buffer(bufnr))
  assert_true(get_buf_map(bufnr, '<Left>'))
  plugin.disable()
end)

test('aggressive key callbacks use cached lifecycle eligibility', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  local eligibility_checks = 0
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = {
      enabled = true,
      auto_insert = false,
      should_attach = function(candidate)
        eligibility_checks = eligibility_checks + 1
        return candidate == bufnr
      end,
    },
  })

  local checks_after_attach = eligibility_checks
  local map = get_buf_map(bufnr, '<Left>')
  assert_true(map and type(map.callback) == 'function')
  for _ = 1, 10 do
    map.callback()
  end

  assert_eq(eligibility_checks, checks_after_attach, 'hot-path key callbacks should not rerun attachment policy')
  assert_true(plugin.is_aggressive_buffer(bufnr))
  assert_eq(eligibility_checks, checks_after_attach, 'status checks should read cached active state')
  plugin.disable()
end)

test('aggressive setup invalidates stale scheduled Insert-mode transitions', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  local original_cmd = vim.cmd
  local startinsert_calls = 0
  vim.cmd = function(command)
    if command == 'startinsert' then
      startinsert_calls = startinsert_calls + 1
      return
    end
    return original_cmd(command)
  end

  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = true },
  })
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = false },
  })
  vim.wait(10)
  vim.cmd = original_cmd

  assert_eq(startinsert_calls, 0, 'a prior setup must not re-enter Insert mode after reconfiguration')
  plugin.disable()
end)

test('aggressive action override replaces a definition built-in callback', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha' })
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = {
      enabled = true,
      auto_insert = false,
      keymaps = { save = { lhs = '<F24>', action = 'select_all' } },
    },
  })

  local map = get_buf_map(bufnr, '<F24>')
  assert_true(map and type(map.callback) == 'function')
  map.callback()
  assert_true(require('vscode_style.multi_cursor').primary().selection ~= nil)
  plugin.disable()
end)

test('aggressive movement merges cursors that converge at one position', function()
  local env = setup_buffer({ 'abcde' }, { cursor = { 1, 4 } })
  env.multi_cursor.add_cursor_at(0, 5)

  env.actions.move_cursor('character', 'right')

  assert_eq(cursor_positions(env.multi_cursor), { { line = 0, col = 5 } })
  env.actions.insert_text_at_cursors('X')
  local _, insertions = lines()[1]:gsub('X', '')
  assert_eq(insertions, 1, 'converged cursors must apply the next edit only once')
end)

test('aggressive mode attaches when a current buffer becomes editable', function()
  local plugin = fresh_plugin()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].readonly = true
  plugin.setup({
    mapping_strategy = 'skip',
    notify = false,
    aggressive = { enabled = true, auto_insert = false },
  })
  assert_eq(get_buf_map(bufnr, '<Left>'), nil)

  vim.bo[bufnr].readonly = false
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'readonly' })

  assert_true(get_buf_map(bufnr, '<Left>'))
  vim.bo[bufnr].readonly = true
  vim.api.nvim_exec_autocmds('OptionSet', { pattern = 'readonly' })
  assert_eq(get_buf_map(bufnr, '<Left>'), nil)
  plugin.disable()
end)

test('aggressive commands do not overwrite commands owned by another plugin', function()
  local plugin = fresh_plugin()
  vim.g.vscode_style_foreign_command = nil
  vim.api.nvim_create_user_command('VscodeStyleAggressiveEnable', function()
    vim.g.vscode_style_foreign_command = true
  end, {})

  plugin.setup({ mapping_strategy = 'skip', notify = false })
  plugin.disable()
  vim.cmd('VscodeStyleAggressiveEnable')

  assert_true(vim.g.vscode_style_foreign_command)
  pcall(vim.api.nvim_del_user_command, 'VscodeStyleAggressiveEnable')
end)

test('aggressive teardown preserves a command replaced after setup', function()
  local plugin = fresh_plugin()
  plugin.setup({ mapping_strategy = 'skip', notify = false })
  vim.api.nvim_del_user_command('VscodeStyleAggressiveEnable')
  vim.g.vscode_style_replaced_command = nil
  vim.api.nvim_create_user_command('VscodeStyleAggressiveEnable', function()
    vim.g.vscode_style_replaced_command = true
  end, {})

  plugin.disable()
  vim.cmd('VscodeStyleAggressiveEnable')

  assert_true(vim.g.vscode_style_replaced_command)
  pcall(vim.api.nvim_del_user_command, 'VscodeStyleAggressiveEnable')
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
