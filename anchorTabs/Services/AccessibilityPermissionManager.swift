import AppKit
import ApplicationServices
import Combine
import Foundation

// Wraps Accessibility trust checks, prompt requests, and settings deep-linking.
@MainActor
final class AccessibilityPermissionManager: ObservableObject {
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
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
