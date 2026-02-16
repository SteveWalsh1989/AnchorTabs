# AnchorTabs (macOS)

AnchorTabs is a macOS menu bar app for pinning and restoring specific windows (not just apps) using Accessibility APIs.

It runs as an `NSStatusItem` app (`LSUIElement`), supports multiple windows from the same app, and lets you jump back to exact windows with one click.

## Current Features

- Menu bar app with no Dock presence.
- Per-window pinning with support for multiple windows from the same app.
- Open Windows popover with pin/focus controls.
- Row-level controls for pin/unpin and rename pinned labels.
- Pinned tab click restores exact window focus by:
  - activating the app
  - unminimizing the window
  - raising/focusing the target window
- Drag-and-drop reorder for visible pinned tabs.
- Overflow menu for pinned tabs beyond visible capacity (default visible max: 10).
- Missing-window state for closed/unmatched pins.
- Diagnostics copy action in the popover's `More` menu.
- Persistent pins and custom names via `UserDefaults`.
- Accessibility implementation uses public AX APIs only.

## UI Notes

- Main management entry is a single gear icon that opens the window manager popover.
- The orange Accessibility warning icon is clickable and opens macOS Accessibility settings directly.
- The popover includes a `More` menu for refresh, restart polling, accessibility actions, and diagnostics copy.

## Tech Stack

- Swift 6 + SwiftUI
- AppKit status item hosting
- Accessibility APIs (`AXUIElement`, `AXObserver`)
- `UserDefaults` for persistence

## Project Structure

- `toolbar-helper/App/`
  - `ToolbarHelperApp.swift` (app entry)
  - `AppDelegate.swift` (startup/lifecycle)
  - `AppModel.swift` (app-level orchestration)
  - `StatusBarController.swift` (status-item host)
- `toolbar-helper/Views/`
  - `MenuBarStripView.swift` (menu bar UI/actions)
  - `WindowManagerPopoverView.swift` (open windows popover UI)
  - `SettingsView.swift` (settings scene)
- `toolbar-helper/Stores/`
  - `WindowStore.swift` (AX enumeration/focus/observer polling)
  - `PinnedStore.swift` (pin persistence/reconciliation)
  - `PinMatcher.swift` (matching strategy/scoring)
- `toolbar-helper/Services/`
  - `AccessibilityPermissionManager.swift` (AX trust/prompt/settings)
- `toolbar-helper/Models/`
  - `Models.swift` (window/pin models)
  - `DiagnosticsModels.swift` (diagnostic model types)
- `toolbar-helper/Utilities/`
  - `StringExtensions.swift` (matching helpers)

## Requirements

- macOS (latest recommended)
- Xcode 26.2+ (Swift 6 toolchain)

## Build and Run

### Xcode

1. Open `toolbar-helper.xcodeproj`
2. Select scheme `toolbar-helper`
3. Run on `My Mac`

### CLI

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project toolbar-helper.xcodeproj \
  -scheme toolbar-helper \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .DerivedData \
  build
```

## Accessibility Setup

1. Launch AnchorTabs.
2. Click the orange warning icon to open Accessibility settings directly, or open the gear popover and use `More`.
3. In System Settings:
   - Privacy & Security -> Accessibility
   - enable the app with bundle id `com.stevewalsh.ToolbarHelper`
4. If trust state appears stale, use:
   - popover -> `More` -> `Enable Accessibility Access`
   - popover -> `More` -> `Restart Window Polling`

## Usage

1. Click the gear icon to open the window manager popover.
2. In `Open Windows`:
   - click the window name to focus it
   - click the pin icon to pin/unpin it
   - for pinned rows, use the pencil action to rename
3. Click a pinned tab in the strip to focus that exact window.
4. Drag pinned tabs in the strip to reorder.
5. Use `…` overflow for pinned tabs beyond the visible strip.
6. Open `More` in the popover to refresh, restart polling, open accessibility settings, or copy diagnostics.

## Troubleshooting

### Accessibility still appears disabled

- Use popover `More` actions (`Enable Accessibility Access` / `Restart Window Polling`).
- Relaunch the app.
- Reset AX permission and re-enable:

```bash
tccutil reset Accessibility com.stevewalsh.ToolbarHelper
```

### xcodebuild uses CommandLineTools instead of full Xcode

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Privacy

- No network dependency for core behavior.
- Pinned window metadata and custom labels are local-only (`UserDefaults`).

## Notes on Naming

- App branding name: `AnchorTabs`
- Current Xcode target/scheme/repo path names remain `toolbar-helper` for now.
- Bundle identifier remains `com.stevewalsh.ToolbarHelper` unless changed later.
