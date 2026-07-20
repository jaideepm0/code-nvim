# VS Code-style insert editing for Neovim

`code-nvim` implements familiar VS Code editing gestures without making you leave Insert mode. Selections and secondary cursors are simulated with byte-accurate Neovim extmarks, kept separately per buffer, and updated after edits.

## Features

| Keys | Action |
| --- | --- |
| `Shift+Left/Right` | Extend the selection by one UTF-8 character |
| `Shift+Up/Down` | Extend the selection vertically |
| `Ctrl+Shift+Left/Right` | Extend by a word or symbol group |
| `Shift+Home/End` | Extend to the start or end of the line |
| `Ctrl+Shift+Home/End` | Extend to the start or end of the file |
| `Alt+Up/Down` | Move the selected/current lines |
| `Shift+Alt+Up/Down` | Copy the selected/current lines |
| `Ctrl+Shift+K` | Delete the selected/current lines |
| `Alt+Click` | Add a secondary cursor |
| `Ctrl+Alt+Up/Down` | Add cursors above or below |
| `Ctrl+D` | Select the current word and add its next literal match |
| `Ctrl+Shift+L` | Select all literal occurrences, including multiline text |
| `Shift+Alt+Right/Left` | Expand or shrink the selection stack |
| `Shift+Alt+Drag` | Make a virtual-column-aware box selection |
| `Tab` / `Shift+Tab` | Indent or dedent selected lines/all cursor lines |
| `Backspace` / `Delete` | Delete selections or one character at every cursor |
| `Enter` | Insert a newline at every cursor while preserving leading indent |

