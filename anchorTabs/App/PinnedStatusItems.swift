import AppKit

// Each pin owns a native status button because macOS 27 hosts status items outside the app.
@MainActor
final class PinnedStatusItems {
  private let overflow = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var buttons: [PinnedStatusButton] = []
  private let model: AnchorTabsModel

  init(model: AnchorTabsModel) {
    self.model = model
    overflow.autosaveName = "AnchorTabs.Overflow"
    overflow.button?.image = NSImage(
      systemSymbolName: "ellipsis.circle", accessibilityDescription: "More pinned windows")
    overflow.isVisible = false
  }

  func update() {
    let pins = model.visiblePinnedItems
    let isVisible = model.isAccessibilityTrusted && !model.hidesPinnedItemsInMenuBar
    let spacing = model.menuTrailingSpacing
    if buttons.map(\.pinID) != pins.map(\.id) {
      for button in buttons {
        NSStatusBar.system.removeStatusItem(button.statusItem)
      }
      // Status items are inserted to the left of the preceding item.
      buttons = pins.reversed().map { PinnedStatusButton(pin: $0, model: model) }.reversed()
    }

    for (button, pin) in zip(buttons, pins).reversed() {
      button.update(pin: pin, trailingSpacing: pin.id == pins.last?.id ? spacing : 0)
      button.statusItem.isVisible = isVisible
    }

    let menu = NSMenu()
    for pin in model.overflowPinnedItems {
      let item = StatusActionMenuItem(title: pin.tabLabel) { [weak model] in
        model?.activatePinnedItem(pin)
      }
      item.isEnabled = !pin.isMissing
      menu.addItem(item)
    }
    menu.autoenablesItems = false
    overflow.menu = menu
    overflow.isVisible = isVisible && !model.overflowPinnedItems.isEmpty
  }
}

// Menu items retain their actions without relying on a global responder-chain target.
nonisolated final class StatusActionMenuItem: NSMenuItem {
  private let handler: @MainActor () -> Void

  init(title: String, handler: @escaping @MainActor () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(performAction), keyEquivalent: "")
    target = self
  }

  required init(coder: NSCoder) {
    fatalError("StatusActionMenuItem is created programmatically")
  }

  @MainActor @objc private func performAction() {
    handler()
  }
}
