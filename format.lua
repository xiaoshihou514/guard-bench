local api = vim.api
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local spawn = require("spawn").try_spawn
local util = require("util")
local get_prev_lines = util.get_prev_lines

local function save_views(bufnr)
    local views = {}
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
    end
    return views
end

local function restore_views(views)
    for win, view in pairs(views) do
        api.nvim_win_call(win, function()
            vim.fn.winrestview(view)
        end)
    end
end

local function update_buffer(bufnr, prev_lines, new_lines, srow)
    if not new_lines or #new_lines == 0 then
        return
    end
    local views = save_views(bufnr)
    new_lines = vim.split(new_lines, "\n")
    if new_lines[#new_lines] == "" then
        new_lines[#new_lines] = nil
    end
    local diffs = vim.diff(table.concat(new_lines, "\n"), prev_lines, {
        algorithm = "minimal",
        ctxlen = 0,
        result_type = "indices",
    })
    if not diffs or #diffs == 0 then
        return
    end

    -- Apply diffs in reverse order.
    for i = #diffs, 1, -1 do
        local new_start, new_count, prev_start, prev_count = unpack(diffs[i])
        local replacement = {}
        for j = new_start, new_start + new_count - 1, 1 do
            replacement[#replacement + 1] = new_lines[j]
        end
        local s, e
        if prev_count == 0 then
            s = prev_start
            e = s
        else
            s = prev_start - 1 + srow
            e = s + prev_count
        end
        api.nvim_buf_set_lines(bufnr, s, e, false, replacement)
    end
    local mode = api.nvim_get_mode().mode
    if mode == "v" or "V" then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
    end
    restore_views(views)
end

local function update_buffer_without_diff(bufnr, prev_lines, new_lines)
    if not new_lines or #new_lines == 0 then
        return
    end
    local views = save_views(bufnr)
    new_lines = vim.split(new_lines, "\n")
    if new_lines[#new_lines] == "" then
        new_lines[#new_lines] = nil
    end

    if #new_lines ~= #prev_lines then
        api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
        restore_views(views)
        return
    end
end

local function do_fmt(buf, config)
    buf = buf or api.nvim_get_current_buf()
    local srow = 0
    local erow = -1
    local range
    local mode = api.nvim_get_mode().mode
    if mode == "V" or mode == "v" then
        range = util.range_from_selection(buf, mode)
        srow = range.start[1] - 1
        erow = range["end"][1]
    end
    local fname = vim.fn.fnameescape(api.nvim_buf_get_name(buf))
    local root_dir = util.get_lsp_root()
    local cwd = root_dir or uv.cwd()
    local prev_lines = table.concat(get_prev_lines(buf, srow, erow), "")

    coroutine.resume(coroutine.create(function()
        local new_lines
        local changedtick = api.nvim_buf_get_changedtick(buf)
        local reload = nil

        config.lines = new_lines and new_lines or prev_lines
        config.args = config.args or {}
        config.args[#config.args + 1] = config.fname and fname or nil
        config.cwd = cwd
        reload = (not reload and config.stdout == false) and true or false
        new_lines = spawn(config)
        --restore
        config.lines = nil
        config.cwd = nil
        if config.fname then
            config.args[#config.args] = nil
        end
        changedtick = vim.b[buf].changedtick

        vim.schedule(function()
            if not api.nvim_buf_is_valid(buf) or changedtick ~= api.nvim_buf_get_changedtick(buf) then
                return
            end
            local start = vim.uv.hrtime()
            -- update_buffer(buf, prev_lines, new_lines, srow)
            update_buffer_without_diff(buf, prev_lines, new_lines)
            if reload and api.nvim_get_current_buf() == buf then
                vim.cmd.edit()
            end
            vim.print((vim.uv.hrtime() - start) / 1000000)
        end)
    end))
end

return do_fmt
