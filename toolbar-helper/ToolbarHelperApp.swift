import SwiftUI

@main
struct ToolbarHelperApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView(model: appDelegate.model)
    }
  }
}
