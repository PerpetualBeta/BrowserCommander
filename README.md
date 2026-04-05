# Browser Commander

A macOS menu bar app that adds keyboard-driven navigation to any web browser. Go back, go forward, and navigate links — all without touching the mouse.

## Requirements

- macOS 14 (Sonoma) or later

## Installation

1. Double-click `BrowserCommander.app` to launch it
2. A globe icon appears in the menu bar
3. Grant Accessibility permission when prompted

## How It Works

Browser Commander uses a CGEvent tap to intercept keyboard shortcuts when a browser is in focus. It reads the browser's UI via the Accessibility API to scrape links and detect text fields — no browser extensions, no JavaScript injection.

### Go Back / Go Forward

Press **Backspace** to go back a page, **Shift+Backspace** to go forward. These shortcuts are suppressed when you're typing in a text field, search bar, or any overlay panel (like Browser Notes).

Both shortcuts are fully configurable in Settings.

### Link Navigator

Press **⌃⌥⇧⌘L** (Hyper+L) to open the Link Navigator — a floating HUD that lists every link on the current page. Type to filter, navigate with arrow keys, and press Return to go there.

| Key | Action |
|-----|--------|
| **↑** / **↓** | Navigate links |
| **Return** | Open selected link |
| **Escape** | Dismiss |
| **Type** | Filter by title or URL |

The Link Navigator scrapes links from the browser's Accessibility tree — up to 1,000 links per page, deduplicated by URL. It works with any browser that exposes standard link elements.

## Keyboard Shortcuts

| Action | Default | Configurable |
|--------|---------|:---:|
| Go Back | Backspace | Yes |
| Go Forward | Shift+Backspace | Yes |
| Link Navigator | ⌃⌥⇧⌘L | Yes |

All shortcuts are configurable in Settings.

### Supported Browsers

Safari, Chrome, Edge, Firefox, Arc, Brave, Opera, Vivaldi, Orion, Chromium, Zen, and more — 18 browsers in total.

## Settings

Right-click the globe icon and choose **Settings...** to configure:

- **Enable/Disable** — toggle browser key remapping
- **Go Back shortcut** — customise the go back hotkey (default: Backspace)
- **Go Forward shortcut** — customise the go forward hotkey (default: Shift+Backspace)
- **Link Navigator shortcut** — customise the link navigator hotkey (default: ⌃⌥⇧⌘L)
- **Accessibility permission** — status display and grant button
- **Menu bar icon pill** — optional coloured background for improved contrast on custom wallpapers
- **Launch at Login** — start automatically when you log in
- **Auto-update** — check for new versions on a configurable schedule

## Permissions

- **Accessibility** — required for keyboard interception and reading browser UI. macOS will prompt on first use.

## Architecture

| Component | Purpose |
|-----------|---------|
| `BrowserCommanderEngine.swift` | CGEvent tap for keyboard shortcuts, action dispatch |
| `LinkHUDPanel.swift` | Floating link navigator with filter, table view, navigation |
| `LinkScraper.swift` | Accessibility tree traversal to extract page links |
| `SharedTypes.swift` | Browser bundle IDs, text field detection, HUD panel delegate |
| `AppDelegate.swift` | Menu bar setup, settings, hotkey storage |
| `BrowserCommanderSettingsContent.swift` | SwiftUI settings panel |

## Building from Source

Browser Commander uses Swift Package Manager. No Xcode project is required.

```bash
git clone https://github.com/PerpetualBeta/BrowserCommander.git
cd BrowserCommander
./build.sh
open _BuildOutput/BrowserCommander.app
```

---

Browser Commander is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
