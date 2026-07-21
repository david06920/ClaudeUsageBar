# ClaudeUsageBar
A lightweight macOS menu bar widget that shows your Claude Code usage limits (session % and weekly %) at a glance — like the battery icon. Auto-refreshes on a configurable interval, with a smart mode that switches to 5-minute updates once usage hits 80%. No Xcode or Apple Developer account required.


# ClaudeUsageBar

A small macOS menu bar widget that permanently shows your Claude Code usage limits (session % and week %) — similar to the battery icon in the menu bar.

It runs `claude --print "/usage"` in the background, parses the two percentage values, and displays them in the menu bar.

## Requirements

- macOS
- Xcode Command Line Tools (`xcode-select --install`, if not already installed)
- The `claude` CLI must be installed and logged in, expected by default at `~/.local/bin/claude`
  (if your path differs, adjust `claudePath` in `main.swift`)

## Installation

```bash
chmod +x install.sh
./install.sh
```

The script:

1. compiles `main.swift` with `swiftc`
2. builds an `.app` bundle at `~/Applications/ClaudeUsageBar.app`
3. ad-hoc code-signs it (no Apple Developer account required)
4. sets up a LaunchAgent that starts the app automatically at every login

After installation, an icon appears immediately in the menu bar (e.g. `S 19% · W 45%`).

## Features

- **Update now** — manual refresh via the menu
- **Settings…** — slider for the refresh interval (1–60 min.)
- **Smart refresh** — checkbox in Settings: once session or weekly usage reaches ≥ 80%, it automatically refreshes every 5 minutes instead of the regular interval
- **Quit** — stops the app from the menu

Settings are persisted via `UserDefaults` and survive a restart.

## Uninstalling

```bash
launchctl unload ~/Library/LaunchAgents/com.example.claudeusagebar.plist
rm -rf ~/Applications/ClaudeUsageBar.app ~/Library/LaunchAgents/com.example.claudeusagebar.plist
```

## Rebuilding after code changes

```bash
./install.sh
```

(rebuilds, replaces the running version, and reloads the LaunchAgent)

## Notes

- The displayed values are approximate per `claude --print "/usage"` and are based only on local sessions on this machine — not on other devices or claude.ai.
- The app shows no Dock icon (`LSUIElement`), it runs purely in the menu bar.
- No App Store, no Apple Developer account signing required, since it's only installed locally (ad-hoc code signing).
