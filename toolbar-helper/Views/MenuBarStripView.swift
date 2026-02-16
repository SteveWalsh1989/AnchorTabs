import SwiftUI

// Main menu bar strip UI with pinned tabs and one consolidated management menu.
struct MenuBarStripView: View {
  @ObservedObject var model: AppModel

  // Renders pinned tabs plus one consolidated settings/menu button.
  var body: some View {
    HStack(spacing: 6) {
      if model.isAccessibilityTrusted {
        if model.visiblePinnedItems.isEmpty {
          Text("No Pins")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.visiblePinnedItems) { pinnedItem in
            let targetIndex = model.pinnedItems.firstIndex(where: { $0.id == pinnedItem.id })
            Button {
              model.activatePinnedItem(pinnedItem)
            } label: {
              Text(pinnedItem.tabLabel)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(TabButtonStyle(pinnedItem.isMissing ? .missing : .active))
            .help(tooltip(for: pinnedItem))
            .draggable(pinnedItem.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
              guard
                let draggedID = draggedPinID(from: items),
                draggedID != pinnedItem.id,
                let targetIndex
              else { return false }
              return reorderPinnedItem(draggedID: draggedID, beforeIndex: targetIndex)
            }
            .contextMenu {
              Button {
                model.promptRename(for: pinnedItem)
              } label: {
                Label("Rename…", systemImage: "pencil")
              }
              if pinnedItem.reference.customName?.isEmpty == false {
                Button("Reset Name") {
                  model.renamePin(pinID: pinnedItem.id, customName: nil)
                }
              }
              Button("Unpin") {
                model.unpin(pinID: pinnedItem.id)
              }
            }
          }

          Color.clear
            .frame(width: 8, height: 18)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
              guard let draggedID = draggedPinID(from: items) else { return false }
              return reorderPinnedItem(draggedID: draggedID, beforeIndex: nil)
            }
            .help("Drop to move tab to the end")
        }

        if !model.overflowPinnedItems.isEmpty {
          Menu {
            ForEach(model.overflowPinnedItems) { pinnedItem in
              Menu(pinnedItem.tabLabel) {
                Button("Focus Window") {
                  model.activatePinnedItem(pinnedItem)
                }
                .disabled(pinnedItem.isMissing)

                Button {
                  model.promptRename(for: pinnedItem)
                } label: {
                  Label("Rename…", systemImage: "pencil")
                }

                if pinnedItem.reference.customName?.isEmpty == false {
                  Button("Reset Name") {
                    model.renamePin(pinID: pinnedItem.id, customName: nil)
                  }
                }

                Button("Unpin") {
                  model.unpin(pinID: pinnedItem.id)
                }
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .menuStyle(.borderlessButton)
          .help("Overflow pinned windows")
        }
      } else {
        Button {
          model.openAccessibilitySettings()
        } label: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .help(
          "Accessibility access is required to enumerate and focus windows. Click to open Accessibility Settings."
        )
      }

      Menu {
        if model.isAccessibilityTrusted {
          windowsMenuSection
          if !model.pinnedItems.isEmpty {
            Divider()
            pinnedManagementSection
          }
        } else {
          accessibilityRequiredMenuSection
        }

        Divider()
        Menu {
          settingsMenuSection
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
      } label: {
        Image(systemName: "gearshape.fill")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .help("Open toolbar menu")
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .frame(minHeight: 24)
  }

  // Accessibility recovery actions shown when trust is missing.
  @ViewBuilder
  private var accessibilityRequiredMenuSection: some View {
    Text("Accessibility Required")
      .font(.headline)

    Text("Enable Toolbar Helper in Privacy & Security > Accessibility.")
      .foregroundStyle(.secondary)

    Button("Enable Accessibility Access") {
      model.requestAccessibilityPermission()
    }

    Button("Open Accessibility Settings…") {
      model.openAccessibilitySettings()
    }

    Button("Re-check Accessibility Status") {
      model.resetAccessibilitySession()
    }
  }

  // Lists open windows with per-window pin and rename actions.
  @ViewBuilder
  private var windowsMenuSection: some View {
    Text("Open Windows")
      .font(.headline)

    if model.windows.isEmpty {
      Text("No eligible windows found")
        .foregroundStyle(.secondary)
    } else {
      ForEach(model.windows) { window in
        let pinnedItem = model.pinnedItem(for: window)
        let isPinned = pinnedItem != nil

        Menu {
          Button(isPinned ? "Unpin Window" : "Pin Window") {
            model.togglePin(for: window)
          }

          if let pinnedItem {
            Button {
              model.promptRename(for: pinnedItem)
            } label: {
              Label("Rename Toolbar Label…", systemImage: "pencil")
            }

            if pinnedItem.reference.customName?.isEmpty == false {
              Button("Reset Custom Label") {
                model.renamePin(pinID: pinnedItem.id, customName: nil)
              }
            }
          } else {
            Button {
              model.togglePin(for: window)
              if let newPinnedItem = model.pinnedItem(for: window) {
                model.promptRename(for: newPinnedItem)
              }
            } label: {
              Label("Pin and Rename Toolbar Label…", systemImage: "pencil")
            }
          }
        } label: {
          openWindowMenuLabel(for: window, isPinned: isPinned)
        }
      }
    }
  }

  // Bulk rename shortcuts for existing pinned items.
  @ViewBuilder
  private var pinnedManagementSection: some View {
    Menu {
      ForEach(model.pinnedItems) { pinnedItem in
        Button {
          model.promptRename(for: pinnedItem)
        } label: {
          Label(pinnedItem.tabLabel, systemImage: "pencil")
        }
      }
    } label: {
      Label("Rename Pinned Items", systemImage: "pencil")
    }
  }

  // Maintenance actions available inside the Settings submenu.
  @ViewBuilder
  private var settingsMenuSection: some View {
    Button("Restart Window Polling") {
      model.resetAccessibilitySession()
    }

    Button("Refresh Open Windows") {
      model.refreshWindowsNow()
    }

    if !model.isAccessibilityTrusted {
      Button("Enable Accessibility Access") {
        model.requestAccessibilityPermission()
      }
    }

    Button("Accessibility Settings…") {
      model.openAccessibilitySettings()
    }

    Divider()
    diagnosticsMenuSection
  }

  // Runtime diagnostics view and copy-to-clipboard action.
  @ViewBuilder
  private var diagnosticsMenuSection: some View {
    Menu("Diagnostics") {
      Text("AX Trusted: \(model.windowDiagnostics.isTrusted ? "Yes" : "No")")
      Text("Open Windows: \(model.windowDiagnostics.windowCount)")
      Text("Pinned Items: \(model.pinnedDiagnostics.totalPins)")
      Text("Missing Pins: \(model.pinnedDiagnostics.missingPins)")
      Text("Last Refresh: \(diagnosticsDateText(model.windowDiagnostics.lastRefreshAt))")
      Text("Last Refresh Reason: \(model.windowDiagnostics.lastRefreshReason?.rawValue ?? "N/A")")

      Divider()
      Button("Copy Diagnostics") {
        model.copyDiagnosticsToPasteboard()
      }
    }
  }

  // Builds icon + title rows for the Open Windows menu.
  @ViewBuilder
  private func openWindowMenuLabel(for window: WindowSnapshot, isPinned: Bool) -> some View {
    let title = "\(isPinned ? "✓ " : "")\(window.menuTitle)"

    if let icon = model.appIcon(for: window.bundleID) {
      Label {
        Text(title)
          .lineLimit(1)
      } icon: {
        Image(nsImage: icon)
      }
    } else {
      Text(title)
    }
  }

  // Tooltip text for pinned tabs, including missing-state guidance.
  private func tooltip(for item: PinnedWindowItem) -> String {
    if item.isMissing {
      return
        "Missing window: \(item.reference.title) (\(item.reference.appName)). Unpin or open a matching window."
    }

    return "Focus \(item.displayTitle) in \(item.displayAppName)"
  }

  // Formats optional diagnostics timestamps.
  private func diagnosticsDateText(_ date: Date?) -> String {
    guard let date else { return "N/A" }
    return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium)
  }

  // Parses an internal drag payload into a pinned item UUID.
  private func draggedPinID(from items: [String]) -> UUID? {
    guard let rawID = items.first else { return nil }
    return UUID(uuidString: rawID)
  }

  // Reorders a dragged pin and returns true when a move was applied.
  private func reorderPinnedItem(draggedID: UUID, beforeIndex: Int?) -> Bool {
    guard let currentIndex = model.pinnedItems.firstIndex(where: { $0.id == draggedID }) else {
      return false
    }

    if let beforeIndex {
      let clampedIndex = max(0, min(beforeIndex, model.pinnedItems.count))
      if currentIndex == clampedIndex || currentIndex + 1 == clampedIndex {
        return false
      }
      model.movePinnedItem(id: draggedID, beforeIndex: clampedIndex)
      return true
    }

    if currentIndex == model.pinnedItems.count - 1 {
      return false
    }
    model.movePinnedItem(id: draggedID, beforeIndex: nil)
    return true
  }
}

// Shared tab visual styling for active and missing pinned items.
private struct TabButtonStyle: ButtonStyle {
  enum Kind {
    case active
    case missing
    case warning
    case neutral
  }

  let kind: Kind

  init(_ kind: Kind) {
    self.kind = kind
  }

  // Applies compact tab styling to status bar buttons.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 7)
          .fill(backgroundColor.opacity(configuration.isPressed ? 0.6 : 1))
      )
      .foregroundStyle(foregroundColor)
  }

  // Chooses background color by tab state.
  private var backgroundColor: Color {
    switch kind {
    case .active:
      Color(nsColor: .controlBackgroundColor)
    case .missing:
      Color.red.opacity(0.18)
    case .warning:
      Color.orange.opacity(0.22)
    case .neutral:
      Color(nsColor: .controlBackgroundColor)
    }
  }

  // Chooses foreground color by tab state.
  private var foregroundColor: Color {
    switch kind {
    case .missing:
      Color.red
    case .warning:
      Color.orange
    case .active, .neutral:
      Color.primary
    }
  }
}
