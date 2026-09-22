import AppKit
import SwiftUI

// Uses AppKit's target/action path so status-bar clicks remain reliable across macOS versions.
struct AccessibilityWarningButton: NSViewRepresentable {
  let action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeNSView(context: Context) -> NSButton {
    let image = NSImage(
      systemSymbolName: "exclamationmark.triangle.fill",
      accessibilityDescription: "Accessibility permission required"
    )
    let button = NSButton(
      image: image ?? NSImage(), target: context.coordinator,
      action: #selector(Coordinator.performAction))
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.contentTintColor = .systemOrange
    button.toolTip =
      "Accessibility access is required to enumerate and focus windows. Click to open Accessibility Settings."
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.action = action
  }

  @MainActor
  final class Coordinator: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc func performAction() {
      action()
    }
  }
}
