import SwiftUI

// Minimal Settings scene for permission guidance in a menu bar-only app.
struct SettingsView: View {
  @ObservedObject var model: AppModel

  // Shows current Accessibility state and quick settings shortcuts.
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Toolbar Helper")
        .font(.title3.weight(.semibold))

      Text(
        "This is a menu bar app. Use the status bar strip to pin windows and quickly refocus them."
      )
      .foregroundStyle(.secondary)

      if model.isAccessibilityTrusted {
        Label("Accessibility access granted", systemImage: "checkmark.seal.fill")
          .foregroundStyle(.green)
      } else {
        Label("Accessibility access required", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Button("Request Accessibility Permission") {
          model.requestAccessibilityPermission()
        }
      }

      Button("Open Accessibility Settings") {
        model.openAccessibilitySettings()
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Spacing")
          .font(.headline)

        HStack(spacing: 10) {
          Slider(
            value: $model.menuTrailingSpacing,
            in: AppModel.menuTrailingSpacingRange,
            step: 2
          )
          Text("\(Int(model.menuTrailingSpacing)) px")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .frame(width: 58, alignment: .trailing)
        }

        Text("Adds gap between pinned items and the settings icon to move pinned items left.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Pinned Item Min Width")
          .font(.headline)

        HStack(spacing: 10) {
          Slider(
            value: $model.menuPinnedItemMinWidth,
            in: AppModel.menuPinnedItemMinWidthRange,
            step: 2
          )
          Text("\(Int(model.menuPinnedItemMinWidth)) px")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .frame(width: 58, alignment: .trailing)
        }

        Text("Sets the minimum width for each pinned tab in the menu bar strip.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(18)
    .frame(width: 420, height: 290)
  }
}
