import AppKit
import SwiftUI

// Settings panel rendered inside WindowPopoverView when gear mode is enabled.
struct WindowPopoverSettingsView: View {
  @ObservedObject var model: AnchorTabsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      settingRow(title: "Spacing") {
        numberInputControl(value: $model.menuTrailingSpacing, range: AnchorTabsModel.menuTrailingSpacingRange)
      }
      settingRow(title: "Pinned Item Min Width") {
        numberInputControl(
          value: $model.menuPinnedItemMinWidth,
          range: AnchorTabsModel.menuPinnedItemMinWidthRange
        )
      }
      settingRow(title: "Highlight missing pinned windows") {
        checkboxControl(isOn: $model.highlightMissingPins)
      }
      settingRow(title: "Highlight focused window") {
        checkboxControl(isOn: $model.highlightFocusedWindow)
      }

      VStack(spacing: 10) {
        settingsActionButton("Accessibility Settings…") {
          model.openAccessibilitySettings()
        }

        settingsActionButton("Reset All Settings") {
          model.resetMenuLayoutSettingsToDefaults()
        }

        if !model.isAccessibilityTrusted {
          settingsActionButton("Enable Accessibility Access") {
            model.requestAccessibilityPermission()
          }
        }
      }
      .font(.system(size: 12))

      Divider()

      settingsActionButton("Quit AnchorTabs") {
        NSApplication.shared.terminate(nil)
      }
      .font(.system(size: 12))
    }
  }

  private func settingRow<Control: View>(
    title: String,
    @ViewBuilder control: () -> Control
  ) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
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
