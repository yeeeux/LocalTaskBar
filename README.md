# LocalTaskBar

Keyboard-first task checklist for the Omarchy bar (`qs`/Quickshell plugin,
id `gordeev.tasks`). Fully local — no account, no sync, no network calls.
Storage is a plain markdown checklist compatible with the [Obsidian Tasks
plugin](https://publish.obsidian.md/tasks/) syntax, kept inside an Obsidian
vault so the same file is both this panel's backing store and a normal,
browsable note.

## Features

- Today (Overdue + Today) / Inbox / All views
- 4-tier priority (Low/Medium/High/Urgent), colored to match
- Due dates via inline shorthand while typing: `@today`, `@tomorrow`,
  `@YYYY-MM-DD`
- Priority via inline shorthand: `!1`..`!4` (Todoist numbering: 1 = Urgent)
- Full keyboard control — see `?` inside the panel for the live shortcut list
- Delete requires a second press/click to confirm (`x x` or `d d`, mixed
  works too)

## Keyboard shortcuts (summary)

| Key | Action |
|---|---|
| `↑↓` / `j k` | Move cursor |
| `Space` / `Enter` | Mark selected task done |
| `x x` / `d d` | Delete selected (second press confirms) |
| `e` | Edit selected task |
| `1 2 3 4` | Set selected task's priority (Urgent…Low) |
| `h` / `l` | Step selected task's priority by one tier |
| `L M H U` | Set priority for the *next* new task |
| `n` | Jump to the text field |
| `t i a` | Switch view: Today / Inbox / All |
| `?` | Toggle this shortcut list |

## Requirements

- Omarchy Quattro with third-party shell plugins
- An Obsidian vault at `~/Documents/obsidian-vault/Tasks/tasks.md` (path is
  hardcoded in `Panel.qml`'s `FileView`)

## Install

Already loaded in place as `~/.config/omarchy/plugins/gordeev.tasks` — enable
via `omarchy-plugin-enable gordeev.tasks` or the Omarchy plugin manager.
