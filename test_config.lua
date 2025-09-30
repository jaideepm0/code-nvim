-- Minimal test configuration for code-nvim
-- Test backspace delete functionality

-- Clear any existing setup
if pcall(require, 'vscode_style') then
  package.loaded['vscode_style'] = nil
  package.loaded['vscode_style.init'] = nil
  package.loaded['vscode_style.actions'] = nil
  package.loaded['vscode_style.multi_cursor'] = nil
  package.loaded['vscode_style.config'] = nil
  package.loaded['vscode_style.utils'] = nil
  package.loaded['code-nvim'] = nil
end

-- Load plugin with debug enabled
require('vscode_style').setup({
  -- Enable backspace deletion
  backspace_deletes_selection = true,
  
  -- Enable debug for testing
  debug = true,
  log_level = 'debug',
  
  -- All features enabled
  features = {
    selection = true,
    multi_cursor = true,
    line_manipulation = true,
    column_selection = true,
  },
})

print("✓ Plugin loaded with backspace delete enabled")
print("✓ Debug mode ON")
print("")
print("Testing Instructions:")
print("1. Enter insert mode")
print("2. Hold Shift and press arrow keys to select text")
print("3. Press Backspace")
print("4. Selected text should be deleted")
print("")
print("Check :messages for debug output")
