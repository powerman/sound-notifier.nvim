local assert = require 'luassert'

local notify = require 'sound_notifier'

local notifier
local play_called
local play_count

before_each(function()
    -- Reset global config and focus state to defaults before each test.
    notify.setup {}
    vim.api.nvim_exec_autocmds('FocusGained', {})
    notifier = notify.new('test.wav', { delay_ms = 100, throttle_ms = 0 })
    play_called = false
    play_count = 0
    notifier._play_sound = function()
        play_called = true
        play_count = play_count + 1
    end
end)

describe('task_started/task_finished', function()
    it('should not play sound when focused', function()
        notifier:task_started()
        notifier:task_finished()

        vim.wait(150, function()
            return false
        end)
        assert.is_false(play_called)
    end)

    it('should play sound when not focused', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:task_started()
        notifier:task_finished()

        vim.wait(150, function()
            return false
        end)
        assert.is_true(play_called)
    end)

    it('should not play sound if any task is still active after task_finished', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:task_started()
        notifier:task_started()
        notifier:task_finished() -- one still running

        vim.wait(150, function()
            return false
        end)
        assert.is_false(play_called)
    end)

    it('should play sound only after all parallel tasks finish', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:task_started()
        notifier:task_started()
        notifier:task_finished()
        notifier:task_finished() -- all done

        vim.wait(150, function()
            return false
        end)
        assert.is_true(play_called)
    end)

    it('should not play sound if new task started before delay', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:task_started()
        notifier:task_finished()

        notifier:task_started()

        vim.wait(150, function()
            return false
        end)
        assert.is_false(play_called)
    end)

    it('should play sound only once on multiple task_finished calls', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:task_finished()
        notifier:task_finished()

        vim.wait(250, function()
            return false
        end)
        assert.are.equal(1, play_count)
    end)
end)

describe('notify', function()
    it('should play sound immediately when not focused', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:notify()
        assert.is_true(play_called)
    end)

    it('should not play sound immediately when focused', function()
        notifier:notify()
        assert.is_false(play_called)
    end)

    it('should call _play_sound with correct self (sound_path is used)', function()
        -- Verifies that notify() calls _play_sound via method syntax (self:_play_sound()),
        -- so _play_sound receives the correct notifier instance.
        local orig_jobstart = vim.fn.jobstart
        local captured_cmd
        vim.fn.jobstart = function(cmd, _)
            captured_cmd = cmd
        end
        notify.setup { cmd = { 'play', '-q', '%s' }, escape_fn = false }
        local n = notify.new 'specific-sound.wav'
        vim.api.nvim_exec_autocmds('FocusLost', {})
        n:notify()
        vim.fn.jobstart = orig_jobstart
        assert.are.same({ 'play', '-q', 'specific-sound.wav' }, captured_cmd)
    end)
end)

describe('notify_callback', function()
    it('should have callback for immediate notification', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        local callback = notifier:notify_callback()
        callback()
        assert.is_true(play_called)
    end)
end)

describe('task_started_callback', function()
    it('should return callback that marks task as started', function()
        local cb = notifier:task_started_callback()
        assert.are.equal(0, notifier._active_count)
        cb()
        assert.are.equal(1, notifier._active_count)
    end)
end)

describe('task_finished_callback', function()
    it('should return callback that schedules notification when not focused', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        local cb = notifier:task_finished_callback()
        cb()

        vim.wait(150, function()
            return false
        end)
        assert.is_true(play_called)
    end)
end)

describe('throttle', function()
    it('should allow repeated sounds when throttle_ms is 0', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:notify()
        notifier:notify()
        assert.are.equal(2, play_count)
    end)

    it('should default to throttle_ms of 1000', function()
        local n = notify.new 'test.wav'
        assert.are.equal(1000, n._throttle_ms)
    end)

    it('should suppress repeated sounds within throttle window', function()
        local throttled = notify.new('test.wav', { throttle_ms = 200 })
        throttled._play_sound = function()
            play_count = play_count + 1
        end
        vim.api.nvim_exec_autocmds('FocusLost', {})

        throttled:notify()
        throttled:notify()
        assert.are.equal(1, play_count)
    end)

    it('should allow sound again after throttle window expires', function()
        local throttled = notify.new('test.wav', { throttle_ms = 100 })
        throttled._play_sound = function()
            play_count = play_count + 1
        end
        vim.api.nvim_exec_autocmds('FocusLost', {})

        throttled:notify()
        vim.wait(150, function()
            return false
        end)
        throttled:notify()
        assert.are.equal(2, play_count)
    end)
end)

