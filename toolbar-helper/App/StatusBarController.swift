import AppKit
import Combine
import SwiftUI

// Hosts the SwiftUI strip inside an NSStatusItem and keeps width in sync.
@MainActor
final class StatusBarController {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let hostingView: NSHostingView<MenuBarStripView>
  private var cancellable: AnyCancellable?

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
    cancellable = model.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateLength()
      }
  }

  // Measures the hosting view and applies a safe minimum width.
  private func updateLength() {
    hostingView.layoutSubtreeIfNeeded()
    let fittingWidth = hostingView.fittingSize.width
    statusItem.length = max(70, fittingWidth + 10)
  }
}
