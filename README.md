# AnchorTabs (macOS)

AnchorTabs is a macOS menu bar app for pinning specific windows and restoring the exact window with one click.

It is designed for heavy multi-window workflows (for example, multiple Cursor workspaces or multiple Chrome windows) to easily pin, rename, and select opened windows to avoid needing to swipe up or use the ALT TAB and go through a list of applications you dont need to cycle through

This app was built using the assistance of AI, specifically Codex. 


#### How pinned items can appear on the menubar
<img width="1137" height="35" alt="image" src="https://github.com/user-attachments/assets/70c6dc13-5cc8-4cb0-bd0c-c7ae6ffa0235" />


Popover for pinning items | additional settings 
---|---
<img width="414" height="428" alt="image" src="https://github.com/user-attachments/assets/2405f666-3c84-4182-b68a-1cf3b6312eeb" /> | <img width="419" height="425" alt="image" src="https://github.com/user-attachments/assets/796a0d29-617e-41d7-a1f6-2481bf48fb6b" />

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


## FAQ

#### Why make it
- Personally I never found the ALT TAB or ALT SHIFT TAB or swipe up to be a good way of switching for active windows, especially if just switching often between a few of the opened windows
- This allows you to select a few windows for quick access on the menu bar, this means no more leaving a small section overlapping or having windows different heights to try move quickly or using swipe and then figuring out which window is which.
- You can add spacing so can position to the center of the screen, great for ultrawide monitors

#### Why is it not on app store
- I built this for myself as I use an ultrawide and this solves a workflow annoyance of mine but i wanted to share incase others find it useless but I don't want to pay to put it on the app store or have to conform to all of Apples requirements for apps there.

#### Are there going to be updates/ bug fixes
- Will depend on what issues might arise. Im not committing to making any updates

#### Are there known issues
- Yes, changing the spacing sometimes moves the popover around
- It wont refresh when popover is open, there is manual button for it though as the auto refresh looked glitchy
- For single instance windows, they often show when changing mac window if you use muttiple workspaces. Thats why there is a show/hide option on the popover 

