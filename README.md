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
  },
  notify = vim.notify, -- a function, or false
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

Individual keymap overrides accept `false`, a replacement `lhs` string/list, or a table containing `enabled`, `lhs`, `opts`, `desc`, `callback`, `action`, and `args`. Use `require("vscode_style.config").keymap_definitions()` to inspect the supported names.

To remove the plugin's mappings, autocmds, extmarks, and simulated cursors without restarting Neovim:

```lua
require("vscode_style").disable()
```

Mappings installed or replaced by another plugin after `setup()` are left untouched during cleanup.
For statuslines or diagnostics, `get_cursor_count()` returns the active count and `get_cursors()` returns a detached snapshot of the per-buffer cursor state.

## Platform notes and limitations

- Neovim 0.9 or newer is supported; there are no external runtime dependencies.
- Modifier delivery depends on the UI. GUI clients generally distinguish these chords, while legacy terminals may collapse `Ctrl+Shift+letter` into `Ctrl+letter`. Alt mappings in terminals also depend on escape-sequence timing. A terminal with the Kitty keyboard protocol or a GUI gives the most reliable results.
- Mouse gestures require `set mouse=a`. Whether `Shift+Alt+Drag` reaches Neovim depends on the terminal/GUI and window manager.
- Selection expansion uses word, full-line, then indentation-block heuristics. It does not claim syntax-tree parity with VS Code's language-specific smart selection.
- Printable typing, Backspace/Delete, Enter, and indentation are replicated at secondary cursors. Completion menus, snippets, register insertion, IME composition, and arbitrary third-party insert mappings may still operate only at Neovim's real cursor.
- Cursor columns are byte offsets internally, as required by Neovim's buffer API, but character movement is UTF-8-safe. Box selection converts virtual screen columns to byte columns, including tabs and wide characters where the host supports `virtcol2col()`.

## Testing

Run the headless regression suite from the repository root:

```sh
nvim --headless -u NONE -n -l tests/headless_spec.lua
```