Typing replaces every active selection. Typing `'`, `"`, `(`, `{`, `[`, or `<` around a selection inserts the matching closing delimiter. Printable multi-cursor input is queued and coalesced outside `InsertCharPre`, where Neovim's `textlock` prevents direct buffer changes.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jaideepm0/code-nvim",
  config = function()
    require("vscode_style").setup()
  end,
}
```

For a manual installation, add the repository to `runtimepath` and call:

```lua
require("vscode_style").setup()
```

The plugin never enables itself automatically. Normal-mode mappings are not created.

## Aggressive mode

Aggressive mode turns an ordinary editable buffer into a persistent, non-modal editing surface. It enters Insert mode when an editor window gains focus, keeps normal movement and editing keys working at every simulated cursor, and re-enters Insert mode if an editor action temporarily leaves it.

```lua
require("vscode_style").setup({
  aggressive = true,
})
```

In addition to the selection and multi-cursor bindings above, aggressive mode provides these Insert-mode bindings:

| Keys | Action |
| --- | --- |
| `Left/Right/Up/Down`, `Home/End` | Move every cursor or collapse every selection |
| `Ctrl+Left/Right`, `Ctrl+Home/End` | Move by word or file boundary |
| `Ctrl+Backspace/Delete` | Delete a word at every cursor |
| `Ctrl+A/C/X/V` | Select all, copy, cut, or paste |
| `Ctrl+Z`, `Ctrl+Y` / `Ctrl+Shift+Z` | Undo or redo |
| `Ctrl+U` | Undo the last multi-cursor or selection operation |
| `Ctrl+S`, `Ctrl+F` | Save or enter Neovim's search command line |
| `Ctrl+PageUp/PageDown` | Switch buffers |
| `Click` | Move the primary cursor and clear secondary cursors |
| `Esc` | Dismiss completion/snippets or simulated cursor state; when none remains, enter real Normal mode |
| `Ctrl+Alt+Esc` | Suspend aggressive mode for the buffer and return to regular Neovim |

The controller deliberately does not attach editing mappings to terminal, prompt, help, quickfix, `nofile`, read-only, or floating UI buffers. Terminal buffers are put into terminal-input mode, and returning to an eligible file buffer restores the non-modal editing experience. Buffer-local mappings from completion engines, snippets, and other plugins win by default.

`Esc` is contextual: the first press closes completion or snippets and clears selections/secondary cursors; once there is nothing to dismiss, it opens a temporary real Normal-mode session. Use ordinary `i`, `a`, `o`, or another native Insert command to return to aggressive editing automatically. `Ctrl+Alt+Esc` remains available when you want the buffer to stay suspended across Insert entries.

Repeated `Ctrl+D` wraps through unmatched literal occurrences. `Ctrl+U` walks back the bounded cursor-state history without undoing buffer text. Copying several selections also records their individual payloads, so a paste with the same number of cursors restores each selection one-for-one; external clipboard text continues to paste identically at every cursor.

Runtime controls are available as both Lua functions and commands:

```lua
local vscode = require("vscode_style")
vscode.enable_aggressive_mode()
vscode.disable_aggressive_mode()
vscode.suspend_aggressive_mode() -- current buffer only
vscode.resume_aggressive_mode()
vscode.enter_normal_mode() -- temporary; native Insert commands return automatically
```

The corresponding commands are `:VscodeStyleAggressiveEnable`, `:VscodeStyleAggressiveDisable`, `:VscodeStyleAggressiveToggle`, `:VscodeStyleAggressiveSuspend`, and `:VscodeStyleAggressiveResume`. `is_aggressive_mode()` and `is_aggressive_buffer()` can be used in a statusline. Mode changes emit the `User VscodeStyleAggressiveModeChanged` event.

## Configuration

```lua
require("vscode_style").setup({
  selection_hl = "Visual", -- highlight group, or false
  cursor_hl = "Cursor", -- secondary-cursor overlay, or false
  max_cursors = 32,
  mapping_strategy = "respect", -- "respect", "force", or "skip"
  feature_flags = {
    selection = true,
    line_ops = true,
    multi_cursor = true,
    column_selection = true,
    tab = true,
    backspace = true,
    surround = true,
  },
  autocommands = {
    insert_char_pre = true,
    insert_leave = true,
    buf_enter = true,
    buf_cleanup = true,
    cursor_moved_i = true,
    text_changed = true,
  },
  notify = vim.notify, -- a function, or false
  buffer_policy = {
    allow_floating = false,
    exclude_buftypes = { "acwrite", "help", "nofile", "nowrite", "prompt", "quickfix", "terminal" },
    exclude_filetypes = { "TelescopePrompt", "lazy", "neo-tree" },
    should_handle = function(bufnr, winid, context)
      -- context is "regular" or "aggressive". Return true/false to
      -- override the defaults, or nil to retain them.
    end,
  },
  aggressive = {
    enabled = true,
    auto_insert = true,
    escape_to_normal = true,
    terminal_startinsert = true,
    mapping_strategy = "respect", -- or "force", scoped per eligible buffer
    clipboard_register = "+",
    -- These inherit buffer_policy and can be overridden for aggressive mode:
    allow_floating = false,
    exclude_buftypes = { "nofile", "prompt", "quickfix", "terminal" },
    exclude_filetypes = { "TelescopePrompt", "lazy", "neo-tree" },
    should_attach = function(bufnr, winid)
      -- Return true/false to decide, or nil to keep the default decision.
    end,
    keymaps = {
      save = { lhs = "<C-s>" },
      suspend = { lhs = "<C-M-Esc>" },
      find = false,
    },
  },
  keymaps = {
    move_line_up = { lhs = "<A-k>", desc = "Move line up" },
    add_selection_next = { lhs = { "<C-d>", "<Leader>d" } },
    backspace = false,
    select_all_occurrences = {
      callback = function()
        -- A complete custom Insert-mode action.
      end,
    },
  },
})
```

`mapping_strategy = "respect"` installs only globally free shortcuts (and respects a target buffer-local mapping when `opts.buffer` is used). `"force"` replaces existing mappings and restores them during the next setup or `disable()` call. `"skip"` installs no persistent mappings, which is useful when another layer calls the action functions directly.

Regular and aggressive dispatch share `buffer_policy`. Even when a regular mapping is global, it yields to Neovim's native key behavior in excluded, unmodifiable, read-only, unloaded, or disallowed floating buffers. Eligibility is cached on buffer/window/filetype events and refreshed when `buftype`, `modifiable`, or `readonly` changes, so user policy callbacks do not run on every keypress.

Individual keymap overrides accept `false`, a replacement `lhs` string/list, or a table containing `enabled`, `lhs`, `opts`, `desc`, `callback`, `action`, and `args`. Use `require("vscode_style.config").keymap_definitions()` to inspect the supported names.

Aggressive keymap overrides use the same `false`, string/list, or `{ enabled, lhs, desc, callback, action, args }` forms under `aggressive.keymaps`. Set `vim.b.vscode_style_aggressive_disable = true` to exclude one buffer, or `vim.b.vscode_style_aggressive_enable = true` to opt a special buffer in. The `respect` strategy never replaces an existing buffer-local or global Insert-mode mapping. The `force` strategy restores displaced buffer-local mappings when aggressive mode detaches, as long as another plugin has not replaced the aggressive mapping in the meantime.

`aggressive.should_attach` is evaluated on buffer/window lifecycle and eligibility-option events, then cached for key dispatch. If external state used by the callback changes independently, call `resume_aggressive_mode(bufnr)` to refresh that buffer's attachment decision.

To remove the plugin's mappings, autocmds, extmarks, and simulated cursors without restarting Neovim:

```lua
require("vscode_style").disable()
```

Mappings installed or replaced by another plugin after `setup()` are left untouched during cleanup.
For statuslines or diagnostics, `is_enabled()` reports the core lifecycle, `is_buffer_active()` reports the effective regular/aggressive dispatch state, and `is_buffer_eligible()` explicitly refreshes the shared policy decision. `get_cursor_count()` returns the active count and `get_cursors()` returns a detached snapshot; after `disable()` these probes return empty values without recreating cursor state.

## Platform notes and limitations

- Neovim 0.9 or newer is supported; there are no external runtime dependencies.
- Modifier delivery depends on the UI. GUI clients generally distinguish these chords, while legacy terminals may collapse `Ctrl+Shift+letter` into `Ctrl+letter`. Alt mappings in terminals also depend on escape-sequence timing. A terminal with the Kitty keyboard protocol or a GUI gives the most reliable results.
- Aggressive mode does not simulate cursors inside a terminal emulator or plugin prompt. It yields those buffers to their owning UI and resumes editing when focus returns to a file buffer.
- Mouse gestures require `set mouse=a`. Whether `Shift+Alt+Drag` reaches Neovim depends on the terminal/GUI and window manager.
- Selection expansion uses word, full-line, then indentation-block heuristics. It does not claim syntax-tree parity with VS Code's language-specific smart selection.
- Printable typing, Backspace/Delete, Enter, and indentation are replicated at secondary cursors. Completion menus, snippets, register insertion, IME composition, and arbitrary third-party insert mappings may still operate only at Neovim's real cursor.
- Cursor columns are byte offsets internally, as required by Neovim's buffer API, but character movement is UTF-8-safe. Box selection converts virtual screen columns to byte columns, including tabs and wide characters where the host supports `virtcol2col()`.

## Testing

Run the headless regression suite from the repository root:

```sh
nvim --headless -u NONE -n -l tests/headless_spec.lua
```
