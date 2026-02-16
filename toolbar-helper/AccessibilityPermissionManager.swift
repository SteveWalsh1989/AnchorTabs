import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionManager: ObservableObject {
  @Published private(set) var isTrusted = AXIsProcessTrusted()
  private let promptOptionKey = "AXTrustedCheckOptionPrompt"

  func refreshStatus() {
    let options = [promptOptionKey: false] as CFDictionary
    isTrusted = AXIsProcessTrustedWithOptions(options)
  }

  func requestPermissionPrompt() {
    let options = [promptOptionKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    refreshStatus()
  }

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
