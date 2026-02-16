import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var windows: [WindowSnapshot] = []
  @Published private(set) var pinnedItems: [PinnedWindowItem] = []
  @Published private(set) var isAccessibilityTrusted = false
  @Published private(set) var maxVisiblePinnedTabs = 10

  // Controls whether missing pinned items are highlighted in red.
  @Published var highlightMissingPins = false

  let permissionManager: AccessibilityPermissionManager

  private let windowStore: WindowStore
  private let pinnedStore: PinnedStore
  private let iconCache = NSCache<NSString, NSImage>()
  private var cancellables: Set<AnyCancellable> = []

  init(
    permissionManager: AccessibilityPermissionManager,
    pinnedStore: PinnedStore
  ) {
    self.permissionManager = permissionManager
    self.pinnedStore = pinnedStore
    windowStore = WindowStore(permissionManager: permissionManager)
    bindStores()
  }

  convenience init() {
    self.init(
      permissionManager: AccessibilityPermissionManager(),
      pinnedStore: PinnedStore()
    )
  }

  var visiblePinnedItems: [PinnedWindowItem] {
    Array(pinnedItems.prefix(maxVisiblePinnedTabs))
  }

  var overflowPinnedItems: [PinnedWindowItem] {
    Array(pinnedItems.dropFirst(maxVisiblePinnedTabs))
  }

  func start() {
    permissionManager.refreshStatus()
    windowStore.startPolling()
  }

  func stop() {
    windowStore.stopPolling()
  }

  func requestAccessibilityPermission() {
    permissionManager.requestPermissionPrompt()
  }

  func openAccessibilitySettings() {
    permissionManager.openAccessibilitySettings()
  }

  func refreshWindowsNow() {
    windowStore.refreshNow()
  }

  func resetAccessibilitySession() {
    permissionManager.refreshStatus()
    windowStore.stopPolling()
    windowStore.startPolling()
  }

  func togglePin(for window: WindowSnapshot) {
    pinnedStore.togglePin(for: window)
  }

  func unpin(pinID: UUID) {
    pinnedStore.unpin(pinID: pinID)
  }

  func renamePin(pinID: UUID, customName: String?) {
    pinnedStore.renamePin(pinID: pinID, customName: customName)
  }

  // Reorder pinned items using IndexSet (for SwiftUI's onMove)
  func movePinnedItem(from source: IndexSet, to destination: Int) {
    pinnedStore.movePinnedItem(from: source, to: destination)
  }

  // Reorder a specific pinned item before a target index (for drag-and-drop)
  func movePinnedItem(id: UUID, beforeIndex: Int?) {
    pinnedStore.movePinnedItem(id: id, beforeIndex: beforeIndex)
  }

  func promptRename(for pinnedItem: PinnedWindowItem) {
    let alert = NSAlert()
    alert.messageText = "Rename Pinned Item"
    alert.informativeText = "Set a custom label for this pinned window."
    alert.alertStyle = .informational

    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    if let existingCustomName = pinnedItem.reference.customName, !existingCustomName.isEmpty {
      textField.stringValue = existingCustomName
    } else {
      textField.stringValue = pinnedItem.displayAppName
    }
    alert.accessoryView = textField

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")

    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      renamePin(pinID: pinnedItem.id, customName: textField.stringValue)
    } else if response == .alertSecondButtonReturn {
      renamePin(pinID: pinnedItem.id, customName: nil)
    }
  }

  func removeAllMissingPins() {
    pinnedStore.removeAllMissingPins()
  }

  func isPinned(window: WindowSnapshot) -> Bool {
    pinnedStore.isPinned(window: window)
  }

  func pinnedItem(for window: WindowSnapshot) -> PinnedWindowItem? {
    pinnedStore.pinnedItem(for: window)
  }

  func activatePinnedItem(_ item: PinnedWindowItem) {
    guard let runtimeID = item.window?.id else { return }
    _ = windowStore.activateWindow(runtimeID: runtimeID)
  }

  func appIcon(for bundleID: String) -> NSImage? {
    if let cached = iconCache.object(forKey: bundleID as NSString) {
      return cached
    }

    guard
      let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleID
      }),
      let bundleURL = app.bundleURL
    else {
      return nil
    }

    let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
    icon.size = NSSize(width: 14, height: 14)
    iconCache.setObject(icon, forKey: bundleID as NSString)
    return icon
  }

  private func bindStores() {
    permissionManager.$isTrusted
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isTrusted in
        self?.isAccessibilityTrusted = isTrusted
      }
      .store(in: &cancellables)

    windowStore.$windows
      .receive(on: DispatchQueue.main)
      .sink { [weak self] windows in
        guard let self else { return }
        self.windows = windows
        self.pinnedStore.reconcile(with: windows)
      }
      .store(in: &cancellables)

    pinnedStore.$pinnedItems
      .receive(on: DispatchQueue.main)
      .sink { [weak self] pinnedItems in
        self?.pinnedItems = pinnedItems
      }
      .store(in: &cancellables)

    pinnedStore.$maxVisiblePinnedTabs
      .receive(on: DispatchQueue.main)
      .sink { [weak self] maxVisiblePinnedTabs in
        self?.maxVisiblePinnedTabs = maxVisiblePinnedTabs
      }
      .store(in: &cancellables)
  }
}
