# Browser Commander

A macOS menu bar app that adds keyboard-driven navigation to any web browser. Go back, go forward, and navigate links — all without touching the mouse.

## Requirements

- macOS 14 (Sonoma) or later

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/BrowserCommander/releases/latest/download/BrowserCommander.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places the app in `/Applications` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/BrowserCommander/releases/latest)** — unzip and drag `BrowserCommander.app` to your Applications folder.

Or install it with [Homebrew](https://brew.sh):

```sh
brew install --cask perpetualbeta/jorvik/browsercommander
```

After installation:

1. Launch Browser Commander — a globe icon appears in the menu bar
2. Grant Accessibility permission when prompted

## How It Works

Browser Commander uses a CGEvent tap to intercept keyboard shortcuts when a browser is in focus. It reads the browser's UI via the Accessibility API to scrape links and detect text fields — no browser extensions, no JavaScript injection.

### Go Back / Go Forward

Press **Backspace** to go back a page, **Shift+Backspace** to go forward. These shortcuts are suppressed when you're typing in a text field, search bar, or any overlay panel (like Browser Notes).

Both shortcuts are fully configurable in Settings.

### Link Navigator

Press `control` `option` `shift` `command` `L` (Hyper+L) to open the Link Navigator — a floating HUD that lists every link on the current page. Type to filter, navigate with arrow keys, and press Return to go there.

| Key | Action |
|-----|--------|
| `up` / `down` | Navigate links |
| `return` | Open selected link |
| `esc` | Dismiss |
| **Type** | Filter by title or URL |

The Link Navigator scrapes links from the browser's Accessibility tree — up to 1,000 links per page, deduplicated by URL. It works with any browser that exposes standard link elements.

## Keyboard Shortcuts

| Action | Default | Configurable |
|--------|---------|:---:|
| Go Back | Backspace | Yes |
| Go Forward | Shift+Backspace | Yes |
| Link Navigator | `control` `option` `shift` `command` `L` | Yes |

All shortcuts are configurable in Settings.

### Supported Browsers

Safari, Chrome, Edge, Firefox, Arc, Brave, Opera, Vivaldi, Orion, Chromium, Zen, SigmaOS, Waterfox, LibreWolf, Mullvad Browser, Tor Browser, and more.

## Settings

Right-click the globe icon and choose **Settings...** to configure:

- **Enable/Disable** — toggle browser key remapping
- **Go Back shortcut** — customise the go back hotkey (default: Backspace)
- **Go Forward shortcut** — customise the go forward hotkey (default: Shift+Backspace)
- **Link Navigator shortcut** — customise the link navigator hotkey (default: `control` `option` `shift` `command` `L`)
- **Accessibility permission** — status display and grant button
- **Show icon in menu bar** — hide the globe status icon while Browser Commander keeps running (still reachable via its keyboard shortcut); the choice persists across launches, including login auto-start. *Shown only on macOS 14–15 — on macOS 26 (Tahoe) and later, use System Settings → Menu Bar, which provides this natively.*
- **Menu bar icon pill** — optional grey background for stronger contrast on busy or wallpaper-tinted menu bars (off by default)
- **Launch at Login** — start automatically when you log in

If you've hidden the status icon and want it back, simply re-open Browser Commander from your Applications folder — it reappears immediately.

Auto-updates are handled by Sparkle. Use the **Check for Updates…** entry in the right-click menu to check on demand; Sparkle's prompt offers an "Automatically download and install updates in the future" checkbox the first time an update is available.

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

The build is driven by the shared [`release.mk`](https://github.com/PerpetualBeta/jorvik-release) Make include, so `jorvik-release` has to be checked out **beside this repo** — the Makefile looks for it at `../jorvik-release/`. macOS ships GNU Make 3.81 as `make`, which is too old, so `gmake` comes from [Homebrew](https://brew.sh).

```bash
brew install make   # GNU Make 4+, if you do not already have gmake
git clone https://github.com/PerpetualBeta/jorvik-release.git
git clone https://github.com/PerpetualBeta/BrowserCommander.git
cd BrowserCommander
gmake build
open .build/BrowserCommander.app
```

---

Browser Commander is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
