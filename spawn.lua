---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop

local function safe_close(handle)
  if not uv.is_closing(handle) then
    uv.close(handle)
  end
end

local function on_failed(msg)
  vim.schedule(function()
    vim.notify('[Guard] ' .. msg, vim.log.levels.ERROR)
  end)
end

--TODO: replace by vim.system when neovim 0.10 released
local function spawn(opt)
  assert(opt, 'missing opt param')
  local co = assert(coroutine.running())

  local chunks = {}
  local num_stderr_chunks = 0
  local stdin = opt.lines and assert(uv.new_pipe()) or nil
  local stdout = assert(uv.new_pipe())
  local stderr = assert(uv.new_pipe())
  local handle

  local timeout
  local killed = false
  if opt.timeout then
    timeout = assert(uv.new_timer())
    timeout:start(opt.timeout, 0, function()
      safe_close(handle)
      killed = true
    end)
  end

  handle = uv.spawn(opt.cmd, {
    stdio = { stdin, stdout, stderr },
    args = opt.args,
    cwd = opt.cwd,
    env = opt.env,
  }, function(exit_code, signal)
    if timeout then
      timeout:stop()
      timeout:close()
    end
    safe_close(handle)
    safe_close(stdout)
    safe_close(stderr)
    local check = assert(uv.new_check())
    check:start(function()
      if not stdout:is_closing() or not stderr:is_closing() then
        return
      end
      check:stop()
      if killed then
        on_failed(
          ('process %s was killed because it reached the timeout signal %s code %s'):format(
            opt.cmd,
            signal,
            exit_code
          )
        )
        coroutine.resume(co)
        return
      end
    end)

    if exit_code ~= 0 and num_stderr_chunks ~= 0 then
      on_failed(('process %s exited with non-zero exit code %s'):format(opt.cmd, exit_code))
      coroutine.resume(co)
      return
    else
      coroutine.resume(co, table.concat(chunks))
    end
  end)

  if not handle then
    on_failed('failed to spawn process ' .. opt.cmd)
    return
  end

  if stdin then
    stdin:write(opt.lines)
    uv.shutdown(stdin, function()
      safe_close(stdin)
    end)
  end

  stdout:read_start(function(err, data)
    assert(not err, err)
    if data then
      chunks[#chunks + 1] = data
    end
  end)

  stderr:read_start(function(err, data)
    assert(not err, err)
    if data then
      num_stderr_chunks = num_stderr_chunks + 1
    end
  end)

  return (coroutine.yield())
end

local function try_spawn(opt)
  local ok, out = pcall(spawn, opt)
  if not ok then
    on_failed('error: ' .. out)
    return
  end
  return out
end

return {
  try_spawn = try_spawn,
}
