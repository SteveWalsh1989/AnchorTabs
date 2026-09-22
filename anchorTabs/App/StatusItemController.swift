import AppKit
import Combine
import OSLog
import SwiftUI

// Keeps the native launcher independent from the resizable pinned-tab strip.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: 36)
  private let stripStatusItem = NSStatusBar.system.statusItem(
    withLength: NSStatusItem.variableLength)
  private let hostingView: NSHostingView<MenuBarView>
  private let model: AnchorTabsModel
  private var nativePins: PinnedStatusItems?
  private let windowPopover = NSPopover()
  private let minimumLength: CGFloat = 70
  private let lengthPadding: CGFloat = 10
  private let lengthChangeThreshold: CGFloat = 1
  private let lengthUpdateDebounceMs = 100
  private var lastAppliedLength: CGFloat?
  private let logger = Logger(subsystem: "com.stevewalsh.AnchorTabs", category: "MenuBarLayout")
  private var cancellables: Set<AnyCancellable> = []

  // Creates the hosting view and binds status item sizing updates.
  init(model: AnchorTabsModel) {
    self.model = model
    hostingView = NSHostingView(rootView: MenuBarView(model: model))
    super.init()
    configureWindowPopover()
    configureLauncher()
    if #available(macOS 27.0, *) {
      nativePins = PinnedStatusItems(model: model)
    }
    installHostView()
    observeModel(model)
    updateLength()
  }

  private func configureLauncher() {
    statusItem.autosaveName = "AnchorTabs.Launcher"
    statusItem.isVisible = true
    statusItem.button?.image = NSImage(
      systemSymbolName: "pin", accessibilityDescription: "AnchorTabs")
    statusItem.button?.toolTip = "Open AnchorTabs window manager"
    statusItem.button?.target = self
    statusItem.button?.action = #selector(toggleWindowPopover)
  }

  @objc private func toggleWindowPopover() {
    model.toggleWindowPopoverVisibility()
  }

  private func configureWindowPopover() {
    windowPopover.behavior = .transient
    windowPopover.animates = false
    windowPopover.delegate = self
    windowPopover.contentSize = NSSize(width: 300, height: 430)
  }

  // Installs the SwiftUI host through NSStatusItem's supported custom-view API.
  private func installHostView() {
    hostingView.frame = NSRect(
      x: 0,
      y: 0,
      width: minimumLength,
      height: NSStatusBar.system.thickness
    )
    hostingView.sizingOptions = [.intrinsicContentSize]
    stripStatusItem.autosaveName = "AnchorTabs.Pins"
    stripStatusItem.view = hostingView
  }

  // Listens for model changes so width can adapt to changing tab labels.
  private func observeModel(_ model: AnchorTabsModel) {
    model.$isWindowPopoverVisible
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isVisible in
        guard let self else { return }
        if isVisible {
          self.showWindowPopover()
        } else {
          self.hideWindowPopover()
        }
        if !isVisible {
          self.updateLengthIfNeeded()
        }
      }
      .store(in: &cancellables)

    model.objectWillChange
      .debounce(for: .milliseconds(lengthUpdateDebounceMs), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in self?.updateLengthIfNeeded() }
      .store(in: &cancellables)

    model.$focusedWindowRuntimeID
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.nativePins?.update() }
      .store(in: &cancellables)
  }

  // Measures the hosting view and applies a safe minimum width.
  private func updateLength() {
    updateLengthIfNeeded()
  }

  // Avoids tiny width thrash that can make the strip visibly flicker.
  private func updateLengthIfNeeded() {
    statusItem.button?.image = NSImage(
      systemSymbolName: model.isAccessibilityTrusted ? "pin" : "exclamationmark.triangle.fill",
      accessibilityDescription: "AnchorTabs")
    if let nativePins {
      stripStatusItem.isVisible = false
      nativePins.update()
      return
    }
    let showsPins =
      !model.hidesPinnedItemsInMenuBar && model.isAccessibilityTrusted && !model.pinnedItems.isEmpty
    stripStatusItem.isVisible = showsPins
    guard showsPins else { return }
    hostingView.invalidateIntrinsicContentSize()
    let fittingWidth = hostingView.fittingSize.width
    let desiredLength = max(minimumLength, fittingWidth + lengthPadding)
    if let lastAppliedLength, abs(lastAppliedLength - desiredLength) < lengthChangeThreshold {
      return
    }
    lastAppliedLength = desiredLength
    // Custom status-item views must resize with their allocated menu-bar space.
    hostingView.setFrameSize(NSSize(width: desiredLength, height: NSStatusBar.system.thickness))
    stripStatusItem.length = desiredLength
    logger.info(
      "Menu layout: measured=\(fittingWidth) allocated=\(desiredLength) pins=\(self.model.pinnedItems.count)"
    )
  }

  private func showWindowPopover() {
    guard !windowPopover.isShown else { return }
    guard let statusItemView = statusItem.button else {
      model.setWindowPopoverVisibility(false)
      return
    }

    windowPopover.contentViewController = NSHostingController(
      rootView: WindowPopoverView(model: model)
    )

    let anchorRect = NSRect(
      x: statusItemView.bounds.midX,
      y: statusItemView.bounds.minY,
      width: 1,
      height: statusItemView.bounds.height
    )
    windowPopover.show(relativeTo: anchorRect, of: statusItemView, preferredEdge: .minY)
  }

  private func hideWindowPopover() {
    guard windowPopover.isShown else { return }
    windowPopover.performClose(nil)
  }

  func popoverDidClose(_ notification: Notification) {
    model.setWindowPopoverVisibility(false)
  }
}
