local M = {}

M.state = {
  console_buf = nil,
  console_win = nil,
  console_lines = {},
  is_open = false,
  config = nil,
  resize_autocmd_id = nil,
}

-- Console log level colors
local level_colors = {
  log = "Normal",
  info = "DiagnosticInfo", 
  warn = "DiagnosticWarn",
  warning = "DiagnosticWarn",
  error = "DiagnosticError",
  debug = "Comment",
}

-- Set config for UI module
function M.set_config(config)
  M.state.config = config
end

-- Create console window
function M.create_console_window()
  if M.state.is_open then
    return M.state.console_buf
  end
  
  -- Create buffer
  M.state.console_buf = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(M.state.console_buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(M.state.console_buf, "swapfile", false)
  vim.api.nvim_buf_set_option(M.state.console_buf, "filetype", "devcon-console")
  vim.api.nvim_buf_set_name(M.state.console_buf, "DevCon Console")
  
  -- Create floating window or split based on config
  local ui_config = M.state.config and M.state.config.ui or { window = { width = 100, height = 25, position = "bottom" } }
  local win_config = M.get_window_config(ui_config.window)
  
  M.state.console_win = vim.api.nvim_open_win(M.state.console_buf, false, win_config)
  
  -- Set window options
  vim.api.nvim_win_set_option(M.state.console_win, "wrap", true)
  vim.api.nvim_win_set_option(M.state.console_win, "number", false)
  vim.api.nvim_win_set_option(M.state.console_win, "relativenumber", false)
  vim.api.nvim_win_set_option(M.state.console_win, "signcolumn", "no")
  vim.api.nvim_win_set_option(M.state.console_win, "foldcolumn", "0")
  
  -- Set buffer content
  local header = {
    "╭─────────────────────────────────────────────────────────────────────────────╮",
    "│                              DevCon Console                                 │",
    "│                     Chrome DevTools Console Output                          │",
    "╰─────────────────────────────────────────────────────────────────────────────╯",
    "",
  }
  
  vim.api.nvim_buf_set_lines(M.state.console_buf, 0, -1, false, header)
  
  -- Set buffer keymaps
  M.set_console_keymaps()
  
  -- Setup resize handler
  M.setup_resize_handler()
  
  M.state.is_open = true
  
  return M.state.console_buf
end

-- Close console window
function M.close_console_window()
  -- Clean up resize handler
  M.cleanup_resize_handler()
  
  if M.state.console_win and vim.api.nvim_win_is_valid(M.state.console_win) then
    vim.api.nvim_win_close(M.state.console_win, true)
  end
  
  if M.state.console_buf and vim.api.nvim_buf_is_valid(M.state.console_buf) then
    vim.api.nvim_buf_delete(M.state.console_buf, { force = true })
  end
  
  M.state.console_buf = nil
  M.state.console_win = nil
  M.state.is_open = false
end

-- Toggle console window
function M.toggle_console_window()
  if M.state.is_open then
    M.close_console_window()
  else
    M.create_console_window()
  end
end

-- Get window configuration based on position
function M.get_window_config(window_config)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  
  local width = math.min(window_config.width, editor_width - 4)
  local height = math.min(window_config.height, editor_height - 6)
  
  local position = window_config.position
  
  if position == "bottom" then
    return {
      relative = "editor",
      width = editor_width,
      height = height,
      row = editor_height - height - 2,
      col = 0,
      style = "minimal",
      border = "single",
      title = " DevCon Console ",
      title_pos = "center",
    }
  elseif position == "right" then
    return {
      relative = "editor",
      width = width,
      height = editor_height - 4,
      row = 1,
      col = editor_width - width,
      style = "minimal",
      border = "single", 
      title = " DevCon Console ",
      title_pos = "center",
    }
  else -- floating
    return {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((editor_height - height) / 2),
      col = math.floor((editor_width - width) / 2),
      style = "minimal",
      border = "single",
      title = " DevCon Console ",
      title_pos = "center",
    }
  end
end

-- Append console message to buffer
function M.append_console_message(message_data)
  if not M.state.console_buf or not vim.api.nvim_buf_is_valid(M.state.console_buf) then
    return
  end
  
  local formatted_msg = M.format_message_for_display(message_data)
  table.insert(M.state.console_lines, formatted_msg)
  
  -- Limit console lines
  local max_lines = (M.state.config and M.state.config.ui.console.max_lines) or 1000
  if #M.state.console_lines > max_lines then
    table.remove(M.state.console_lines, 1)
  end
  
  -- Update buffer
  M.update_console_buffer()
  
  -- Auto-scroll to bottom if enabled and window is valid
  local auto_scroll = (M.state.config and M.state.config.ui.console.auto_scroll) or true
  if auto_scroll and M.state.console_win and vim.api.nvim_win_is_valid(M.state.console_win) then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(M.state.console_win) and vim.api.nvim_buf_is_valid(M.state.console_buf) then
        local line_count = vim.api.nvim_buf_line_count(M.state.console_buf)
        vim.api.nvim_win_set_cursor(M.state.console_win, { line_count, 0 })
        -- Also scroll to show the last line
        pcall(function()
          vim.api.nvim_win_call(M.state.console_win, function()
            vim.cmd("normal! G")
          end)
        end)
      end
    end)
  end
