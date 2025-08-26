-- DevCon.nvim - Browser debugging tool for Neovim
-- Author: kwon-gray
-- Version: 1.0.0

if vim.g.loaded_devcon then
  return
end
vim.g.loaded_devcon = 1

local devcon = require("devcon")

-- Create user commands
vim.api.nvim_create_user_command("DevConStart", function(args)
  local url = args.args ~= "" and args.args or nil
  devcon.start_debug_session(url)
end, { nargs = "?", desc = "Start DevCon debug session" })

vim.api.nvim_create_user_command("DevConStop", function()
  devcon.stop_debug_session()
end, { desc = "Stop DevCon debug session" })

vim.api.nvim_create_user_command("DevConToggle", function()
  require("devcon.ui").toggle_console_window()
end, { desc = "Toggle DevCon console window" })

vim.api.nvim_create_user_command("DevConStatus", function()
  local status = devcon.get_status()
  local ui_status = require("devcon.ui").get_status()
  
  vim.notify(
    string.format(
      [[DevCon Status:
  Connected: %s
  Browser Running: %s  
  WebSocket Connected: %s
  Console Open: %s
  Messages: %d]],
      status.connected and "✓" or "✗",
      status.browser_running and "✓" or "✗",
      status.websocket_connected and "✓" or "✗",
      ui_status.is_open and "✓" or "✗",
      ui_status.message_count
    ),
    vim.log.levels.INFO
  )
end, { desc = "Show DevCon status" })

vim.api.nvim_create_user_command("DevConExec", function(args)
  if args.args == "" then
    vim.ui.input({ prompt = "JavaScript Code: " }, function(code)
      if code then
        devcon.execute_js(code)
      end
    end)
  else
    devcon.execute_js(args.args)
  end
end, { nargs = "?", desc = "Execute JavaScript in browser" })

-- Auto-setup with default config if user doesn't call setup
if not vim.g.devcon_setup_called then
  vim.defer_fn(function()
    if not vim.g.devcon_setup_called then
      devcon.setup({})
      vim.g.devcon_setup_called = true
    end
  end, 100)
end