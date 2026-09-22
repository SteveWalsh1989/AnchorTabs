import AppKit
import Combine
import SwiftUI

// Popover UI for browsing open windows and managing pin/rename actions.
struct WindowPopoverView: View {
  @ObservedObject var model: AnchorTabsModel
  @State private var isShowingLayoutSettings = false
  private let accessibilityStateRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common)
    .autoconnect()
  private let popoverWidth: CGFloat = 300
  private let noAccessibilityPopoverHeight: CGFloat = 170
  private let openWindowsListMaxHeight: CGFloat = 430

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !model.isAccessibilityTrusted {
        HStack {
          Spacer()
          settingsToggleButton
        }
        .font(.system(size: 12))

        accessibilityPermissionSection
      } else if isShowingLayoutSettings {
        HStack {
          Spacer()
          hidePinnedItemsButton
          refreshButton
          settingsToggleButton
        }
        .font(.system(size: 12))

        WindowPopoverSettingsView(model: model)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        HStack {
          Text("AnchorTab")
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 8)
          Spacer()
          hidePinnedItemsButton
          refreshButton
          settingsToggleButton
        }
        .font(.system(size: 12))

        openWindowsSection
      }
    }
    .padding(12)
    .frame(
      width: popoverWidth,
      height: explicitPopoverHeight,
      alignment: .topLeading
    )
    .onReceive(accessibilityStateRefreshTimer) { _ in
      guard !model.isAccessibilityTrusted else { return }
      model.refreshWindowsNow()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      guard !model.isAccessibilityTrusted else { return }
      model.refreshWindowsNow()
    }
  }

  private var explicitPopoverHeight: CGFloat? {
    if !model.isAccessibilityTrusted {
      return noAccessibilityPopoverHeight
    }
    return nil
  }

  private var settingsToggleButton: some View {
    Button {
      isShowingLayoutSettings.toggle()
    } label: {
      Image(systemName: isShowingLayoutSettings ? "gearshape.fill" : "gearshape")
    }
    .buttonStyle(.plain)
    .help(isShowingLayoutSettings ? "Hide settings" : "Show settings")
  }

  private var refreshButton: some View {
    Button {
      model.refreshWindowsNow()
    } label: {
      Image(systemName: "arrow.clockwise")
    }
    .buttonStyle(.plain)
    .help("Refresh open windows")
  }

  private var hidePinnedItemsButton: some View {
    Button {
      model.toggleMenuBarPinnedItemsHidden()
    } label: {
      Image(systemName: model.hidesPinnedItemsInMenuBar ? "eye" : "eye.slash")
    }
    .buttonStyle(.plain)
    .help(
      model.hidesPinnedItemsInMenuBar
        ? "Show pinned items in menu bar"
        : "Hide pinned items in menu bar"
    )
  }

  // Guidance shown when Accessibility permission is currently unavailable.
  private var accessibilityPermissionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Accessibility access is required to list and focus windows.")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }

      Button {
        model.openAccessibilitySettings()
      } label: {
        Text("Open Accessibility Settings…")
          .font(.system(size: 13, weight: .semibold))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.orange.opacity(0.14))
    )
  }

  private var openWindowsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if model.pinnedItems.isEmpty && availableWindows.isEmpty {
        Text("No eligible windows found")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            if !model.pinnedItems.isEmpty {
              sectionHeader("Pinned")
              ForEach(model.pinnedItems) { pinnedItem in
                WindowPopoverPinnedRowView(
                  pinnedItem: pinnedItem,
                  mappingDescription: model.pinnedWindowMappingDescription(for: pinnedItem),
                  onFocus: { model.activatePinnedItem(pinnedItem) },
                  onRename: { model.promptRename(for: pinnedItem) },
                  onRemove: { model.unpin(pinID: pinnedItem.id) }
                )
              }
            }

            if !availableWindows.isEmpty {
              sectionHeader("Open Windows")
            }
            ForEach(availableWindows) { window in
              WindowPopoverWindowRowView(
                displayLabel: window.menuTitle,
                nameTooltip: window.menuTitle,
                onFocus: { model.activateWindow(window) },
                onTogglePin: { model.togglePin(for: window) }
              )
            }
          }
        }
        .frame(maxHeight: openWindowsListMaxHeight)
      }
    }
  }

  private var availableWindows: [WindowSnapshot] {
    model.windows.filter { !model.isPinned(window: $0) }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.top, 4)
  }
}

// Pinned rows remain present when their window is unavailable so they can always be managed.
private struct WindowPopoverPinnedRowView: View {
  let pinnedItem: PinnedWindowItem
  let mappingDescription: String
  let onFocus: () -> Void
  let onRename: () -> Void
  let onRemove: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 10) {
      Button {
        onRemove()
      } label: {
        Image(systemName: "pin.slash")
      }
      .buttonStyle(.plain)
      .foregroundStyle(Color.accentColor)
      .frame(width: 26, alignment: .center)
      .help("Remove pinned item")

      Button {
        onFocus()
      } label: {
        HStack(spacing: 5) {
          Text(truncated(pinnedItem.tabLabel, maxCharacters: 64))
            .lineLimit(1)
            .truncationMode(.tail)
          if pinnedItem.isMissing {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 9))
              .foregroundStyle(.orange)
          }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(mappingDescription)
      }
      .buttonStyle(.plain)
      .disabled(pinnedItem.isMissing)

      Button {
        onRename()
      } label: {
        Image(systemName: "pencil")
      }
      .buttonStyle(.plain)
      .frame(width: 26, alignment: .trailing)
      .opacity(isHovering ? 1 : 0.55)
      .help("Rename")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 7)
        .fill(isHovering ? Color.secondary.opacity(0.14) : Color.clear)
    )
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
  }

  private func truncated(_ text: String, maxCharacters: Int) -> String {
    guard maxCharacters > 1, text.count > maxCharacters else { return text }
    let endIndex = text.index(text.startIndex, offsetBy: maxCharacters - 1)
    return "\(text[..<endIndex])…"
  }
}

// Row used by the window popover list with pin and name affordances.
private struct WindowPopoverWindowRowView: View {
  let displayLabel: String
  let nameTooltip: String
  let onFocus: () -> Void
  let onTogglePin: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 10) {
      Button {
        onTogglePin()
      } label: {
        Image(systemName: "pin")
      }
      .buttonStyle(.plain)
      .foregroundStyle(Color.secondary)
      .frame(width: 26, alignment: .center)
      .help("Pin window")

      Button {
        onFocus()
      } label: {
        Text(truncated(displayLabel, maxCharacters: 64))
          .font(.system(size: 12))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
          .help(nameTooltip)
      }
      .buttonStyle(.plain)

      Color.clear
        .frame(width: 26, height: 14)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 7)
        .fill(isHovering ? Color.secondary.opacity(0.14) : Color.clear)
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovering = hovering
    }
  }

  // Applies a fixed character limit so labels stay compact in narrow popovers.
  private func truncated(_ text: String, maxCharacters: Int) -> String {
    guard maxCharacters > 1, text.count > maxCharacters else { return text }
    let endIndex = text.index(text.startIndex, offsetBy: maxCharacters - 1)
    return "\(text[..<endIndex])…"
  }
}
