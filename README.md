# Toolbar Helper (macOS)

Toolbar Helper is a macOS menu bar app for pinning and restoring specific windows (not just apps) using Accessibility APIs.

It runs as an `NSStatusItem` app (`LSUIElement`), supports multiple windows from the same app, and lets you jump back to exact windows with one click.

## Current Features

- Menu bar app with no Dock presence.
- Per-window pinning with support for multiple windows from the same app.
- Open Windows list (icon + title + checkmark state) in the menu.
- Pin/unpin, rename, and reset custom label actions.
- Pinned tab click restores exact window focus by:
  - activating the app
  - unminimizing the window
  - raising/focusing the target window
- Drag-and-drop reorder for visible pinned tabs.
- Overflow menu for pinned tabs beyond visible capacity (default visible max: 10).
- Missing-window state for closed/unmatched pins.
- Diagnostics submenu with runtime counters and copy-to-clipboard report.
- Persistent pins and custom names via `UserDefaults`.
- Accessibility implementation uses public AX APIs only.

## UI Notes

- Main management menu is a single gear icon in the menu bar strip.
- When Accessibility is not trusted, the orange warning icon opens macOS Accessibility settings directly.

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

1. Launch Toolbar Helper.
2. If needed, use the gear menu -> Accessibility actions.
3. In System Settings:
   - Privacy & Security -> Accessibility
   - enable `Toolbar Helper`
4. If trust state appears stale, use:
   - gear menu -> `Re-check Accessibility Status`
   - or gear menu -> `Settings` -> `Restart Window Polling`

## Usage

1. Click the gear icon in the strip.
2. In `Open Windows`, pin/unpin or rename a window label.
3. Click a pinned tab to focus that exact window.
4. Drag pinned tabs to reorder.
5. Use `…` overflow for additional pinned tabs.
6. Open `Settings` -> `Diagnostics` to copy runtime diagnostics.

## Troubleshooting

### Accessibility still appears disabled

- Re-check status from the gear menu.
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