end

-- Format message for display
function M.format_message_for_display(message_data)
  local timestamp = ""
  local show_timestamp = (M.state.config and M.state.config.ui.console.timestamp) or true
  if show_timestamp and message_data.timestamp then
    timestamp = "[" .. message_data.timestamp .. "] "
  end
  
  local level_prefix = ""
  if message_data.level then
    local level = message_data.level:upper()
    if level == "LOG" then
      level_prefix = ""
    else
      level_prefix = "[" .. level .. "] "
    end
  end
  
  local source_info = ""
  if message_data.source and message_data.source ~= "console-api" then
    if message_data.line then
      source_info = " (" .. (message_data.source or "") .. ":" .. (message_data.line or "") .. ")"
    end
  end
  
  -- Handle newlines in message text by splitting into multiple lines
  local message_text = message_data.text or ""
  -- Replace newlines with spaces to keep it on one line, or split if needed
  message_text = message_text:gsub("\n", " "):gsub("\r", " ")
  
  return {
    text = timestamp .. level_prefix .. message_text .. source_info,
    level = message_data.level or "log",
    raw_data = message_data,
  }
end

-- Update console buffer with all messages
function M.update_console_buffer()
  if not M.state.console_buf or not vim.api.nvim_buf_is_valid(M.state.console_buf) then
    return
  end
  
  -- Get header lines (first 5 lines)
  local current_lines = vim.api.nvim_buf_get_lines(M.state.console_buf, 0, 5, false)
  local header_lines = current_lines
  
  -- Add console messages
  local display_lines = vim.deepcopy(header_lines)
  for _, msg in ipairs(M.state.console_lines) do
    -- Ensure msg.text is a string and doesn't contain newlines
    local text = tostring(msg.text or "")
    text = text:gsub("\n", " "):gsub("\r", " ")
    table.insert(display_lines, text)
  end
  
  -- Update buffer safely
  pcall(function()
    vim.api.nvim_buf_set_lines(M.state.console_buf, 0, -1, false, display_lines)
  end)
  
  -- Apply syntax highlighting
  M.apply_syntax_highlighting()
end

-- Apply syntax highlighting to console messages  
function M.apply_syntax_highlighting()
  if not M.state.console_buf or not vim.api.nvim_buf_is_valid(M.state.console_buf) then
    return
  end
  
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(M.state.console_buf, -1, 0, -1)
  
  local line_num = 5 -- Start after header
  for _, msg in ipairs(M.state.console_lines) do
    local highlight_group = level_colors[msg.level] or "Normal"
    vim.api.nvim_buf_add_highlight(M.state.console_buf, -1, highlight_group, line_num, 0, -1)
    line_num = line_num + 1
  end
end

-- Set console buffer keymaps
function M.set_console_keymaps()
  if not M.state.console_buf then
    return
  end
  
  local opts = { buffer = M.state.console_buf, noremap = true, silent = true }
  
  -- Close console
  vim.keymap.set("n", "q", function() M.close_console_window() end, opts)
  vim.keymap.set("n", "<ESC>", function() M.close_console_window() end, opts)
  
  -- Clear console
  vim.keymap.set("n", "c", function() M.clear_console() end, opts)
  
  -- Refresh
  vim.keymap.set("n", "r", function() M.update_console_buffer() end, opts)
end

-- Clear console messages
function M.clear_console()
  M.state.console_lines = {}
  M.update_console_buffer()
  vim.notify("DevCon: Console cleared", vim.log.levels.INFO)
end

-- Get console status
function M.get_status()
  return {
    is_open = M.state.is_open,
    message_count = #M.state.console_lines,
    buffer_valid = M.state.console_buf and vim.api.nvim_buf_is_valid(M.state.console_buf),
    window_valid = M.state.console_win and vim.api.nvim_win_is_valid(M.state.console_win),
  }
end

-- Setup resize handler
function M.setup_resize_handler()
  if M.state.resize_autocmd_id then
    return -- Already set up
  end
  
  M.state.resize_autocmd_id = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      M.handle_resize()
    end,
    desc = "DevCon console window resize handler"
  })
end

-- Clean up resize handler
function M.cleanup_resize_handler()
  if M.state.resize_autocmd_id then
    vim.api.nvim_del_autocmd(M.state.resize_autocmd_id)
    M.state.resize_autocmd_id = nil
  end
end

-- Handle nvim resize event
function M.handle_resize()
  if not M.state.is_open or not M.state.console_win or not vim.api.nvim_win_is_valid(M.state.console_win) then
    return
  end
  
  -- Get current window config
  local ui_config = M.state.config and M.state.config.ui or { window = { width = 100, height = 25, position = "bottom" } }
  local new_config = M.get_window_config(ui_config.window)
  
  -- Update window configuration
  pcall(function()
    vim.api.nvim_win_set_config(M.state.console_win, new_config)
  end)
end

-- Update window size and position manually (can be called by user)
function M.resize_console_window()
  M.handle_resize()
end

return M