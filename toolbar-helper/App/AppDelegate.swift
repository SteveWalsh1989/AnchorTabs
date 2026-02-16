import AppKit

// Owns app startup/shutdown and the status bar host controller.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  private var statusBarController: StatusBarController?

  // Starts the model and installs the custom menu bar strip.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    statusBarController = StatusBarController(model: model)
    model.start()
  }

  // Stops background polling before process exit.
  func applicationWillTerminate(_ notification: Notification) {
    model.stop()
  }
}
