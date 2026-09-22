import AppKit

// Renders all tabs inside one native status button so their visual gap stays under app control.
@MainActor
final class PinnedStatusItems: NSObject {
  private struct TabLayout {
    let pinID: UUID
    let title: NSAttributedString
    let width: CGFloat
    let underline: NSColor?
    let frame: NSRect
  }

  private let spacer = NSStatusBar.system.statusItem(withLength: 0)
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let overflow = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let model: AnchorTabsModel
  private let tabGap: CGFloat = 3
  private var tabLayouts: [TabLayout] = []

  init(model: AnchorTabsModel) {
    self.model = model
    super.init()
    spacer.autosaveName = "AnchorTabs.Spacing.v2"
    statusItem.autosaveName = "AnchorTabs.NativePins"
    statusItem.button?.target = self
    statusItem.button?.action = #selector(handleClick)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.imageScaling = .scaleNone
    (statusItem.button?.cell as? NSButtonCell)?.highlightsBy = []
    overflow.autosaveName = "AnchorTabs.Overflow"
    overflow.button?.image = NSImage(
      systemSymbolName: "ellipsis.circle", accessibilityDescription: "More pinned windows")
    update()
  }

  func update() {
    let pins = model.visiblePinnedItems
    let isVisible = model.isAccessibilityTrusted && !model.hidesPinnedItemsInMenuBar
    tabLayouts = layouts(for: pins)

    if let button = statusItem.button {
      button.image = tabImage(for: tabLayouts)
      button.toolTip = "Pinned windows"
      button.setAccessibilityLabel(
        "Pinned windows: \(pins.map(\.tabLabel).joined(separator: ", "))")
    }
    statusItem.length = stripWidth
    statusItem.isVisible = isVisible && !pins.isEmpty

    let spacing = model.menuTrailingSpacing
    spacer.length = spacing
    spacer.button?.image = spacing > 0 ? NSImage(size: NSSize(width: spacing, height: 1)) : nil
    spacer.isVisible = isVisible && !pins.isEmpty && spacing > 0

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

  private var stripWidth: CGFloat {
    tabLayouts.last?.frame.maxX ?? 0
  }

  private func layouts(for pins: [PinnedWindowItem]) -> [TabLayout] {
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    var currentX: CGFloat = 0
    return pins.map { pin in
      let title = NSAttributedString(
        string: pin.tabLabel,
        attributes: [.font: font, .foregroundColor: NSColor.labelColor]
      )
      let width = max(model.menuPinnedItemMinWidth, ceil(title.size().width) + 20)
      let underline: NSColor?
      if pin.isMissing && model.highlightMissingPins {
        underline = .systemRed
      } else if model.highlightFocusedWindow && model.isPinnedItemFocused(pin) {
        underline = NSColor(red: 0.69, green: 0.56, blue: 0.94, alpha: 1)
      } else {
        underline = nil
      }
      let frame = NSRect(x: currentX, y: 0, width: width, height: 20)
      currentX = frame.maxX + tabGap
      return TabLayout(
        pinID: pin.id, title: title, width: width, underline: underline, frame: frame)
    }
  }

  private func tabImage(for layouts: [TabLayout]) -> NSImage? {
    guard let lastLayout = layouts.last else { return nil }
    return NSImage(size: NSSize(width: lastLayout.frame.maxX, height: 20), flipped: false) { _ in
      for layout in layouts {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: layout.frame, xRadius: 7, yRadius: 7).fill()
        let textSize = layout.title.size()
        layout.title.draw(
          at: NSPoint(
            x: layout.frame.minX + (layout.width - textSize.width) / 2,
            y: (layout.frame.height - textSize.height) / 2
          )
        )
        if let underline = layout.underline {
          underline.setFill()
          NSRect(x: layout.frame.minX + 8, y: 1, width: layout.width - 16, height: 1).fill()
        }
      }
      return true
    }
  }

  @objc private func handleClick() {
    guard
      let event = NSApp.currentEvent,
      let button = statusItem.button,
      let layout = tabLayout(at: button.convert(event.locationInWindow, from: nil)),
      let pin = model.pinnedItems.first(where: { $0.id == layout.pinID })
    else { return }

    if event.type == .rightMouseUp {
      NSMenu.popUpContextMenu(contextMenu(for: pin), with: event, for: button)
    } else {
      model.activatePinnedItem(pin)
    }
  }

  private func tabLayout(at point: NSPoint) -> TabLayout? {
    tabLayouts.first { $0.frame.contains(point) }
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