describe('focus', function()
    it('FocusLost event causes notify to play sound', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        notifier:notify()
        assert.is_true(play_called)
    end)

    it('FocusGained event causes notify to suppress sound', function()
        vim.api.nvim_exec_autocmds('FocusLost', {})
        vim.api.nvim_exec_autocmds('FocusGained', {})
        notifier:notify()
        assert.is_false(play_called)
    end)
end)

describe('setup', function()
    it('should error if cmd is a string instead of a list', function()
        assert.has_error(function()
            notify.setup { cmd = 'aplay -q %s' }
        end)
    end)

    it('should error if cmd is an empty list', function()
        assert.has_error(function()
            notify.setup { cmd = {} }
        end)
    end)

    it('should error if cmd first element is an empty string', function()
        assert.has_error(function()
            notify.setup { cmd = { '' } }
        end)
    end)
end)

describe('_play_sound', function()
    local orig_jobstart
    local captured_cmd

    before_each(function()
        orig_jobstart = vim.fn.jobstart
        vim.fn.jobstart = function(cmd, _)
            captured_cmd = cmd
        end
    end)

    after_each(function()
        vim.fn.jobstart = orig_jobstart
        captured_cmd = nil
    end)

    -- Helper: configure cmd and escape_fn, create notifier, call _play_sound.
    local function play(cmd, escape_fn, sound_path)
        notify.setup { cmd = cmd, escape_fn = escape_fn }
        notify.new(sound_path):_play_sound()
        return captured_cmd
    end

    -- Standalone '%s': path is passed as a separate process argument, no escaping needed.

    it('standalone %s: passes path as-is (no escape_fn)', function()
        assert.are.same(
            { 'play', '-q', '/my sounds/alert.wav' },
            play({ 'play', '-q', '%s' }, false, '/my sounds/alert.wav')
        )
    end)

    it('standalone %s: passes path as-is even when escape_fn is set', function()
        -- For standalone '%s', the original path is always passed as a separate process argument.
        -- escape_fn output is only used for embedded '%s' substitution via gsub.
        assert.are.same(
            { 'play', '-q', "it's fine.wav" },
            play({ 'play', '-q', '%s' }, function(p)
                return p:gsub("'", "''")
            end, "it's fine.wav")
        )
    end)

    it('standalone %s: path with % characters is not mangled', function()
        assert.are.same(
            { 'play', '-q', 'file%20name%.wav' },
            play({ 'play', '-q', '%s' }, false, 'file%20name%.wav')
        )
    end)

    -- Embedded '%s': path is substituted inside a string argument via gsub.

    it('embedded %s: substitutes path into argument string (no escape_fn)', function()
        assert.are.same(
            { 'sh', '-c', 'play /my sounds/alert.wav' },
            play({ 'sh', '-c', 'play %s' }, false, '/my sounds/alert.wav')
        )
    end)

    it('embedded %s: applies escape_fn before substitution', function()
        -- PowerShell single-quoted string: ' must be doubled.
        assert.are.same(
            {
                'powershell',
                '-c',
                "(New-Object Media.SoundPlayer 'C:\\My ''Music''\\alert.wav').PlaySync()",
            },
            play(
                { 'powershell', '-c', "(New-Object Media.SoundPlayer '%s').PlaySync()" },
                function(p)
                    return p:gsub("'", "''")
                end,
                "C:\\My 'Music'\\alert.wav"
            )
        )
    end)

    it('embedded %s: path with % characters is not mangled by gsub replacement', function()
        assert.are.same(
            { 'sh', '-c', 'play path%20with%percent.wav' },
            play({ 'sh', '-c', 'play %s' }, false, 'path%20with%percent.wav')
        )
    end)

    it(
        'embedded %s: escape_fn result with % characters is not mangled by gsub replacement',
        function()
            -- escape_fn returns a string that itself contains '%'; gsub must not misinterpret it.
            assert.are.same(
                { 'sh', '-c', 'play %20file.wav' },
                play({ 'sh', '-c', 'play %s' }, function(p)
                    return '%20' .. p
                end, 'file.wav')
            )
        end
    )

    -- No '%s' in argument: argument is passed through unchanged.

    it('no %s in argument: argument is not modified', function()
        assert.are.same(
            { 'sh', '-c', 'echo hello' },
            play({ 'sh', '-c', 'echo hello' }, false, 'irrelevant.wav')
        )
    end)
end)
