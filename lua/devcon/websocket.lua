local M = {}

-- Get WebSocket URL from Chrome DevTools API with retry
function M.get_websocket_url(debug_port, callback, retry_count, callback_called)
  retry_count = retry_count or 5
  callback_called = callback_called or { value = false }
  local url = "http://localhost:" .. debug_port .. "/json"

  -- Use curl to get the JSON data
  local cmd = { "curl", "-s", url }

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 or data[1] == "" then
        if retry_count > 0 and not callback_called.value then
          vim.notify("DevCon: Empty response, retrying... (" .. retry_count .. " left)", vim.log.levels.WARN)
          vim.defer_fn(function()
            M.get_websocket_url(debug_port, callback, retry_count - 1, callback_called)
          end, 1000)
        else
          if not callback_called.value then
            callback_called.value = true
            callback(nil)
          end
        end
        return
      end

      local json_str = table.concat(data, "\n")
      
      -- Debug: show first part of response
      if json_str:match("^%s*$") then
        if retry_count > 0 and not callback_called.value then
          vim.notify("DevCon: Chrome not ready, retrying... (" .. retry_count .. " left)", vim.log.levels.WARN)
          vim.defer_fn(function()
            M.get_websocket_url(debug_port, callback, retry_count - 1, callback_called)
          end, 1000)
        else
          if not callback_called.value then
            callback_called.value = true
            callback(nil)
          end
        end
        return
      end

      local success, json_data = pcall(vim.json.decode, json_str)

      if not success then
        vim.notify("DevCon: Invalid JSON from Chrome: " .. json_str:sub(1, 100) .. "...", vim.log.levels.ERROR)
        if retry_count > 0 and not callback_called.value then
          vim.defer_fn(function()
            M.get_websocket_url(debug_port, callback, retry_count - 1, callback_called)
          end, 1000)
        else
          if not callback_called.value then
            callback_called.value = true
            callback(nil)
          end
        end
        return
      end

      if not json_data or type(json_data) ~= "table" or #json_data == 0 then
        if retry_count > 0 and not callback_called.value then
          vim.notify("DevCon: No tabs found, retrying... (" .. retry_count .. " left)", vim.log.levels.WARN)
          vim.defer_fn(function()
            M.get_websocket_url(debug_port, callback, retry_count - 1, callback_called)
          end, 1000)
        else
          if not callback_called.value then
            callback_called.value = true
            vim.notify("DevCon: No debuggable tabs found", vim.log.levels.ERROR)
            callback(nil)
          end
        end
        return
      end

      -- Find the first page/tab with webSocketDebuggerUrl
      for _, tab in ipairs(json_data) do
        if tab.webSocketDebuggerUrl and tab.type == "page" and not callback_called.value then
          callback_called.value = true
          vim.notify("DevCon: Found debuggable tab: " .. (tab.title or "Unknown"), vim.log.levels.INFO)
          -- Call callback immediately to prevent race condition
          callback(tab.webSocketDebuggerUrl)
          return
        end
      end

      if retry_count > 0 and not callback_called.value then
        vim.notify("DevCon: No debuggable pages in " .. #json_data .. " tabs, retrying... (" .. retry_count .. " left)", vim.log.levels.WARN)
        vim.defer_fn(function()
          M.get_websocket_url(debug_port, callback, retry_count - 1, callback_called)
        end, 1000)
      else
        if not callback_called.value then
          callback_called.value = true
          vim.notify("DevCon: No debuggable pages found after all retries", vim.log.levels.ERROR)
          callback(nil)
        end
      end
    end,
    on_stderr = function(_, data)
      if data and data[1] ~= "" then
        local error_msg = table.concat(data, "\n")
        vim.notify("DevCon: curl error: " .. error_msg, vim.log.levels.ERROR)
      end
      if retry_count > 0 and not callback_called.value then
        vim.defer_fn(function()
          M.get_websocket_url(debug_port, callback, retry_count - 1, callback_called)
        end, 1000)
      else
        callback(nil)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        if retry_count > 0 and not callback_called.value then
          vim.notify("DevCon: Chrome not ready (exit " .. code .. "), retrying... (" .. retry_count .. " left)", vim.log.levels.WARN)
          vim.defer_fn(function()
            M.get_websocket_url(debug_port, callback, retry_count - 1, callback_called)
          end, 1000)
        else
          if not callback_called.value then
            callback_called.value = true
            vim.notify("DevCon: Failed to connect to Chrome after all retries", vim.log.levels.ERROR)
            callback(nil)
          end
        end
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
  local text = tostring(message.text or "")
  
  -- Clean up newlines and control characters
  text = text:gsub("\n", " "):gsub("\r", " "):gsub("\t", " ")

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
      local value_str = tostring(arg.value)
      -- Clean up newlines and control characters
      value_str = value_str:gsub("\n", " "):gsub("\r", " "):gsub("\t", " ")
      table.insert(text_parts, value_str)
    elseif arg.description then
      local desc = tostring(arg.description)
      desc = desc:gsub("\n", " "):gsub("\r", " "):gsub("\t", " ")
      table.insert(text_parts, desc)
    else
      local inspected = vim.inspect(arg)
      inspected = inspected:gsub("\n", " "):gsub("\r", " "):gsub("\t", " ")
      table.insert(text_parts, inspected)
    end
  end

  local final_text = table.concat(text_parts, " ")
  -- Final cleanup
  final_text = final_text:gsub("\n", " "):gsub("\r", " "):gsub("\t", " ")

  return {
    timestamp = timestamp,
    level = level,
    text = final_text,
    source = "console-api",
  }
end

-- Format exception for display
function M.format_exception(exception_details)
  local timestamp = os.date "%H:%M:%S"
  local text = tostring(exception_details.text or "JavaScript Error")

  if exception_details.exception and exception_details.exception.description then
    text = tostring(exception_details.exception.description)
  end
  
  -- Clean up newlines and control characters
  text = text:gsub("\n", " "):gsub("\r", " "):gsub("\t", " ")

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

