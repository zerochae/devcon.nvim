local M = {}

-- Config reference for debug logging
M.config = nil

-- Helper function for debug logging
local function debug_log(message, level)
  if M.config and M.config.debug then
    vim.notify(message, level or vim.log.levels.INFO)
  end
end

-- Set config for browser module
function M.set_config(config)
  M.config = config
end

-- Detect current OS
local function get_os()
  return vim.loop.os_uname().sysname
end

-- Find browser executable path
local function get_browser_path(browser_type, browser_paths)
  local os_name = get_os()
  local paths = browser_paths[os_name]

  if not paths or not paths[browser_type] then
    return nil
  end

  local path = paths[browser_type]

  -- Check if executable exists
  if os_name == "Windows_NT" then
    -- Expand %USERNAME% on Windows
    path = path:gsub("%%USERNAME%%", os.getenv "USERNAME" or "")
  end

  if vim.fn.executable(path) == 1 or vim.fn.filereadable(path) == 1 then
    return path
  end

  return nil
end

-- Start browser with remote debugging
function M.start_browser(url, debug_port, browser_type, arc_mode, browser_paths)
  local browser_path = get_browser_path(browser_type, browser_paths)

  if not browser_path then
    vim.notify("DevCon: Browser not found: " .. browser_type, vim.log.levels.ERROR)
    return nil
  end

  debug_log("DevCon: Starting browser: " .. browser_type)

  -- Build command arguments
  local args = {}
  
  -- Arc browser specific arguments (using arc-cli)
  if browser_type == "arc" then
    if arc_mode == "little" then
      table.insert(args, "new-little-arc")
    else
      table.insert(args, "new-window")
    end
    -- Arc CLI handles URL as last argument
    table.insert(args, url)
    -- Note: Arc CLI doesn't support --remote-debugging-port directly
    -- We'll need to handle debugging differently for Arc
  else
    -- Other browsers
    table.insert(args, "--remote-debugging-port=" .. debug_port)
    table.insert(args, "--no-first-run")
    table.insert(args, "--no-default-browser-check")
    table.insert(args, "--disable-background-timer-throttling")
    table.insert(args, "--disable-renderer-backgrounding")
    table.insert(args, "--disable-backgrounding-occluded-windows")
    table.insert(args, url)
  end

  -- Add user data directory to avoid conflicts (skip for Arc)
  local temp_dir = vim.fn.tempname() .. "_devcon_browser"
  if browser_type ~= "arc" then
    table.insert(args, 2, "--user-data-dir=" .. temp_dir)
  end

  local cmd = { browser_path }
  vim.list_extend(cmd, args)

  vim.notify("DevCon: Starting browser: " .. browser_type, vim.log.levels.INFO)

  -- For Arc, we need special handling
  if browser_type == "arc" then
    -- First start Arc with arc-cli
    local arc_handle = vim.loop.spawn(browser_path, {
      args = args,
      detached = true, -- Arc CLI should run detached
    }, function(code, signal)
      -- Arc CLI exits immediately after launching Arc
    end)
    
    -- Wait a moment then try to enable debugging on existing Arc
    vim.defer_fn(function()
      -- Try to start Arc main app with debugging
      local arc_app_path = "/Applications/Arc.app/Contents/MacOS/Arc"
      if vim.fn.filereadable(arc_app_path) == 1 then
        vim.loop.spawn(arc_app_path, {
          args = {"--remote-debugging-port=" .. debug_port},
          detached = true,
        })
      end
    end, 1000)
    
    return {
      handle = arc_handle,
      temp_dir = nil, -- Arc doesn't use temp dir
      browser_type = browser_type,
    }
  else
    -- Other browsers - normal spawn
    local handle = vim.loop.spawn(browser_path, {
      args = args,
      detached = false,
    }, function(code, signal)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("DevCon: Browser process exited with code " .. code, vim.log.levels.WARN)
        end)
      end
    end)
    
    if not handle then
      vim.notify("DevCon: Failed to start browser process", vim.log.levels.ERROR)
      return nil
    end
    
    return {
      handle = handle,
      temp_dir = temp_dir,
      browser_type = browser_type,
    }
  end
end

-- Stop browser process
function M.stop_browser(browser_process)
  if browser_process and browser_process.handle then
    if not vim.loop.process_kill(browser_process.handle, "SIGTERM") then
      vim.loop.process_kill(browser_process.handle, "SIGKILL")
    end

    -- Clean up temp directory
    if browser_process.temp_dir then
      vim.defer_fn(function()
        vim.fn.delete(browser_process.temp_dir, "rf")
      end, 1000)
    end
  end
end

-- Check if browser supports remote debugging
function M.check_browser_support(browser_type)
  local supported_browsers = { "chrome", "edge", "chromium", "arc" }
  return vim.tbl_contains(supported_browsers, browser_type)
end

-- Get available browsers on current system
function M.get_available_browsers(browser_paths)
  local os_name = get_os()
  local paths = browser_paths[os_name]
  local available = {}

  if not paths then
    return available
  end

  for browser_type, _ in pairs(paths) do
    if get_browser_path(browser_type, browser_paths) then
      table.insert(available, browser_type)
    end
  end

  return available
end

return M

