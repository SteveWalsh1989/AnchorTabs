import AppKit
import ApplicationServices
import Combine
import Foundation

// Wraps Accessibility trust checks, prompt requests, and settings deep-linking.
@MainActor
final class AccessibilityPermissionService: ObservableObject {
  @Published private(set) var isTrusted = AXIsProcessTrusted()
  private let promptOptionKey = "AXTrustedCheckOptionPrompt"

  // Refreshes trust state without triggering the system prompt.
  func refreshStatus() {
    let options = [promptOptionKey: false] as CFDictionary
    isTrusted = AXIsProcessTrustedWithOptions(options)
  }

  // Requests system Accessibility prompt and immediately re-reads trust.
  func requestPermissionPrompt() {
    let options = [promptOptionKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    refreshStatus()
  }

  // Opens macOS Privacy > Accessibility directly for this app.
  func openAccessibilitySettings() {
    requestPermissionPrompt()

    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else {
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open(url, configuration: configuration) { application, error in
      if let error {
        NSLog("Failed to open Accessibility Settings: %@", error.localizedDescription)
        return
      }
      application?.activate(options: [.activateAllWindows])
    }
  }
}
