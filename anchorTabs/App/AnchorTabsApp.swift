import SwiftUI

// App entry point that boots the status-item lifecycle via AnchorTabsAppDelegate.
@main
struct AnchorTabsApp: App {
  @NSApplicationDelegateAdaptor(AnchorTabsAppDelegate.self) private var appDelegate

  // Exposes only Settings because the main UI lives in the menu bar.
  var body: some Scene {
    Settings {
      AppSettingsView(model: appDelegate.model)
    }
  }
}
