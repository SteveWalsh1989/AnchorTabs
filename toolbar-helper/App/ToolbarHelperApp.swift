import SwiftUI

// App entry point that boots the status-item lifecycle via AppDelegate.
@main
struct ToolbarHelperApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  // Exposes only Settings because the main UI lives in the menu bar.
  var body: some Scene {
    Settings {
      SettingsView(model: appDelegate.model)
    }
  }
}
