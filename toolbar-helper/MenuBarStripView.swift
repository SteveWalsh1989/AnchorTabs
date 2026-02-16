import SwiftUI

struct MenuBarStripView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    HStack(spacing: 6) {
      if model.isAccessibilityTrusted {
        if model.visiblePinnedItems.isEmpty {
          Text("No Pins")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.visiblePinnedItems) { pinnedItem in
            Button {
              model.activatePinnedItem(pinnedItem)
            } label: {
              Text(pinnedItem.tabLabel)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(TabButtonStyle(pinnedItem.isMissing ? .missing : .active))
            .help(tooltip(for: pinnedItem))
            .contextMenu {
              Button("Rename…") {
                model.promptRename(for: pinnedItem)
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
        }

        if !model.overflowPinnedItems.isEmpty {
          Menu {
            ForEach(model.overflowPinnedItems) { pinnedItem in
              Menu(pinnedItem.tabLabel) {
                Button("Focus Window") {
                  model.activatePinnedItem(pinnedItem)
                }
                .disabled(pinnedItem.isMissing)

                Button("Rename…") {
                  model.promptRename(for: pinnedItem)
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
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .help("Accessibility access is required to enumerate and focus windows")
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
        Menu("Settings") {
          settingsMenuSection
        }
      } label: {
        Image(systemName: "plus.circle.fill")
      }
      .menuStyle(.borderlessButton)
      .help("Pin / unpin open windows")
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .frame(minHeight: 24)
  }

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
            Button("Rename Toolbar Label…") {
              model.promptRename(for: pinnedItem)
            }

            if pinnedItem.reference.customName?.isEmpty == false {
              Button("Reset Custom Label") {
                model.renamePin(pinID: pinnedItem.id, customName: nil)
              }
            }
          } else {
            Button("Pin and Rename Toolbar Label…") {
              model.togglePin(for: window)
              if let newPinnedItem = model.pinnedItem(for: window) {
                model.promptRename(for: newPinnedItem)
              }
            }
          }
        } label: {
          openWindowMenuLabel(for: window, isPinned: isPinned)
        }
      }
    }
  }

  @ViewBuilder
  private var pinnedManagementSection: some View {
    Menu("Rename Pinned Items") {
      ForEach(model.pinnedItems) { pinnedItem in
        Button {
          model.promptRename(for: pinnedItem)
        } label: {
          Text(pinnedItem.tabLabel)
        }
      }
    }
  }

  @ViewBuilder
  private var settingsMenuSection: some View {
    Button("Restart Window Polling") {
      model.resetAccessibilitySession()
    }

    Button("Refresh Windows") {
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
  }

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

  private func tooltip(for item: PinnedWindowItem) -> String {
    if item.isMissing {
      return
        "Missing window: \(item.reference.title) (\(item.reference.appName)). Unpin or open a matching window."
    }

    return "Focus \(item.displayTitle) in \(item.displayAppName)"
  }
}

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
