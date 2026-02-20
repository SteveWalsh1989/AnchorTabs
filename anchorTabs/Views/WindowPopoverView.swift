import AppKit
import Combine
import SwiftUI

// Popover UI for browsing open windows and managing pin/rename actions.
struct WindowPopoverView: View {
  @ObservedObject var model: AnchorTabsModel
  @State private var isShowingLayoutSettings = false
  private let accessibilityStateRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common)
    .autoconnect()
  private let popoverWidth: CGFloat = 340
  private let noAccessibilityPopoverHeight: CGFloat = 170
  private let settingsPopoverHeight: CGFloat = 430
  private let openWindowsRowsBeforeScroll = 8
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
      } else {
        HStack {
          Text("AnchorTab")
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 44)
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
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in
      guard !model.isAccessibilityTrusted else { return }
      model.refreshWindowsNow()
    }
  }

  private var explicitPopoverHeight: CGFloat? {
    if !model.isAccessibilityTrusted {
      return noAccessibilityPopoverHeight
    }
    if isShowingLayoutSettings {
      return settingsPopoverHeight
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

  // Returns windows with currently pinned items first, preserving pin order.
  private var orderedWindows: [WindowSnapshot] {
    var pinnedRank: [String: Int] = [:]
    for (index, runtimeID) in model.pinnedItems.compactMap({ $0.window?.id }).enumerated() {
      if pinnedRank[runtimeID] == nil {
        pinnedRank[runtimeID] = index
      }
    }

    return model.windows.enumerated()
      .sorted { lhs, rhs in
        let leftRank = pinnedRank[lhs.element.id]
        let rightRank = pinnedRank[rhs.element.id]

        switch (leftRank, rightRank) {
        case (let left?, let right?):
          if left != right {
            return left < right
          }
        case (.some, .none):
          return true
        case (.none, .some):
          return false
        case (.none, .none):
          break
        }

        return lhs.offset < rhs.offset
      }
      .map(\.element)
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

  // Chooses row title, preferring a custom pinned label when one exists.
  private func displayLabel(for window: WindowSnapshot) -> String {
    guard let pinnedItem = model.pinnedItem(for: window) else { return window.menuTitle }
    let customName =
      pinnedItem.reference.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return customName.isEmpty ? window.menuTitle : customName
  }

  // Returns expanded details for renamed pins to show in an info tooltip.
  private func renamedWindowTooltip(for window: WindowSnapshot) -> String? {
    guard let pinnedItem = model.pinnedItem(for: window) else { return nil }
    let customName =
      pinnedItem.reference.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !customName.isEmpty else { return nil }
    return "Renamed from: \(window.menuTitle)"
  }

  private var openWindowsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if orderedWindows.isEmpty {
        Text("No eligible windows found")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if orderedWindows.count <= openWindowsRowsBeforeScroll {
        LazyVStack(spacing: 4) {
          ForEach(orderedWindows) { window in
            let isPinned = model.isPinned(window: window)
            let rowLabel = displayLabel(for: window)
            WindowPopoverWindowRowView(
              displayLabel: rowLabel,
              nameTooltip: rowLabel,
              renameInfoTooltip: renamedWindowTooltip(for: window),
              isPinned: isPinned,
              onFocus: { model.activateWindow(window) },
              onTogglePin: { model.togglePin(for: window) },
              onRename: {
                guard let pinnedItem = model.pinnedItem(for: window) else { return }
                model.promptRename(for: pinnedItem)
              }
            )
          }
        }
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(orderedWindows) { window in
              let isPinned = model.isPinned(window: window)
              let rowLabel = displayLabel(for: window)
              WindowPopoverWindowRowView(
                displayLabel: rowLabel,
                nameTooltip: rowLabel,
                renameInfoTooltip: renamedWindowTooltip(for: window),
                isPinned: isPinned,
                onFocus: { model.activateWindow(window) },
                onTogglePin: { model.togglePin(for: window) },
                onRename: {
                  guard let pinnedItem = model.pinnedItem(for: window) else { return }
                  model.promptRename(for: pinnedItem)
                }
              )
            }
          }
        }
        .frame(maxHeight: openWindowsListMaxHeight)
      }
    }
  }

}

// Row used by the window popover list with pin, name, and rename affordances.
private struct WindowPopoverWindowRowView: View {
  let displayLabel: String
  let nameTooltip: String
  let renameInfoTooltip: String?
  let isPinned: Bool
  let onFocus: () -> Void
  let onTogglePin: () -> Void
  let onRename: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 10) {
      Button {
        onTogglePin()
      } label: {
        Image(systemName: isPinned ? "pin.fill" : "pin")
      }
      .buttonStyle(.plain)
      .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
      .frame(width: 26, alignment: .center)
      .help(isPinned ? "Unpin window" : "Pin window")

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

      if let renameInfoTooltip, isHovering {
        Image(systemName: "info.circle")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .frame(width: 14, alignment: .center)
          .help(renameInfoTooltip)
      } else {
        Color.clear
          .frame(width: 14, height: 14)
      }

      if isPinned {
        Button {
          onRename()
        } label: {
          Image(systemName: "pencil")
        }
        .buttonStyle(.plain)
        .frame(width: 26, alignment: .trailing)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .help("Rename")
      } else {
        Color.clear
          .frame(width: 26, height: 14)
      }
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
