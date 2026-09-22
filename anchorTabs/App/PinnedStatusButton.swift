import AppKit

@MainActor
final class PinnedStatusButton: NSObject {
  let pinID: UUID
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let model: AnchorTabsModel
  private let nativeItemChromeAdjustment: CGFloat = 8

  init(pin: PinnedWindowItem, model: AnchorTabsModel) {
    pinID = pin.id
    self.model = model
    super.init()
    statusItem.autosaveName = "AnchorTabs.Pin.\(pin.id.uuidString)"
    statusItem.button?.target = self
    statusItem.button?.action = #selector(handleClick)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    update(pin: pin)
  }

  func update(pin: PinnedWindowItem, trailingSpacing: CGFloat = 0) {
    guard let button = statusItem.button else { return }
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    var attributes: [NSAttributedString.Key: Any] = [.font: font]
    attributes[.foregroundColor] = NSColor.labelColor
    var underline: NSColor?
    if pin.isMissing && model.highlightMissingPins {
      underline = .systemRed
    } else if model.highlightFocusedWindow && model.isPinnedItemFocused(pin) {
      underline = NSColor(red: 0.69, green: 0.56, blue: 0.94, alpha: 1)
    }
    let title = NSAttributedString(string: pin.tabLabel, attributes: attributes)
    // Native status items add 16 points of chrome between items. Split that overhead across
    // adjacent tabs so the strip stays close to the previous six-point SwiftUI spacing.
    let width = max(
      24,
      max(model.menuPinnedItemMinWidth, ceil(title.size().width) + 20)
        - nativeItemChromeAdjustment
    )
    button.image = tabImage(
      title: title, width: width, trailingSpacing: trailingSpacing, underline: underline)
    button.toolTip = model.pinnedWindowMappingDescription(for: pin)
    button.setAccessibilityLabel(pin.tabLabel)
    statusItem.length = width + trailingSpacing
  }

  private func tabImage(
    title: NSAttributedString, width: CGFloat, trailingSpacing: CGFloat, underline: NSColor?
  ) -> NSImage {
    // Keep spacing inside the last native item so macOS cannot reorder it between tabs.
    NSImage(size: NSSize(width: width + trailingSpacing, height: 20), flipped: false) { _ in
      NSColor.controlBackgroundColor.setFill()
      NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: width, height: 20), xRadius: 7, yRadius: 7
      ).fill()
      let textSize = title.size()
      title.draw(at: NSPoint(x: (width - textSize.width) / 2, y: (20 - textSize.height) / 2))
      if let underline {
        underline.setFill()
        NSRect(x: 8, y: 1, width: width - 16, height: 1).fill()
      }
      return true
    }
  }

  @objc private func handleClick() {
    guard let pin = model.pinnedItems.first(where: { $0.id == pinID }) else { return }
    if let event = NSApp.currentEvent, event.type == .rightMouseUp {
      guard let button = statusItem.button else { return }
      NSMenu.popUpContextMenu(contextMenu(for: pin), with: event, for: button)
      return
    }
    model.activatePinnedItem(pin)
  }

  private func contextMenu(for pin: PinnedWindowItem) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let description = NSMenuItem(
      title: model.pinnedWindowMappingDescription(for: pin), action: nil, keyEquivalent: "")
    description.isEnabled = false
    menu.addItem(description)
    let reassignment = NSMenuItem(title: "Reassign Window", action: nil, keyEquivalent: "")
    let candidates = model.reassignmentWindows(for: pin)
    reassignment.isEnabled = !candidates.isEmpty
    let submenu = NSMenu()
    for window in candidates {
      let item = StatusActionMenuItem(title: window.menuTitle) { [weak model] in
        model?.reassignPinnedItem(pin, to: window)
      }
      item.state = window.id == pin.window?.id ? .on : .off
      submenu.addItem(item)
    }
    reassignment.submenu = submenu
    menu.addItem(reassignment)
    menu.addItem(.separator())
    menu.addItem(
      StatusActionMenuItem(title: "Rename…") { [weak model] in model?.promptRename(for: pin) })
    if pin.reference.customName?.isEmpty == false {
      menu.addItem(
        StatusActionMenuItem(title: "Reset Name") { [weak model] in
          model?.renamePin(pinID: pin.id, customName: nil)
        })
    }
    menu.addItem(
      StatusActionMenuItem(title: "Unpin") { [weak model] in model?.unpin(pinID: pin.id) })
    return menu
  }
}
