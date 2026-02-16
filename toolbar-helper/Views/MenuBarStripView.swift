import SwiftUI

// Main menu bar strip UI with pinned tabs and one consolidated management menu.
struct MenuBarStripView: View {
  @ObservedObject var model: AppModel
  @State private var isShowingWindowManager = false

  private var effectiveTrailingSpacing: Double {
    model.isAccessibilityTrusted ? model.menuTrailingSpacing : 0
  }

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
            .buttonStyle(
              TabButtonStyle(
                pinnedItem.isMissing ? .missing : .active,
                minWidth: model.menuPinnedItemMinWidth,
                showsMissingUnderline: model.highlightMissingPins
              )
            )
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

      if effectiveTrailingSpacing > 0 {
        Color.clear
          .frame(width: effectiveTrailingSpacing, height: 1)
          .allowsHitTesting(false)
      }

      Button {
        isShowingWindowManager.toggle()
      } label: {
        Image(systemName: "gearshape.fill")
      }
      .buttonStyle(.plain)
      .help("Open window manager")
      .popover(
        isPresented: $isShowingWindowManager,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .top
      ) {
        WindowManagerPopoverView(model: model)
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .frame(minHeight: 24)
  }

  // Tooltip text for pinned tabs, including missing-state guidance.
  private func tooltip(for item: PinnedWindowItem) -> String {
    if item.isMissing {
      return
        "Missing window: \(item.reference.title) (\(item.reference.appName)). Unpin or open a matching window."
    }

    return "Focus \(item.displayTitle) in \(item.displayAppName)"
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
  let minWidth: Double
  let showsMissingUnderline: Bool

  init(_ kind: Kind, minWidth: Double = 0, showsMissingUnderline: Bool = true) {
    self.kind = kind
    self.minWidth = minWidth
    self.showsMissingUnderline = showsMissingUnderline
  }

  // Applies compact tab styling to status bar buttons.
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .frame(minWidth: minWidth, alignment: .center)
      .background(
        RoundedRectangle(cornerRadius: 7)
          .fill(backgroundColor.opacity(configuration.isPressed ? 0.6 : 1))
      )
      .foregroundStyle(foregroundColor)
      .overlay(alignment: .bottom) {
        if kind == .missing && showsMissingUnderline {
          Rectangle()
            .fill(Color.red.opacity(0.85))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.bottom, 1)
        }
      }
  }

  // Chooses background color by tab state.
  private var backgroundColor: Color {
    switch kind {
    case .active:
      Color(nsColor: .controlBackgroundColor)
    case .missing:
      Color(nsColor: .controlBackgroundColor)
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
      Color.primary
    case .warning:
      Color.orange
    case .active, .neutral:
      Color.primary
    }
  }
}
