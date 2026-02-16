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

      Spacer()
    }
    .padding(18)
    .frame(width: 420, height: 220)
  }
}
