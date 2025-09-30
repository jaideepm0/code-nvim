# VSCode Style Insert Editing for Neovim

`code-nvim` keeps you in insert mode while borrowing a handful of Visual Studio Code’s core text-editing shortcuts. Hold familiar `Shift`, `Ctrl`, and `Alt` combinations to extend selections, jump to boundaries, and shuffle lines without leaving the flow of typing.

## Basic Capabilities
- Extend selections with `Shift` + arrow keys, or jump straight to line/file boundaries with `Shift+Home/End` and `Ctrl+Shift+Home/End`.
- Reshape selections word-by-word using `Ctrl+Shift+Left/Right` and clear them instantly when you leave insert mode.
- Use `Alt+Up/Down` to move the active lines and `Shift+Alt+Up/Down` to duplicate them in place.
- Press `Tab`/`Shift+Tab` to indent or dedent just the highlighted span, and overwrite any selection simply by typing.
- Press `Backspace` to delete whatever you have highlighted without needing to leave insert mode.

## Installation
Add the plugin to your preferred manager. With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jaideepm0/code-nvim",
  config = function()
    require("vscode_style").setup({
      -- selection_hl = "Visual",
      -- max_cursors = 32,
    })
  end,
}
```

For a manual setup, add the repository to `runtimepath` and call:

```lua
require("vscode_style").setup()
```

Call `setup()` explicitly. This plugin is intentionally non‑opinionated and does not auto‑enable itself; you decide where and when to map keys and which features to enable.

## Configuration
`setup()` with no arguments keeps the built-in defaults and only maps shortcuts that are currently unmapped in insert mode. Drop in a table when you need tweaks:

- `selection_hl` (string\|false) – highlight group for simulated selections; set to `false` to turn highlights off.
- `max_cursors` (number) – maximum simultaneous cursors (default `32`).
- `mapping_strategy` (`"respect"`\|`"force"`\|`"skip"`) – whether to reuse your bindings, override them, or install nothing.
- `feature_flags` / `mappings` – enable/disable whole shortcut groups (`selection`, `line_ops`, `multi_cursor`, `column_selection`, `tab`, `backspace`).
- `autocommands` – opt in/out of helper autocmds (`insert_char_pre`, `insert_leave`, `insert_enter`, `buf_enter`, `buf_cleanup`).
- `notify` – custom notification function or `false` to stay quiet.
- `debug` – enabled by default right now; expect verbose backspace traces in `:messages`. Provide `{ log = function(msg) ... end }` to redirect or set `debug = { enabled = false }` once you’re done investigating.
- `keymaps` – override individual shortcuts (change `lhs`, tweak `opts`/`desc`, disable with `false`, or supply your own `callback`).

Example customisation:

```lua
require("vscode_style").setup({
  selection_hl = "Search",
  max_cursors = 16,
  mapping_strategy = "respect", -- use "force" to override or "skip" to install nothing
  feature_flags = {
    tab = false, -- keep native Tab behaviour
    backspace = true,
  },
  autocommands = {
    insert_enter = false, -- opt out of snapshot restore on InsertEnter
  },
  notify = false, -- run quietly
  keymaps = {
    move_line_up = { lhs = "<A-k>", desc = "Move line up like VS Code" },
    backspace_ctrl_h = false, -- disable the Ctrl+h alias
    add_selection_next = {
      lhs = { "<C-d>", "<Leader>d" },
    },
  },
})
```

## Notes
- Designed for Neovim 0.9 or newer; no external dependencies.
- Behaves best with `set mouse=a` if you plan to use Shift+Alt drags for wider selections.
- Default mappings are added only when free; use `mapping_strategy = "force"` to override (previous bindings are restored if you disable the plugin later).
- Normal mode remains untouched—hit `<Esc>` whenever you want native motions back.
