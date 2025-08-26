local M = {}

-- Get WebSocket URL from Chrome DevTools API
function M.get_websocket_url(debug_port, callback)
  local url = "http://localhost:" .. debug_port .. "/json"

  -- Use curl to get the JSON data
  local cmd = { "curl", "-s", url }

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 or data[1] == "" then
        callback(nil)
        return
      end

      local json_str = table.concat(data, "\n")
      local success, json_data = pcall(vim.json.decode, json_str)

      if not success or not json_data or #json_data == 0 then
        vim.notify("DevCon: Failed to parse DevTools JSON response", vim.log.levels.ERROR)
        callback(nil)
        return
      end

      -- Find the first page/tab with webSocketDebuggerUrl
      for _, tab in ipairs(json_data) do
        if tab.webSocketDebuggerUrl and tab.type == "page" then
          callback(tab.webSocketDebuggerUrl)
          return
        end
      end

      vim.notify("DevCon: No debuggable page found", vim.log.levels.ERROR)
      callback(nil)
    end,
    on_stderr = function(_, data)
      if data and data[1] ~= "" then
        vim.notify("DevCon: Error getting WebSocket URL: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
      end
      callback(nil)
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("DevCon: curl command failed with code " .. code, vim.log.levels.ERROR)
        callback(nil)
      end
    end,
  })
end

-- WebSocket connection using wscat or websocat (external tools)
function M.connect(ws_url, callbacks)
  -- Check if wscat or websocat is available
  local ws_tool = nil
  if vim.fn.executable "websocat" == 1 then
    ws_tool = "websocat"
  elseif vim.fn.executable "wscat" == 1 then
    ws_tool = "wscat"
  else
    vim.notify("DevCon: WebSocket tool not found. Please install 'websocat' or 'wscat'", vim.log.levels.ERROR)
    return nil
  end

  local cmd
  if ws_tool == "websocat" then
    cmd = { "websocat", "-n", ws_url }
  else -- wscat
    cmd = { "wscat", "-c", ws_url }
  end

  local websocket = {
    job_id = nil,
    url = ws_url,
    tool = ws_tool,
    callbacks = callbacks or {},
    message_id = 1,
  }

  websocket.job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data and data[1] ~= "" then
        for _, line in ipairs(data) do
          if line and line ~= "" then
            M.handle_message(websocket, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data and data[1] ~= "" and websocket.callbacks.on_error then
        websocket.callbacks.on_error(table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, code)
      if websocket.callbacks.on_close then
        websocket.callbacks.on_close(code)
      end
    end,
  })

  if websocket.job_id <= 0 then
    vim.notify("DevCon: Failed to start WebSocket connection", vim.log.levels.ERROR)
    return nil
  end

  return websocket
end

-- Handle incoming WebSocket messages
function M.handle_message(websocket, message_str)
  local success, message = pcall(vim.json.decode, message_str)

  if not success then
    return
  end

  -- Handle different message types
  if message.method == "Console.messageAdded" then
    M.handle_console_message(websocket, message.params.message)
  elseif message.method == "Runtime.consoleAPICalled" then
    M.handle_console_api_called(websocket, message.params)
  elseif message.method == "Runtime.exceptionThrown" then
    M.handle_exception(websocket, message.params.exceptionDetails)
  end

  -- Call user callback
  if websocket.callbacks.on_message then
    websocket.callbacks.on_message(message)
  end
end

-- Handle console messages
function M.handle_console_message(websocket, console_message)
  local formatted = M.format_console_message(console_message)
  if websocket.callbacks.on_console then
    websocket.callbacks.on_console(formatted)
  end
end

-- Handle console API calls (console.log, console.error, etc.)
function M.handle_console_api_called(websocket, params)
  local formatted = M.format_console_api_call(params)
  if websocket.callbacks.on_console then
    websocket.callbacks.on_console(formatted)
  end
end

-- Handle JavaScript exceptions
function M.handle_exception(websocket, exception_details)
  local formatted = M.format_exception(exception_details)
  if websocket.callbacks.on_console then
    websocket.callbacks.on_console(formatted)
  end
end

-- Format console message for display
function M.format_console_message(message)
  local timestamp = os.date "%H:%M:%S"
  local level = message.level or "log"
  local text = message.text or ""

  return {
    timestamp = timestamp,
    level = level,
    text = text,
    source = message.source,
    line = message.line,
    column = message.column,
  }
end

-- Format console API call for display
function M.format_console_api_call(params)
  local timestamp = os.date "%H:%M:%S"
  local level = params.type or "log"
  local args = params.args or {}

  local text_parts = {}
  for _, arg in ipairs(args) do
    if arg.value ~= nil then
      table.insert(text_parts, tostring(arg.value))
    elseif arg.description then
      table.insert(text_parts, arg.description)
    else
      table.insert(text_parts, vim.inspect(arg))
    end
  end

  return {
    timestamp = timestamp,
    level = level,
    text = table.concat(text_parts, " "),
    source = "console-api",
  }
end

-- Format exception for display
function M.format_exception(exception_details)
  local timestamp = os.date "%H:%M:%S"
  local text = exception_details.text or "JavaScript Error"

  if exception_details.exception and exception_details.exception.description then
    text = exception_details.exception.description
  end

  return {
    timestamp = timestamp,
    level = "error",
    text = text,
    source = "exception",
    line = exception_details.lineNumber,
    column = exception_details.columnNumber,
    url = exception_details.url,
  }
end

-- Send command to WebSocket
function M.send_command(websocket, method, params)
  if not websocket or not websocket.job_id then
    return false
  end

  local command = {
    id = websocket.message_id,
    method = method,
    params = params or {},
  }

  websocket.message_id = websocket.message_id + 1

  local json_str = vim.json.encode(command)
  vim.fn.chansend(websocket.job_id, json_str .. "\n")

  return true
end

-- Close WebSocket connection
function M.close(websocket)
  if websocket and websocket.job_id then
    vim.fn.jobstop(websocket.job_id)
    websocket.job_id = nil
  end
end

return M

