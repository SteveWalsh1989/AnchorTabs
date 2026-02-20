import AppKit
import SwiftUI

// Settings panel rendered inside WindowPopoverView when gear mode is enabled.
struct WindowPopoverSettingsView: View {
  @ObservedObject var model: AnchorTabsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      settingRow(
        title: "Spacing",
        description: "Gap before the gear icon."
      ) {
        numberInputControl(value: $model.menuTrailingSpacing, range: AnchorTabsModel.menuTrailingSpacingRange)
      }
      settingRow(
        title: "Pinned Item Min Width",
        description: "Minimum tab width."
      ) {
        numberInputControl(
          value: $model.menuPinnedItemMinWidth,
          range: AnchorTabsModel.menuPinnedItemMinWidthRange
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

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 8),
          GridItem(.flexible(), spacing: 8),
        ],
        spacing: 10
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

      Divider()

      HStack(spacing: 8) {
        settingsActionButton("Reset All Settings") {
          model.resetMenuLayoutSettingsToDefaults()
        }
        settingsActionButton("Quit AnchorTabs") {
          NSApplication.shared.terminate(nil)
        }
      }
      .font(.system(size: 12))
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
