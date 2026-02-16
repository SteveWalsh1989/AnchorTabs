import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  private var statusBarController: StatusBarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    statusBarController = StatusBarController(model: model)
    model.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    model.stop()
  }
}
