# DevCon.nvim

A Neovim plugin that connects to Chrome DevTools for real-time browser console debugging within nvim.

## Features

- 🚀 Launch Chrome/Edge/Chromium/Arc with remote debugging
- 🔌 WebSocket connection to Chrome DevTools Protocol  
- 📱 Real-time console output in nvim
- 🎨 Syntax-highlighted console messages
- ⚡ Execute JavaScript code directly from nvim
- 🖥️ Customizable console window (floating/split)
- 🌟 Arc browser Little Arc mode support

## Requirements

- Neovim 0.8+
- Chrome, Edge, Chromium, or Arc browser
- `websocat` or `wscat` for WebSocket connections:
  ```bash
  # Install websocat (recommended)
  brew install websocat
  # or npm install -g wscat
  ```
- For Arc browser support: `arc-cli`
  ```bash
  npm install -g arc-cli
  # or brew install arc-cli
  ```

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "kwon-gray/devcon.nvim",
  cmd = { "DevConStart", "DevConStop", "DevConToggle", "DevConStatus", "DevConExec" },
  keys = {
    { "<leader>dc", "<cmd>DevConToggle<cr>", desc = "Toggle DevCon Console" },
    { "<leader>ds", "<cmd>DevConStart<cr>", desc = "Start DevCon Session" },
    { "<leader>dx", "<cmd>DevConStop<cr>", desc = "Stop DevCon Session" },
    { "<leader>dS", "<cmd>DevConStatus<cr>", desc = "DevCon Status" },
  },
  opts = {
    browser = {
      type = "arc", -- chrome, edge, chromium, arc
      url = "http://localhost:4000",
      arc_mode = "little", -- "little" or "normal" (for Arc only)
    }
  }
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "kwon-gray/devcon.nvim",
  config = function()
    require("devcon").setup({
      browser = {
        type = "arc",
        url = "http://localhost:4000",
      }
    })
  end
}
```

## Configuration

Default configuration:

```lua
{
  -- Browser settings
  browser = {
    type = "arc", -- chrome, edge, chromium, arc
    debug_port = 9222,
    url = "http://localhost:3000",
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
  }
}
```

## Usage

### Commands

- `:DevConStart [url]` - Start debug session (default: configured URL)
- `:DevConStop` - Stop debug session and close browser
- `:DevConToggle` - Toggle console window
- `:DevConStatus` - Show connection status
- `:DevConExec [code]` - Execute JavaScript code in browser

### Key Mappings (suggested)

```lua
vim.keymap.set("n", "<leader>dc", "<cmd>DevConToggle<cr>", { desc = "Toggle DevCon Console" })
vim.keymap.set("n", "<leader>ds", "<cmd>DevConStart<cr>", { desc = "Start DevCon Session" })
vim.keymap.set("n", "<leader>dx", "<cmd>DevConStop<cr>", { desc = "Stop DevCon Session" })
vim.keymap.set("n", "<leader>dS", "<cmd>DevConStatus<cr>", { desc = "Show DevCon Status" })
```

### Console Window Keys

When the console window is active:
- `q` or `<ESC>` - Close console
- `c` - Clear console messages
- `r` - Refresh console display

## Example Workflow

1. Start your web development server: `npm run dev`
2. Open DevCon console: `<leader>dc`
3. Start debug session: `:DevConStart` (opens browser with debugging)
4. View real-time console.log(), errors, and warnings in nvim
5. Execute JS directly: `:DevConExec console.log('Hello from nvim!')`
6. Stop when done: `:DevConStop`

## Browser Support

| Browser | Support | Notes |
|---------|---------|-------|
| ✅ Chrome | Full | Standard Chromium debugging |
| ✅ Microsoft Edge | Full | Chromium-based Edge |
| ✅ Chromium | Full | Open source version |
| ✅ **Arc** | Full | Uses `arc-cli` for Little Arc mode |
| ❌ Safari | None | No remote debugging support |
| ❌ Firefox | None | Different debugging protocol |

### Arc Browser Special Features

Arc browser supports two modes:
- **Little Arc** (`arc_mode = "little"`) - Compact window mode
- **Normal** (`arc_mode = "normal"`) - Regular window

## API

### Setup

```lua
require("devcon").setup({
  browser = {
    type = "arc",
    url = "http://localhost:4000",
  }
})
```

### Methods

```lua
local devcon = require("devcon")

-- Start debug session
devcon.start_debug_session("http://localhost:3000")

-- Stop debug session
devcon.stop_debug_session()

-- Execute JavaScript
devcon.execute_js("console.log('Hello from Neovim!')")

-- Get status
local status = devcon.get_status()
print(status.connected) -- boolean
```

## Troubleshooting

### "Browser not found" error
- Check if your browser is installed in the expected location
- For Arc: ensure `arc-cli` is installed (`npm install -g arc-cli`)

### "WebSocket tool not found" error
- Install websocat: `brew install websocat`
- Or install wscat: `npm install -g wscat`

### Connection fails
- Ensure browser starts with debugging port (check terminal output)
- Wait a moment after browser launch before connecting
- Try different debug port if 9222 is in use:
  ```lua
  opts = {
    browser = { debug_port = 9223 }
  }
  ```

### Arc-specific issues
- Make sure Arc is running before using arc-cli
- Try `arc-cli --help` to verify installation
- For debugging, Arc needs to be launched with remote debugging enabled

## Development

### Project Structure
```
devcon.nvim/
├── lua/
│   └── devcon/
│       ├── init.lua      # Main module
│       ├── browser.lua   # Browser management
│       ├── websocket.lua # WebSocket & DevTools Protocol
│       └── ui.lua        # Console UI
├── plugin/
│   └── devcon.lua        # Plugin initialization
└── README.md
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Credits

- Chrome DevTools Protocol for browser communication
- Arc browser team for arc-cli
- Neovim community for the excellent plugin ecosystem