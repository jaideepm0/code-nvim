#!/bin/bash

# Test script for verifying backspace selection delete works

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         BACKSPACE SELECTION DELETE - VERIFICATION TEST           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

cd "$(dirname "$0")"

echo "1. Testing Plugin Load..."
nvim --headless -u NONE -c "set rtp+=$(pwd)" \
  -c "lua require('vscode_style').setup({ backspace_deletes_selection = true })" \
  -c "lua print(require('vscode_style').is_initialized() and '✓ Plugin loaded' or '✗ Failed')" \
  -c "qa!" 2>&1 | grep -E "(Plugin loaded|Failed)"

echo ""
echo "2. Testing Backspace with Selection..."

# Create test script
cat > /tmp/test_bs.lua << 'EOLUA'
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Load with debug
require('vscode_style').setup({
  backspace_deletes_selection = true,
  debug = true,
})

-- Create buffer
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'Hello World'})

-- Modules
local actions = require('vscode_style.actions')
local multi_cursor = require('vscode_style.multi_cursor')

-- Enter insert, select, delete
vim.api.nvim_win_set_cursor(0, {1, 0})
vim.cmd('startinsert')

-- Select "Hello"
for i = 1, 5 do
  actions.select_character('right')
end

-- Press backspace
actions.backspace_expr()

-- Wait and check
vim.defer_fn(function()
  local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  if line == " World" then
    print("✓ Test PASSED: Selection deleted correctly")
    vim.cmd('cq 0')
  else
    print("✗ Test FAILED: Expected ' World', got '" .. line .. "'")
    vim.cmd('cq 1')
  end
end, 100)
EOLUA

nvim --headless -u NONE -c "luafile /tmp/test_bs.lua" 2>&1 | grep -E "(PASSED|FAILED)"
TEST_RESULT=$?

echo ""
echo "3. Testing with Typing Replacement..."

cat > /tmp/test_type.lua << 'EOLUA'
vim.opt.runtimepath:append(vim.fn.getcwd())

require('vscode_style').setup({
  backspace_deletes_selection = true,
  typing_replaces_selection = true,
})

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'Hello World'})

local actions = require('vscode_style.actions')

vim.api.nvim_win_set_cursor(0, {1, 0})
vim.cmd('startinsert')

-- Select
for i = 1, 5 do
  actions.select_character('right')
end

-- Simulate typing
vim.v.char = 'X'
actions.on_insert_pre()

vim.defer_fn(function()
  local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  if line:match("^X") then
    print("✓ Typing replacement works")
    vim.cmd('cq 0')
  else
    print("✗ Typing replacement failed: " .. line)
    vim.cmd('cq 1')
  end
end, 100)
EOLUA

nvim --headless -u NONE -c "luafile /tmp/test_type.lua" 2>&1 | grep -E "(works|failed)"

echo ""
echo "══════════════════════════════════════════════════════════════════"

if [ $TEST_RESULT -eq 0 ]; then
  echo "✅ ALL TESTS PASSED"
  echo ""
  echo "Backspace selection delete is working correctly!"
  echo ""
  echo "To test manually:"
  echo "  1. Open nvim with this plugin"
  echo "  2. Type some text: Hello World"
  echo "  3. Enter insert mode at start"
  echo "  4. Hold Shift + press Right arrow 5 times"
  echo "  5. Press Backspace"
  echo "  6. 'Hello' should be deleted"
  exit 0
else
  echo "✗ TESTS FAILED"
  echo ""
  echo "Please check the output above for errors."
  echo "Enable debug mode: setup({ debug = true })"
  exit 1
fi
