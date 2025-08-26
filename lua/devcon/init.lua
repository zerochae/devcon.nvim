local browser = require "devcon.browser"
local websocket = require "devcon.websocket"
local ui = require "devcon.ui"

local M = {}

-- Default configuration
M.config = {
  -- Browser settings
  browser = {
    type = "arc", -- chrome, edge, chromium, arc
    debug_port = 9222,
    url = "http://localhost:4000",
    arc_mode = "little", -- "little" or "normal" for Arc browser
  },
  
  -- UI settings
  ui = {
    window = {
      width = 100,
      height = 25,
      position = "bottom", -- "bottom", "right", "floating"
    },
    console = {
      max_lines = 1000,
      auto_scroll = true,
      timestamp = true,
    }
  },
  
  -- WebSocket settings
  websocket = {
    timeout = 5000,
    retry_count = 3,
  },

  -- Browser executable paths by OS and browser type
  browser_paths = {
    Darwin = {
      chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      edge = "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      chromium = "/Applications/Chromium.app/Contents/MacOS/Chromium",
      arc = "arc-cli", -- Use arc-cli command
    },
    Linux = {
      chrome = "google-chrome",
      edge = "microsoft-edge",
      chromium = "chromium-browser",
      arc = "arc-cli",
    },
    Windows_NT = {
      chrome = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
      edge = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
      chromium = "C:\\Users\\%USERNAME%\\AppData\\Local\\Chromium\\Application\\chrome.exe",
      arc = "arc-cli",
    }
  }
}

M.state = {
  browser_process = nil,
  websocket = nil,
  console_buffer = nil,
  is_connected = false,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  -- Share config with UI module
  ui.set_config(M.config)
end

function M.start_debug_session(url)
  local target_url = url or M.config.browser.url

  -- Stop any existing session
  M.stop_debug_session()
  
  -- Kill any existing Chrome processes with debug port to avoid conflicts
  vim.notify("DevCon: Stopping existing Chrome instances...", vim.log.levels.INFO)
  vim.fn.system("pkill -f 'remote-debugging-port=" .. M.config.browser.debug_port .. "'")
  vim.fn.system("sleep 1") -- Wait a moment

  -- Start browser with debugging enabled
  local browser_result = browser.start_browser(target_url, M.config.browser.debug_port, M.config.browser.type, M.config.browser.arc_mode, M.config.browser_paths)
  if not browser_result then
    vim.notify("DevCon: Failed to start browser", vim.log.levels.ERROR)
    return false
  end

  M.state.browser_process = browser_result

  -- Wait a bit longer for browser to start
  vim.notify("DevCon: Waiting for Chrome to start...", vim.log.levels.INFO)
  vim.defer_fn(function()
    -- Get WebSocket URL from Chrome DevTools API with retry
    websocket.get_websocket_url(M.config.browser.debug_port, function(ws_url)
      if not ws_url then
        vim.notify("DevCon: Failed to get WebSocket URL after retries", vim.log.levels.ERROR)
        return
      end

      vim.notify("DevCon: Connecting to WebSocket...", vim.log.levels.INFO)
      -- Connect to WebSocket
      M.state.websocket = websocket.connect(ws_url, {
        on_message = M.on_console_message,
        on_console = M.on_console_message,
        on_close = M.on_websocket_close,
        on_error = M.on_websocket_error,
      })

      if M.state.websocket then
        M.state.is_connected = true
        ui.create_console_window()
        vim.notify("DevCon: Connected to browser debugger", vim.log.levels.INFO)

        -- Enable console API
        websocket.send_command(M.state.websocket, "Runtime.enable")
        websocket.send_command(M.state.websocket, "Console.enable")
      end
    end)
  end, 3000)

  return true
end

function M.stop_debug_session()
  if M.state.websocket then
    websocket.close(M.state.websocket)
    M.state.websocket = nil
  end

  if M.state.browser_process then
    browser.stop_browser(M.state.browser_process)
    M.state.browser_process = nil
  end

  ui.close_console_window()
  M.state.is_connected = false

  vim.notify("DevCon: Debug session stopped", vim.log.levels.INFO)
end

function M.on_console_message(message)
  ui.append_console_message(message)
end

function M.on_websocket_close()
  M.state.is_connected = false
  vim.notify("DevCon: WebSocket connection closed", vim.log.levels.WARN)
end

function M.on_websocket_error(error)
  vim.notify("DevCon WebSocket error: " .. tostring(error), vim.log.levels.ERROR)
end

function M.execute_js(code)
  if not M.state.is_connected or not M.state.websocket then
    vim.notify("DevCon: Not connected to browser", vim.log.levels.ERROR)
    return
  end

  websocket.send_command(M.state.websocket, "Runtime.evaluate", {
    expression = code,
    includeCommandLineAPI = true,
  })
end

function M.get_status()
  return {
    connected = M.state.is_connected,
    browser_running = M.state.browser_process ~= nil,
    websocket_connected = M.state.websocket ~= nil,
  }
end

return M