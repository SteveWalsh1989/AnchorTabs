import AppKit
import Combine
import SwiftUI

// Hosts the SwiftUI strip inside an NSStatusItem and keeps width in sync.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let hostingView: NSHostingView<MenuBarStripView>
  private let model: AppModel
  private let windowManagerPopover = NSPopover()
  private let minimumLength: CGFloat = 70
  private let compactMinimumLength: CGFloat = 18
  private let lengthPadding: CGFloat = 10
  private let compactLengthPadding: CGFloat = 0
  private let launcherSectionWidth: CGFloat = 22
  private let launcherSectionTrailingPadding: CGFloat = 6
  private let lengthChangeThreshold: CGFloat = 1
  private let lengthUpdateDebounceMs = 100
  private var lastAppliedLength: CGFloat?
  private var isCompactMode = false
  private var isWindowManagerVisible = false
  private var cancellables: Set<AnyCancellable> = []

  // Creates the hosting view and binds status item sizing updates.
  init(model: AppModel) {
    self.model = model
    hostingView = NSHostingView(rootView: MenuBarStripView(model: model))
    super.init()
    configureWindowManagerPopover()
    installHostView()
    observeModel(model)
    updateLength()
  }

  private func configureWindowManagerPopover() {
    windowManagerPopover.behavior = .transient
    windowManagerPopover.animates = false
    windowManagerPopover.delegate = self
    windowManagerPopover.contentSize = NSSize(width: 400, height: 430)
  }

  // Installs the SwiftUI host as the status bar button content view.
  private func installHostView() {
    guard let button = statusItem.button else { return }

    button.title = ""
    button.image = nil
    button.addSubview(hostingView)
    hostingView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: button.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
    ])
  }

  // Listens for model changes so width can adapt to changing tab labels.
  private func observeModel(_ model: AppModel) {
    model.$isWindowManagerVisible
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isVisible in
        guard let self else { return }
        self.isWindowManagerVisible = isVisible
        if isVisible {
          self.showWindowManagerPopover()
        } else {
          self.hideWindowManagerPopover()
        }
        if !isVisible {
          self.updateLengthIfNeeded()
        }
      }
      .store(in: &cancellables)

    model.$hidesPinnedItemsInMenuBar
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isHidden in
        guard let self else { return }
        self.isCompactMode = isHidden
        self.updateLengthIfNeeded()
      }
      .store(in: &cancellables)

    let visibleTabLabels = Publishers.CombineLatest(model.$pinnedItems, model.$maxVisiblePinnedTabs)
      .map { pinnedItems, maxVisiblePinnedTabs in
        Array(pinnedItems.prefix(maxVisiblePinnedTabs)).map(\.tabLabel)
      }
      .removeDuplicates()

    Publishers.CombineLatest4(
      visibleTabLabels,
      model.$menuPinnedItemMinWidth.removeDuplicates(),
      model.$menuTrailingSpacing.removeDuplicates(),
      model.$isAccessibilityTrusted.removeDuplicates()
    )
      .combineLatest(model.$hidesPinnedItemsInMenuBar.removeDuplicates())
      .debounce(
        for: .milliseconds(lengthUpdateDebounceMs),
        scheduler: DispatchQueue.main
      )
      .sink { [weak self] _ in
        self?.updateLengthIfNeeded()
      }
      .store(in: &cancellables)
  }

  // Measures the hosting view and applies a safe minimum width.
  private func updateLength() {
    hostingView.layoutSubtreeIfNeeded()
    let fittingWidth = hostingView.fittingSize.width
    let desiredLength = max(effectiveMinimumLength, fittingWidth + effectiveLengthPadding)
    lastAppliedLength = desiredLength
    statusItem.length = desiredLength
  }

  // Avoids tiny width thrash that can make the strip visibly flicker.
  private func updateLengthIfNeeded() {
    hostingView.layoutSubtreeIfNeeded()
    let fittingWidth = hostingView.fittingSize.width
    let desiredLength = max(effectiveMinimumLength, fittingWidth + effectiveLengthPadding)
    if let lastAppliedLength, abs(lastAppliedLength - desiredLength) < lengthChangeThreshold {
      return
    }
    lastAppliedLength = desiredLength
    statusItem.length = desiredLength
  }

  private var effectiveMinimumLength: CGFloat {
    isCompactMode ? compactMinimumLength : minimumLength
  }

  private var effectiveLengthPadding: CGFloat {
    isCompactMode ? compactLengthPadding : lengthPadding
  }

  private func showWindowManagerPopover() {
    guard !windowManagerPopover.isShown else { return }
    guard let button = statusItem.button else {
      model.setWindowManagerVisibility(false)
      return
    }

    windowManagerPopover.contentViewController = NSHostingController(
      rootView: WindowManagerPopoverView(model: model)
    )

    let anchorCenterX = max(
      button.bounds.minX + 1,
      button.bounds.maxX - launcherSectionTrailingPadding - (launcherSectionWidth / 2)
    )
    let anchorRect = NSRect(
      x: anchorCenterX,
      y: button.bounds.minY,
      width: 1,
      height: button.bounds.height
    )
    windowManagerPopover.show(relativeTo: anchorRect, of: button, preferredEdge: .minY)
  }

  private func hideWindowManagerPopover() {
    guard windowManagerPopover.isShown else { return }
    windowManagerPopover.performClose(nil)
  }

  func popoverDidClose(_ notification: Notification) {
    model.setWindowManagerVisibility(false)
  }
}
