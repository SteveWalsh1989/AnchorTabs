# AnchorTabs (macOS)

AnchorTabs is a macOS menu bar app for pinning specific windows and restoring the exact window with one click.

It is designed for heavy multi-window workflows (for example, multiple Cursor workspaces or multiple Chrome windows) to easily ping, rename, and select opened windows.

## Why make it
- Personally I never found the ALT TAB or ALT SHIFT TAB or swipe up to be a good way of switching for active windows, especially if just switching often between a few of the opened windows
- This allows you to select a few windows for quick access at the top, this means no more leaving a small section overlapping or having windows different heights to try move quickly or using swipe and then figuring out which window is which. 

## Features

- Menu bar app (`LSUIElement`) with no Dock icon.
- Per-window pinning, including multiple windows from the same app.
- Open windows manager popover with focus, pin/unpin, and rename actions.
- Drag-and-drop pin reordering plus overflow menu for tabs beyond the visible limit.
- Missing-window handling for closed or unmatched pinned windows.
- Local persistence for pins, custom names, and UI settings (`UserDefaults`).

### Robust Window Mapping

The app now uses stricter mapping rules so pins do not silently jump to the wrong window:

- Uses `AXWindowNumber` when available.
- For windows without `AXWindowNumber`, reuses runtime IDs by matching the underlying `AXUIElement`.
- Generates unique runtime IDs for newly seen no-number windows.
- Treats ambiguous matches as missing instead of auto-remapping to a potentially wrong window.

### Pinned Tab Context Menu

Right-click any pinned tab to:

- See the current mapped window.
- Reassign the pin to another open window from the same app (`Reassign Window`).
- Keep the existing custom pin name while updating the underlying window identity.

## Requirements

- macOS
- Xcode with Swift 6 support

## Build and Run

### Xcode

1. Open `anchorTabs.xcodeproj`.
2. Select scheme `anchorTabs`.
3. Run on `My Mac`.

### CLI

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project anchorTabs.xcodeproj \
  -scheme anchorTabs \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## Accessibility Setup

AnchorTabs requires Accessibility permission to enumerate and focus windows.

1. Launch AnchorTabs.
2. Open macOS System Settings -> Privacy & Security -> Accessibility.
3. Enable `com.stevewalsh.AnchorTabs`.
4. If needed, use app actions:
   - `Open Accessibility Settings...`
   - `Enable Accessibility Access`
   - `Restart Window Polling`

## Usage

1. Click the menu bar pin icon to open the window manager popover.
2. In `Open Windows`, click a row title to focus that window.
3. Use the pin button to pin or unpin a window.
4. Click a pinned tab in the menu bar strip to focus its mapped window.
5. Right-click a pinned tab to rename, reassign, or unpin it.
6. Drag pinned tabs to reorder.
7. Use the `...` overflow menu when pin count exceeds visible capacity.

## Troubleshooting

### Accessibility appears disabled

- Open Accessibility settings from the app and verify permission is enabled.
- Use `Restart Window Polling`.
- If required, reset and re-grant permission:

```bash
tccutil reset Accessibility com.stevewalsh.AnchorTabs
```

### `xcodebuild` points to CommandLineTools

Use one of:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...
```

or:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Project Structure

- `anchorTabs/App/` app lifecycle, orchestration, and status item host
- `anchorTabs/Views/` menu bar strip and popover UI
- `anchorTabs/Stores/` window enumeration/focus, pin persistence, and matching
- `anchorTabs/Services/` accessibility permission integration
- `anchorTabs/Models/` window and diagnostics models
- `anchorTabs/Utilities/` string normalization and matching helpers
- `anchorTabsTests/` pin matching and store behavior tests

## Privacy

- No network dependency for core behavior.
- Pinned metadata, labels, and settings are stored locally in `UserDefaults`.

## Naming Notes

- Product name: `AnchorTabs`
- Target/scheme/source folders: `anchorTabs`
- Bundle identifier: `com.stevewalsh.AnchorTabs`
