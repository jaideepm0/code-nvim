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
You can override basics and mapping behavior:

| Option | Default | Purpose |
| --- | --- | --- |
| `selection_hl` | `"Visual"` | Highlight used for simulated selections in insert mode. |
| `max_cursors` | `32` | Upper bound on simultaneously tracked carets. |
| `mappings.strategy` | `"respect"` | How to set keymaps: `"respect"` (only if unmapped), `"force"` (override), `"skip"` (no maps). |
| `mappings.selection` | `true` | Enable Shift/Ctrl+Shift selection motions. |
| `mappings.line_ops` | `true` | Enable Alt+Up/Down move and Shift+Alt+Up/Down copy, Ctrl+Shift+K delete line. |
| `mappings.multi_cursor` | `true` | Enable Alt+Click, Ctrl+Alt+Up/Down, Ctrl+D, Ctrl+Shift+L, expand/shrink. |
| `mappings.column_selection` | `true` | Enable Shift+Alt mouse drag/release for box selection. |
| `mappings.tab` | `true` | Intercept Tab/Shift+Tab to indent/dedent active selections. |
| `mappings.backspace` | `true` | Intercept Backspace to delete active selections. |

Example:

```lua
require("vscode_style").setup({
  selection_hl = "Search",
  max_cursors = 16,
  mappings = {
    strategy = "respect", -- or "force"/"skip"
    selection = true,
    line_ops = true,
    multi_cursor = true,
    column_selection = true,
    tab = true,
    backspace = true,
  },
})
```

## Notes
- Designed for Neovim 0.9 or newer; no external dependencies.
- Behaves best with `set mouse=a` if you plan to use Shift+Alt drags for wider selections.
- Normal mode remains untouched—hit `<Esc>` whenever you want native motions back.
