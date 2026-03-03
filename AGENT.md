# General rules for the project

## Project Context (Reference)

Project "sound-notifier.nvim" - Neovim plugin to play sound notifications
when Neovim is not focused.

- Minimum Neovim version: 0.10.
- Lua dialect: Lua 5.1. Use `vim.*` APIs, not `io.*` or `os.*`.

### Structure

- `.cache/` — Git-ignored directory for temporary files.
- `mise.toml`, `mise.lock` — Project tasks and tools managed by Mise.
- `.stylua.toml` — Lua formatter config.
- `selene.toml`, `vim.yml` — Lua linter config.
  `vim.yml` declares runtime globals for selene
  (e.g. `vim`, `assert`, busted-style test functions).
  Uses `std = "vim"` in `selene.toml` and `base: lua51` in `vim.yml`,
  so globals defined in `vim.yml` take priority over the Lua 5.1 standard definitions —
  which allows overriding built-ins like `assert`.
- `tests/run.lua` — Test entry point.
- `tests/lazy_bootstrap.lua`, `tests/.config/nvim/lazy-lock.json` — Ensures test dependencies.
- `tests/test_*.lua` — Tests using busted-style `describe`/`it` via `mini.test`
  with `luassert` for assertions.
- `lua/` — Plugin source.

### Tasks

Use these commands for corresponding tasks:

- `mise run lint` — run all linters.
- `mise run fmt` — fix formatting issues reported by linters.
- `mise run test` — run all tests.
- `mise run generate` — generate panvimdoc documentation from `README.md`.

---

## Mandatory Rules

### Repository Safety

- DO NOT create, amend, squash, rebase, or otherwise modify commits.
- DO NOT switch branches.
- DO NOT perform any network git operations inside this repository
  (e.g. `git push`, `git pull`, `git fetch`).
- You MAY use `git stash` if necessary, but clean up after yourself.
- You MAY use `git restore` for reverting local changes.
- Do not delete, rewrite, or mass-modify files outside the explicit scope of the task.
- Avoid destructive shell commands (e.g. `rm -rf`, recursive operations)
  unless explicitly required.
- DO NOT edit `lazy-lock.json` manually.
  Use `mise run deps:tests:update` to update test dependencies and regenerate the lockfile.

### Compatibility Requirements

- Support Neovim latest and previous versions (`mise run test` executes tests on both).
- Do NOT use LuaJIT-specific features (`goto`, `ffi`, `jit.*`, `bit.*`) —
  the plugin must work on Neovim builds without LuaJIT.

### Test Infrastructure

Test files use busted-compatible style provided by `mini.test` (`emulate_busted = true`).
The following globals are available without import:
`describe`, `it`, `before_each`, `after_each`, `setup`, `teardown`.

`luassert` is loaded as a global `assert` by `lazy.minit`.
Declare it explicitly at the top of each test file to satisfy selene and get LSP support:

```lua
local assert = require 'luassert'
```

### Coding Standards

#### Semantic Linefeeds (comments and documentation only)

Start each sentence on a new line.
Break long sentences at natural pauses —
after commas, semicolons, conjunctions,
or between logical clauses.
Do NOT hard-wrap to a fixed column width.
The goal is meaningful diffs:
one changed idea = one changed line.

```lua
--- Checks if a buffer is valid and listed.
--- Returns false for scratch buffers,
--- because they should not appear in the buffer list.
---
--- If the buffer has been modified,
--- the caller must decide whether to save or discard changes
--- before removing it from the list.
```

#### Documentation (markdown)

- Write new documentation in English.
- Avoid adding new documentation unless specifically requested by user.
- Update existing documentation together with code changes
  ONLY if otherwise existing documentation became incorrect.
- Keep lines within 96 characters.

#### Commenting

- Write new comments in English.
- Do not add redundant comments that restate obvious code behavior.
- Explain rationale, intent, trade-offs, and non-obvious behavior.
- Use full sentences in comments and documentation.
- Keep lines within 96 characters.

#### Formatting and Style

- Lua style is defined in `.stylua.toml`.
- Always run `mise run fmt` to fix formatting.
- Lua comments:
  - `--` for inline comments.
  - `---` for docstrings.

#### Naming

- Lua module names must use snake_case (`module_name.lua`).
- Lua type names must use a PascalCase prefix (`ModuleName`).
- Neovim augroup, highlight, and user command names must use a PascalCase prefix (`ModuleName`).
- Error messages and notifications must use a PascalCase prefix in square brackets (`[ModuleName]`).

### Do Not

- Do not add `vim.cmd` calls where a Lua API exists.
- Do not use `vim.fn` for things available in `vim.api` or `vim.*`.
- Do not add autocommands outside of `augroup` (use `vim.api.nvim_create_augroup`).

---

## Recommended Practices

Apply these unless the task explicitly requires otherwise.

### Testing

Use `luassert` assertions: `assert.is_true`, `assert.is_false`, `assert.are.same`, etc.

For **unit tests** (pure logic, no Neovim integration) — use the plain busted style:

```lua
describe('my module', function()
    it('does the thing', function()
        assert.is_true(result)
    end)
end)
```

For **integration tests** (autocommands, keymaps, UI behaviour) — use `new_child_neovim()`
from `mini.test` to run a real Neovim subprocess.
This keeps integration concerns isolated from unit tests:

```lua
local assert = require 'luassert'

local child = require('mini.test').new_child_neovim()
teardown(child.stop)

before_each(function()
    child.restart { '--cmd', 'set rtp+=.' }
end)

describe('my feature', function()
    it('sets up autocmd on setup', function()
        child.lua [[ require('my-plugin').setup {} ]]
        assert.is_true(child.lua_get [[ vim.tbl_count(vim.api.nvim_get_autocmds({})) > 0 ]])
    end)
end)
```

- Prefer table-driven specs for combinatorial cases.
- Stub Neovim APIs carefully: reassign functions and restore them in `after_each` hooks.

### Tool / Shell Discipline

- Store temporary scripts in `.cache/`
  unless the language requires another location.
- Remove temporary scripts after use,
  unless the user is expected to run them manually.
- Avoid creating persistent artifacts unless required by the task.
- Prefer existing project tooling (`mise`, linters, test runner)
  over ad-hoc commands.

---

## Common Gotchas

### Documentation

- Avoid touching generated docs directly — run `mise run generate` instead.

### Neovim API

- `vim.keymap.set` — always provide `desc` in opts for which-key discoverability.
