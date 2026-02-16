import SwiftUI

// Popover UI for browsing open windows and managing pin/rename actions.
struct WindowManagerPopoverView: View {
  @ObservedObject var model: AppModel
  @State private var isShowingLayoutSettings = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if isShowingLayoutSettings {
        HStack {
          Spacer()
          settingsToggleButton
        }
        .font(.system(size: 12))

        layoutSettingsSection
      } else {
        HStack {
          Text("Open Windows")
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer()
          settingsToggleButton
        }
        .font(.system(size: 12))

        openWindowsSection
      }
    }
    .padding(12)
    .frame(width: 400)
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
    VStack(alignment: .leading, spacing: 8) {
      settingRow(
        title: "Spacing",
        description: "Gap before the gear icon."
      ) {
        numberInputControl(value: $model.menuTrailingSpacing, range: AppModel.menuTrailingSpacingRange)
      }
      settingRow(
        title: "Pinned Item Min Width",
        description: "Minimum tab width."
      ) {
        numberInputControl(
          value: $model.menuPinnedItemMinWidth,
          range: AppModel.menuPinnedItemMinWidthRange
        )
      }
      settingRow(
        title: "Highlight missing pinned windows",
        description: "Red underline when missing."
      ) {
        checkboxControl(isOn: $model.highlightMissingPins)
      }
      settingRow(
        title: "Highlight focused window",
        description: "Purple underline for active tab."
      ) {
        checkboxControl(isOn: $model.highlightFocusedWindow)
      }

      HStack {
        Spacer()
        Button("Reset All Settings") {
          model.resetMenuLayoutSettingsToDefaults()
        }
        .font(.system(size: 11, weight: .semibold))
      }
      .font(.system(size: 12))

      Divider()

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 8),
          GridItem(.flexible(), spacing: 8),
        ],
        spacing: 8
      ) {
        settingsActionButton("Refresh Open Windows") {
          model.refreshWindowsNow()
        }

        settingsActionButton("Restart Window Polling") {
          model.resetAccessibilitySession()
        }

        settingsActionButton("Accessibility Settings…") {
          model.openAccessibilitySettings()
        }

        settingsActionButton("Copy Diagnostics") {
          model.copyDiagnosticsToPasteboard()
        }
      }
      .font(.system(size: 12))

      if !model.isAccessibilityTrusted {
        Button("Enable Accessibility Access") {
          model.requestAccessibilityPermission()
        }
        .font(.system(size: 12))
      }
    }
  }

  private var openWindowsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
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
    }
  }

  private func settingRow<Control: View>(
    title: String,
    description: String,
    @ViewBuilder control: () -> Control
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
        Text(description)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      control()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func numberInputControl(
    value: Binding<Double>,
    range: ClosedRange<Double>
  ) -> some View {
    HStack(spacing: 8) {
      TextField(
        "0",
        value: clampedRoundedBinding(value, range: range),
        format: .number.precision(.fractionLength(0))
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 86)

      Text("px")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
  }

  private func checkboxControl(isOn: Binding<Bool>) -> some View {
    Toggle("", isOn: isOn)
      .labelsHidden()
      .toggleStyle(.checkbox)
  }

  private func settingsActionButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
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
