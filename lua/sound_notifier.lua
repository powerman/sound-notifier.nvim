---@class SoundNotifierConfig
---@field cmd? string[] Command to play sound; each element is a separate argument, use '%s' as placeholder for the sound file path
---@field escape_fn? fun(path: string): string|false Function to escape the sound file path before substituting '%s'; pass false to disable the default

---@class _SoundNotifierConfig
---@field cmd string[]
---@field escape_fn? fun(path: string): string

---@class SoundNotifierOpts
---@field delay_ms? number Delay in milliseconds before playing sound after task finishes (default: 3000)
---@field throttle_ms? number Minimum interval in milliseconds between sounds (default: 1000)

---@class SoundNotifier
---@field _active_count number Number of tasks currently in progress
---@field _last_finished number
---@field _last_played number
---@field _delay_ms number
---@field _throttle_ms number
---@field _sound_path string

local M = {}

-- Escapes a path for use inside a PowerShell single-quoted string literal.
-- Single quotes are the only character that needs escaping in that context;
-- they are escaped by doubling: ' -> ''.
local function escape_powershell_sq(path)
    return path:gsub("'", "''")
end

-- Default commands per OS; '%s' is replaced with the sound file path at play time.
local default_cmd_by_os = {
    Linux = { 'play', '-q', '%s' },
    Darwin = { 'afplay', '%s' },
    Windows_NT = { 'powershell', '-c', "(New-Object Media.SoundPlayer '%s').PlaySync()" },
}

local default_escape_fn_by_os = {
    Windows_NT = escape_powershell_sq,
}

local os_name = vim.uv.os_uname().sysname

-- Neovim has a single focus state shared across all notifiers.
-- True by default so that no sound plays before setup() registers the autocmds.
local is_focused = true

---@type _SoundNotifierConfig
local config = {
    cmd = default_cmd_by_os[os_name] or { 'play', '-q', '%s' },
    escape_fn = default_escape_fn_by_os[os_name],
}

---Configures global plugin settings.
---Call this once during plugin setup, before creating any notifier instances.
---Emits a warning via vim.notify if the player executable is not found in PATH.
---@param opts SoundNotifierConfig
function M.setup(opts)
    opts = opts or {}
    if opts.cmd ~= nil then
        if type(opts.cmd) ~= 'table' then
            error('[SoundNotifier] opts.cmd must be a string[]', 2)
        end
        if #opts.cmd == 0 or opts.cmd[1] == '' then
            error('[SoundNotifier] opts.cmd must contain a command', 2)
        end
        config.cmd = opts.cmd
    end
    -- Explicit false clears the escape function; nil keeps the current default.
    if opts.escape_fn ~= nil then
        config.escape_fn = opts.escape_fn or nil
    end
    if vim.fn.executable(config.cmd[1]) == 0 then
        vim.notify(
            "[SoundNotifier] executable '" .. config.cmd[1] .. "' not found in PATH",
            vim.log.levels.WARN
        )
    end

    local focus_augroup = vim.api.nvim_create_augroup('SoundNotifier_focus', { clear = true })
    vim.api.nvim_create_autocmd('FocusGained', {
        group = focus_augroup,
        callback = function()
            is_focused = true
        end,
    })
    vim.api.nvim_create_autocmd('FocusLost', {
        group = focus_augroup,
        callback = function()
            is_focused = false
        end,
    })
end

---Creates new sound notifier.
---@param sound_path string Path to sound file
---@param opts? SoundNotifierOpts
---@return SoundNotifier
function M.new(sound_path, opts)
    opts = opts or {}
    local self = setmetatable({}, { __index = M })
    self._active_count = 0
    self._last_finished = 0
    self._last_played = 0
    self._delay_ms = opts.delay_ms or 3000
    self._throttle_ms = opts.throttle_ms or 1000
    self._sound_path = sound_path
    return self
end

function M:_play_sound()
    local path = self._sound_path
    local path_safe = config.escape_fn and config.escape_fn(path) or path
    -- gsub replacement uses '%' as a special prefix, so literal '%' in the path must be escaped.
    local path_repl = path_safe:gsub('%%', '%%%%')
    local cmd = {}
    for _, part in ipairs(config.cmd) do
        -- Standalone '%s' is passed as a separate process argument without escaping.
        -- Embedded '%s' inside a string argument uses the escaped path via gsub.
        cmd[#cmd + 1] = part == '%s' and path or part:gsub('%%s', path_repl)
    end
    vim.fn.jobstart(cmd, { detach = true })
end

---Plays sound immediately if window is not focused.
---Respects throttle_ms: skips if a sound was played too recently.
function M:notify()
    if is_focused then
        return
    end
    if self._throttle_ms > 0 then
        local elapsed = vim.uv.now() - self._last_played
        if elapsed < self._throttle_ms then
            return
        end
    end
    self._last_played = vim.uv.now()
    self:_play_sound()
end

---Mark a task as started.
---Prevents deferred notification until a matching task_finished is called.
---Multiple concurrent tasks are supported: each call must be paired with task_finished.
function M:task_started()
    self._active_count = self._active_count + 1
end

---Mark a task as finished.
---When all concurrent tasks are done, schedules a notification after delay_ms.
function M:task_finished()
    if self._active_count > 0 then
        self._active_count = self._active_count - 1
    end
    self._last_finished = vim.uv.now()

    vim.defer_fn(function()
        local elapsed = vim.uv.now() - self._last_finished
        if self._active_count == 0 and elapsed >= self._delay_ms then
            self:notify()
        end
    end, self._delay_ms)
end

---Returns callback function that plays sound immediately.
---@return function
function M:notify_callback()
    return function()
        self:notify()
    end
end

---Returns callback function that marks task as started.
---@return function
function M:task_started_callback()
    return function()
        self:task_started()
    end
end

---Returns callback function that marks task as finished.
---@return function
function M:task_finished_callback()
    return function()
        self:task_finished()
    end
end

return M
