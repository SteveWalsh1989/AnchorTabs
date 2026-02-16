import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let hostingView: NSHostingView<MenuBarStripView>
  private var cancellable: AnyCancellable?

  init(model: AppModel) {
    hostingView = NSHostingView(rootView: MenuBarStripView(model: model))
    installHostView()
    observeModel(model)
    updateLength()
  }

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

  private func observeModel(_ model: AppModel) {
    cancellable = model.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateLength()
      }
  }

  private func updateLength() {
    hostingView.layoutSubtreeIfNeeded()
    let fittingWidth = hostingView.fittingSize.width
    statusItem.length = max(70, fittingWidth + 10)
  }
}
