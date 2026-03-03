# sound-notifier.nvim

[![License MIT](https://img.shields.io/badge/license-MIT-royalblue.svg)](LICENSE)
[![Neovim 0.10+](https://img.shields.io/badge/Neovim-0.10%2B-royalblue?logo=neovim&logoColor=white)](https://neovim.io/)
[![Lua 5.1](https://img.shields.io/badge/Lua-5.1-blue)](https://www.lua.org/)
[![Test](https://img.shields.io/github/actions/workflow/status/powerman/{REPO}/test.yml?label=test)](https://github.com/powerman/{REPO}/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/powerman/{REPO}?color=blue)](https://github.com/powerman/{REPO}/releases/latest)

## About

Neovim plugin to play sound notifications when Neovim is not focused.

Useful when running long background tasks (LLM responses, builds, tests):
you switch away from Neovim while waiting,
and get an audio cue when something requires your attention.

## Features

- Plays a sound file when Neovim loses focus and an event occurs.
- Immediate notification via `notify()` — for one-shot events.
- Deferred notification via `task_started()` / `task_finished()` —
  plays sound only after a group of tasks finishes and a configurable quiet period elapses,
  confirming that no new tasks in the group have started in the meantime.
- Throttling — suppresses repeated sounds within a configurable time window (default: 1 second).
- Returns ready-made callbacks (`notify_callback()`, `task_started_callback()`,
  `task_finished_callback()`) for direct use in autocommands and other hooks.
- OS-aware default player command (Linux: `play`, macOS: `afplay`, Windows: PowerShell).
- Configurable player command via `setup()`.
- Warns via `setup()` if the player executable is not found in PATH.
- Multiple independent notifier instances can coexist.

## Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
    'powerman/sound-notifier.nvim',
    opts = {}, -- ensures setup() is called
}
```

### External dependencies

The plugin uses a command-line audio player to play sound files.
The default player depends on your OS:

| OS      | Default command        | How to install              |
| ------- | ---------------------- | --------------------------- |
| Linux   | `play -q <file>`       | `sudo apt install sox`      |
| macOS   | `afplay <file>`        | built-in, no install needed |
| Windows | PowerShell SoundPlayer | built-in, no install needed |

On Linux you can also use `aplay` (part of `alsa-utils`) — see [Setup](#setup).

## Setup

You must call `setup()` to use the plugin.

For most users no configuration is needed —
the plugin picks the right player for your OS automatically.

## Configuration

### `setup(opts)`

Configures global plugin settings.
Must be called before creating any notifier instances.
Emits a `WARN` notification if the player executable is not found in PATH.

**`cmd`** `string[]`

> Command to play sound.
> Each element is a separate argument.
> `%s` is replaced with the sound file path at play time.
>
> Defaults (OS-dependent):
>
> - Linux: `{'play', '-q', '%s'}`
> - macOS: `{'afplay', '%s'}`
> - Windows: `{'powershell', '-c', "(New-Object Media.SoundPlayer '%s').PlaySync()"}`

**`escape_fn`** `fun(path: string): string | false`

> Applied to `sound_path` before substituting `%s` inside embedded string arguments.
> Pass `false` to disable the OS default.
>
> Defaults (OS-dependent):
>
> - Linux: `nil` (no escaping)
> - macOS: `nil` (no escaping)
> - Windows: escapes `'` → `''` for PowerShell single-quoted strings

> **Note on path escaping:**
> The default Windows command embeds `'%s'` inside a PowerShell single-quoted string literal.
> Single quotes inside such a literal must be doubled (`'` → `''`),
> which the built-in `escape_fn` handles automatically.
> If you provide a custom `cmd` that also embeds the path inside a shell string,
> you must supply a matching `escape_fn`.
> For `cmd` where `%s` is a standalone element (Linux/macOS defaults),
> no escaping is needed — the path is passed as a separate process argument.

## Usage

### `new(sound_path, opts)`

Creates a new notifier instance.

| Parameter          | Type     | Default | Description                                                                          |
| ------------------ | -------- | ------- | ------------------------------------------------------------------------------------ |
| `sound_path`       | `string` | —       | Path to the sound file to play                                                       |
| `opts.delay_ms`    | `number` | `3000`  | Delay in milliseconds before playing sound after task finishes                       |
| `opts.throttle_ms` | `number` | `1000`  | Minimum interval in milliseconds between consecutive sounds; `0` disables throttling |

#### Notifier methods

| Method                     | Description                                                                  |
| -------------------------- | ---------------------------------------------------------------------------- |
| `notify()`                 | Play sound immediately if Neovim is not focused (respects `throttle_ms`)     |
| `task_started()`           | Increment the active task counter (suppresses deferred notification)         |
| `task_finished()`          | Decrement the counter; schedules sound after `delay_ms` when it reaches zero |
| `notify_callback()`        | Returns a zero-argument function that calls `notify()`                       |
| `task_started_callback()`  | Returns a zero-argument function that calls `task_started()`                 |
| `task_finished_callback()` | Returns a zero-argument function that calls `task_finished()`                |

## Examples

### Immediate notification on an autocommand event

Play a sound when an event fires (e.g. an LLM response arrives):

```lua
local notifier = require('sound_notifier').new '/path/to/sound.wav'

vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup('user.notify', { clear = true }),
    pattern = {
        'CodeCompanionChatDone',
        'CodeCompanionInlineFinished',
        'CodeCompanionToolApprovalRequested',
    },
    callback = notifier:notify_callback(),
})
```

### Deferred notification around a long-running group of tasks

Use this when multiple tasks may run sequentially or in parallel
and you want a single notification only after all of them finish.
The sound is suppressed while any task is active,
and played only after the last task finishes
and a quiet period elapses with no new tasks starting.
This avoids spurious sounds when you are actively watching the output.

```lua
local notifier =
    require('sound_notifier').new('/usr/share/sounds/notify.wav', { delay_ms = 5000 })
local augroup = vim.api.nvim_create_augroup('user.notify_tasks', { clear = true })

vim.api.nvim_create_autocmd('User', {
    group = augroup,
    pattern = 'CodeCompanionToolStarted',
    callback = notifier:task_started_callback(),
})

vim.api.nvim_create_autocmd('User', {
    group = augroup,
    pattern = 'CodeCompanionToolFinished',
    callback = notifier:task_finished_callback(),
})
```

### Multiple notifiers

You can create independent notifiers for different plugins or sound files:

```lua
local sn = require 'sound_notifier'

local cc_notifier = sn.new '/sounds/ping.wav'
local llm_notifier = sn.new('/sounds/chime.wav', { delay_ms = 5000, throttle_ms = 10000 })
```

Each notifier manages its own task state and throttle window independently.

### Custom player command

If you want to use a different player:

```lua
return {
    'powerman/sound-notifier.nvim',
    opts = {
        -- '%s' is replaced with the sound file path at play time.
        cmd = { 'aplay', '-q', '%s' },
    },
}
```
