import AppKit

// Owns app startup/shutdown and the status bar host controller.
@MainActor
final class AnchorTabsAppDelegate: NSObject, NSApplicationDelegate {
  let model = AnchorTabsModel()
  private var statusBarController: StatusItemController?

  // Starts the model and installs the custom menu bar strip.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    statusBarController = StatusItemController(model: model)
    model.start()
  }

  // Stops background polling before process exit.
  func applicationWillTerminate(_ notification: Notification) {
    model.stop()
  }
}
