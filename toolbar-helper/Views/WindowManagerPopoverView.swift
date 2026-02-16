import SwiftUI

// Popover UI for browsing open windows and managing pin/rename actions.
struct WindowManagerPopoverView: View {
  @ObservedObject var model: AppModel
  @State private var isShowingLayoutSettings = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Open Windows")
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)

      Text("Click a window name to focus it. Use the pin icon to keep it in your strip.")
        .font(.caption)
        .foregroundStyle(.secondary)

      if !model.isAccessibilityTrusted {
        accessibilityWarning
      }

      if orderedWindows.isEmpty {
        Text("No eligible windows found")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 12)
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(orderedWindows) { window in
              let isPinned = model.isPinned(window: window)
              let rowLabel = displayLabel(for: window)
              WindowManagerWindowRow(
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
        .frame(maxHeight: 300)
      }

      Divider()

      HStack {
        Spacer()

        Button {
          withAnimation(.easeInOut(duration: 0.15)) {
            isShowingLayoutSettings.toggle()
          }
        } label: {
          Image(systemName: isShowingLayoutSettings ? "gearshape.fill" : "gearshape")
        }
        .buttonStyle(.plain)
        .help(isShowingLayoutSettings ? "Hide settings" : "Show settings")
      }
      .font(.system(size: 12))

      if isShowingLayoutSettings {
        layoutSettingsSection
      }
    }
    .padding(12)
    .frame(width: 400)
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

  // Inline expandable settings shown under the lower divider.
  private var layoutSettingsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Settings")
        .font(.headline)

      HStack(spacing: 8) {
        Button("Refresh Open Windows") {
          model.refreshWindowsNow()
        }

        Button("Restart Window Polling") {
          model.resetAccessibilitySession()
        }
      }
      .font(.system(size: 12))

      if !model.isAccessibilityTrusted {
        Button("Enable Accessibility Access") {
          model.requestAccessibilityPermission()
        }
        .font(.system(size: 12))
      }

      HStack(spacing: 8) {
        Button("Accessibility Settings…") {
          model.openAccessibilitySettings()
        }

        Button("Copy Diagnostics") {
          model.copyDiagnosticsToPasteboard()
        }
      }
      .font(.system(size: 12))

      Divider()

      numberInputSettingRow(
        title: "Spacing",
        description: "Adds gap between pinned items and the settings icon to move pinned items left.",
        value: $model.menuTrailingSpacing,
        range: AppModel.menuTrailingSpacingRange
      )

      numberInputSettingRow(
        title: "Pinned Item Min Width",
        description: "Sets the minimum width for each pinned tab in the menu bar strip.",
        value: $model.menuPinnedItemMinWidth,
        range: AppModel.menuPinnedItemMinWidthRange
      )

      HStack(spacing: 8) {
        Text("Highlight missing pinned windows")
          .font(.system(size: 12))
        Spacer()
        Toggle("", isOn: $model.highlightMissingPins)
          .labelsHidden()
      }

      HStack {
        Spacer()
        Button("Reset All Settings") {
          model.resetMenuLayoutSettingsToDefaults()
        }
        .font(.system(size: 12, weight: .semibold))
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.secondary.opacity(0.08))
    )
  }

  private func numberInputSettingRow(
    title: String,
    description: String,
    value: Binding<Double>,
    range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.headline)
      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(alignment: .center, spacing: 8) {
        TextField(
          "0",
          value: clampedRoundedBinding(value, range: range),
          format: .number.precision(.fractionLength(0))
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 100)

        Text("px (max \(Int(range.upperBound)))")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func clampedRoundedBinding(
    _ value: Binding<Double>,
    range: ClosedRange<Double>
  ) -> Binding<Double> {
    Binding(
      get: { value.wrappedValue },
      set: { newValue in
        value.wrappedValue = min(max(newValue.rounded(), range.lowerBound), range.upperBound)
      }
    )
  }
}

// Row used by the window popover list with pin, name, and rename affordances.
private struct WindowManagerWindowRow: View {
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
