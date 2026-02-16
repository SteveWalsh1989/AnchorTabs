# Toolbar Helper (macOS)

Toolbar Helper is a macOS menu bar app for pinning and restoring **specific windows** (not just apps) using Accessibility APIs.

The app lives in the menu bar (`NSStatusItem`) and lets you pin multiple windows from the same app, rename pinned labels, and jump back to exact windows quickly.

## What It Does

- Runs as a menu bar app (`LSUIElement`) with no Dock presence.
- Pins windows per-window (supports multiple windows from the same app).
- Lists open windows from the `+` menu with:
  - app icon
  - readable title
  - selected state (checkmark)
  - actions to pin/unpin and rename toolbar label
- Restores pinned windows by:
  - activating the target app
  - unminimizing the window
  - focusing/raising the exact window
- Supports renamed custom labels for pinned items.
- Shows overflow when visible pinned tabs exceed max visible count.
- Persists pinned references and custom names between launches.
- Uses AX APIs only (no private APIs).

## Tech Stack

- Swift + SwiftUI (macOS app target)
- `AXUIElement` and `NSWorkspace`
- `UserDefaults` persistence

## Project Structure

- `toolbar-helper/ToolbarHelperApp.swift`  
  App entry point.
- `toolbar-helper/AppDelegate.swift`  
  Menu bar lifecycle and startup.
- `toolbar-helper/MenuBarStripView.swift`  
  Menu bar UI and dropdown actions.
- `toolbar-helper/WindowStore.swift`  
  AX window enumeration + window activation/focus logic.
- `toolbar-helper/PinnedStore.swift`  
  Pin persistence + runtime window matching.
- `toolbar-helper/AppModel.swift`  
  App-level state and orchestration.
- `toolbar-helper/AccessibilityPermissionManager.swift`  
  AX trust checks + prompt/settings flow.

## Requirements

- macOS (latest recommended)
- Xcode 26.2+ (or compatible Swift 6 toolchain)

## Build and Run

### In Xcode

1. Open `toolbar-helper.xcodeproj`
2. Select scheme: `toolbar-helper`
3. Run on `My Mac`

### CLI build

If your shell points to CommandLineTools instead of full Xcode, use:

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

## Accessibility Setup (First Launch)

1. Launch the app.
2. Open the `+` menu.
3. If prompted, use `Enable Accessibility Access`.
4. In System Settings:  
   `Privacy & Security` -> `Accessibility`  
   Enable **Toolbar Helper**.
5. If status appears stale, use:
   - `+` menu -> `Re-check Accessibility Status`, or
   - `+` menu -> `Settings` -> `Restart Window Polling`

## Usage

1. Click `+` in the menu bar.
2. In `Open Windows`, choose a window:
   - `Pin Window` / `Unpin Window`
   - `Rename Toolbar Label…`
3. Click pinned tabs in the strip to restore/focus windows.
4. Use overflow (`…`) when many pins are present.
5. Open `+` -> `Settings` for refresh/accessibility actions.

## Troubleshooting

### AX still appears disabled after enabling it

- Use `Re-check Accessibility Status`.
- Relaunch the app.
- Reset the AX TCC entry and re-enable:

```bash
tccutil reset Accessibility com.stevewalsh.ToolbarHelper
```

### `xcodebuild` says Xcode is not selected

Use the explicit `DEVELOPER_DIR` command above, or set:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Privacy

- No network calls are required for core functionality.
- Pinned window metadata and custom labels are stored locally via `UserDefaults`.
