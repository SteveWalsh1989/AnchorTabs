import AppKit
import Combine
import SwiftUI

// Hosts the SwiftUI strip inside an NSStatusItem and keeps width in sync.
@MainActor
final class StatusBarController {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let hostingView: NSHostingView<MenuBarStripView>
  private let minimumLength: CGFloat = 70
  private let lengthPadding: CGFloat = 10
  private let lengthChangeThreshold: CGFloat = 1
  private let lengthUpdateDebounceMs = 100
  private var lastAppliedLength: CGFloat?
  private var cancellables: Set<AnyCancellable> = []

  // Creates the hosting view and binds status item sizing updates.
  init(model: AppModel) {
    hostingView = NSHostingView(rootView: MenuBarStripView(model: model))
    installHostView()
    observeModel(model)
    updateLength()
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
    let desiredLength = max(minimumLength, fittingWidth + lengthPadding)
    lastAppliedLength = desiredLength
    statusItem.length = desiredLength
  }

  // Avoids tiny width thrash that can make the strip visibly flicker.
  private func updateLengthIfNeeded() {
    hostingView.layoutSubtreeIfNeeded()
    let fittingWidth = hostingView.fittingSize.width
    let desiredLength = max(minimumLength, fittingWidth + lengthPadding)
    if let lastAppliedLength, abs(lastAppliedLength - desiredLength) < lengthChangeThreshold {
      return
    }
    lastAppliedLength = desiredLength
    statusItem.length = desiredLength
  }
}
