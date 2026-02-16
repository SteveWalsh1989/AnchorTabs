import SwiftUI

// Popover UI for browsing open windows and managing pin/rename actions.
struct WindowManagerPopoverView: View {
  @ObservedObject var model: AppModel
  @State private var hoveredWindowLabel: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(hoveredWindowLabel ?? "Open Windows")
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)
        .help(hoveredWindowLabel ?? "Open windows")

      Text("Click a window name to focus it. Use the pin column to keep it in your strip.")
        .font(.caption)
        .foregroundStyle(.secondary)

      if !model.isAccessibilityTrusted {
        accessibilityWarning
      }

      columnHeader

      if model.windows.isEmpty {
        Text("No eligible windows found")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 12)
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(model.windows) { window in
              let isPinned = model.isPinned(window: window)
              WindowManagerWindowRow(
                displayLabel: displayLabel(for: window),
                fullLabel: fullLabel(for: window),
                isPinned: isPinned,
                onFocus: { model.activateWindow(window) },
                onTogglePin: { model.togglePin(for: window) },
                onRename: {
                  guard let pinnedItem = model.pinnedItem(for: window) else { return }
                  model.promptRename(for: pinnedItem)
                },
                onHoverChanged: { isHovering in
                  hoveredWindowLabel = isHovering ? fullLabel(for: window) : nil
                }
              )
            }
          }
        }
        .frame(maxHeight: 300)
      }

      Divider()

      HStack(spacing: 8) {
        Button("Refresh") {
          model.refreshWindowsNow()
        }

        Button("Restart Polling") {
          model.resetAccessibilitySession()
        }

        Spacer()

        Menu {
          if !model.isAccessibilityTrusted {
            Button("Enable Accessibility Access") {
              model.requestAccessibilityPermission()
            }
          }
          Button("Accessibility Settings…") {
            model.openAccessibilitySettings()
          }
          Divider()
          Button("Copy Diagnostics") {
            model.copyDiagnosticsToPasteboard()
          }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
      }
      .font(.system(size: 12))
    }
    .padding(12)
    .frame(width: 470)
  }

  // Guidance shown when Accessibility permission is currently unavailable.
  private var accessibilityWarning: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Accessibility access is required to list and focus windows.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Button("Open Accessibility Settings…") {
        model.openAccessibilitySettings()
      }
      .font(.caption)
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.orange.opacity(0.1))
    )
  }

  // Compact column labels for the row layout.
  private var columnHeader: some View {
    HStack(spacing: 10) {
      Text("Pin")
        .frame(width: 26, alignment: .center)
      Text("Window")
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("Rename")
        .frame(width: 46, alignment: .trailing)
    }
    .font(.caption2.weight(.semibold))
    .foregroundStyle(.secondary)
  }

  // Chooses row title, preferring a custom pinned label when one exists.
  private func displayLabel(for window: WindowSnapshot) -> String {
    guard let pinnedItem = model.pinnedItem(for: window) else { return window.menuTitle }
    let customName =
      pinnedItem.reference.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return customName.isEmpty ? window.menuTitle : customName
  }

  // Builds full hover text, keeping original app/title visible when renamed.
  private func fullLabel(for window: WindowSnapshot) -> String {
    guard let pinnedItem = model.pinnedItem(for: window) else { return window.menuTitle }
    let customName =
      pinnedItem.reference.customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !customName.isEmpty else { return window.menuTitle }
    return "\(customName) (\(window.menuTitle))"
  }
}

// Row used by the window popover list with pin, name, and rename affordances.
private struct WindowManagerWindowRow: View {
  let displayLabel: String
  let fullLabel: String
  let isPinned: Bool
  let onFocus: () -> Void
  let onTogglePin: () -> Void
  let onRename: () -> Void
  let onHoverChanged: (Bool) -> Void

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
      }
      .buttonStyle(.plain)
      .help(fullLabel)

      if isPinned {
        Button {
          onRename()
        } label: {
          Image(systemName: "pencil")
        }
        .buttonStyle(.plain)
        .frame(width: 46, alignment: .trailing)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .help("Rename pinned label")
      } else {
        Color.clear
          .frame(width: 46, height: 14)
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
      onHoverChanged(hovering)
    }
  }

  // Applies a fixed character limit so labels stay compact in narrow popovers.
  private func truncated(_ text: String, maxCharacters: Int) -> String {
    guard maxCharacters > 1, text.count > maxCharacters else { return text }
    let endIndex = text.index(text.startIndex, offsetBy: maxCharacters - 1)
    return "\(text[..<endIndex])…"
  }
}
