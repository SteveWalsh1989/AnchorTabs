import AppKit

struct PinnedTabGeometry: Equatable {
  static let gap: CGFloat = 3

  let frames: [CGRect]
  let contentWidth: CGFloat
  let totalWidth: CGFloat

  init(widths: [CGFloat], trailingSpacing: CGFloat) {
    var nextX: CGFloat = 0
    frames = widths.enumerated().map { index, width in
      let frame = CGRect(x: nextX, y: 0, width: width, height: 20)
      nextX = frame.maxX + (index == widths.indices.last ? 0 : Self.gap)
      return frame
    }
    contentWidth = frames.last?.maxX ?? 0
    totalWidth = frames.isEmpty ? 0 : contentWidth + max(0, trailingSpacing)
  }

  func index(at point: CGPoint) -> Int? {
    frames.firstIndex { $0.contains(point) }
  }
}

// Uses one native status item so AppKit does not add chrome between pinned tabs.
@MainActor
final class PinnedStatusItems: NSObject {
  private struct TabLayout {
    let pinID: UUID
    let title: NSAttributedString
    let underline: NSColor?
    let frame: CGRect
  }

  private let overflow = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let spacer = NSStatusBar.system.statusItem(withLength: 0)
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let model: AnchorTabsModel
  private let existingPillWidthAdjustment: CGFloat = 8
  private var geometry = PinnedTabGeometry(widths: [], trailingSpacing: 0)
  private var tabLayouts: [TabLayout] = []

  init(model: AnchorTabsModel) {
    self.model = model
    super.init()
    overflow.autosaveName = "AnchorTabs.Overflow"
    overflow.button?.image = NSImage(
      systemSymbolName: "ellipsis.circle", accessibilityDescription: "More pinned windows")
    overflow.isVisible = false
    spacer.autosaveName = "AnchorTabs.TrailingSpacing.v3"
    spacer.button?.isEnabled = false
    spacer.isVisible = false
    statusItem.autosaveName = "AnchorTabs.NativePins.v3"
    statusItem.button?.target = self
    statusItem.button?.action = #selector(handleClick)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.imageScaling = .scaleNone
    (statusItem.button?.cell as? NSButtonCell)?.highlightsBy = []
    statusItem.isVisible = false
  }

  func update() {
    let pins = model.visiblePinnedItems
    let isVisible = model.isAccessibilityTrusted && !model.hidesPinnedItemsInMenuBar
    geometry = geometry(for: pins)
    tabLayouts = layouts(for: pins, frames: geometry.frames)

    if let button = statusItem.button {
      button.image = tabImage(for: tabLayouts, contentWidth: geometry.contentWidth)
      button.toolTip = "Pinned windows"
      button.setAccessibilityLabel(
        "Pinned windows: \(pins.map(\.tabLabel).joined(separator: ", "))")
    }
    statusItem.length = geometry.contentWidth
    statusItem.isVisible = isVisible && !pins.isEmpty

    let trailingSpacing = geometry.totalWidth - geometry.contentWidth
    spacer.length = trailingSpacing
    spacer.button?.image =
      trailingSpacing > 0 ? NSImage(size: NSSize(width: trailingSpacing, height: 1)) : nil
    spacer.isVisible = isVisible && !pins.isEmpty && trailingSpacing > 0

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

  private func geometry(for pins: [PinnedWindowItem]) -> PinnedTabGeometry {
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    let minimumWidth = CGFloat(model.menuPinnedItemMinWidth)
    let widths = pins.map { pin in
      let title = NSAttributedString(string: pin.tabLabel, attributes: [.font: font])
      return max(
        24,
        max(minimumWidth, ceil(title.size().width) + 20)
          - existingPillWidthAdjustment
      )
    }
    return PinnedTabGeometry(
      widths: widths,
      trailingSpacing: CGFloat(model.menuTrailingSpacing)
    )
  }

  private func layouts(for pins: [PinnedWindowItem], frames: [CGRect]) -> [TabLayout] {
    let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    return zip(pins, frames).map { pin, frame in
      let title = NSAttributedString(
        string: pin.tabLabel,
        attributes: [.font: font, .foregroundColor: NSColor.labelColor]
      )
      let underline: NSColor?
      if pin.isMissing && model.highlightMissingPins {
        underline = .systemRed
      } else if model.highlightFocusedWindow && model.isPinnedItemFocused(pin) {
        underline = NSColor(red: 0.69, green: 0.56, blue: 0.94, alpha: 1)
      } else {
        underline = nil
      }
      return TabLayout(pinID: pin.id, title: title, underline: underline, frame: frame)
    }
  }

  private func tabImage(for layouts: [TabLayout], contentWidth: CGFloat) -> NSImage? {
    guard !layouts.isEmpty else { return nil }
    return NSImage(size: NSSize(width: contentWidth, height: 20), flipped: false) { _ in
      for layout in layouts {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: layout.frame, xRadius: 7, yRadius: 7).fill()
        let textSize = layout.title.size()
        layout.title.draw(
          at: NSPoint(
            x: layout.frame.midX - (textSize.width / 2),
            y: layout.frame.midY - (textSize.height / 2)
          )
        )
        if let underline = layout.underline {
          underline.setFill()
          NSRect(x: layout.frame.minX + 8, y: 1, width: layout.frame.width - 16, height: 1)
            .fill()
        }
      }
      return true
    }
  }

  @objc private func handleClick() {
    guard
      let event = NSApp.currentEvent,
      let button = statusItem.button,
      let index = geometry.index(at: button.convert(event.locationInWindow, from: nil)),
      tabLayouts.indices.contains(index),
      let pin = model.pinnedItems.first(where: { $0.id == tabLayouts[index].pinID })
    else { return }

    if event.type == .rightMouseUp {
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
