import AppKit
import Combine
import Foundation

// App-level coordinator that binds permission, window, and pin stores.
@MainActor
final class AppModel: ObservableObject {
  static let menuTrailingSpacingRange: ClosedRange<Double> = 0...2500
  static let menuPinnedItemMinWidthRange: ClosedRange<Double> = 0...200
  private static let defaultMenuTrailingSpacing = 0.0
  private static let menuTrailingSpacingKey = "MenuStripTrailingSpacing.v1"
  private static let menuPinnedItemMinWidthKey = "MenuStripPinnedItemMinWidth.v1"

  @Published private(set) var windows: [WindowSnapshot] = []
  @Published private(set) var pinnedItems: [PinnedWindowItem] = []
  @Published private(set) var isAccessibilityTrusted = false
  @Published private(set) var maxVisiblePinnedTabs = 10
  @Published private(set) var windowDiagnostics = WindowStoreDiagnostics.empty
  @Published private(set) var pinnedDiagnostics = PinnedStoreDiagnostics.empty

  // Controls whether missing pinned items are highlighted in red.
  @Published var highlightMissingPins = false
  // Gap between pinned items and the gear icon, used to shift items left.
  @Published var menuTrailingSpacing = 0.0 {
    didSet {
      userDefaults.set(menuTrailingSpacing, forKey: Self.menuTrailingSpacingKey)
    }
  }
  // Minimum width applied to each pinned tab in the menu bar strip.
  @Published var menuPinnedItemMinWidth = 0.0 {
    didSet {
      userDefaults.set(menuPinnedItemMinWidth, forKey: Self.menuPinnedItemMinWidthKey)
    }
  }

  let permissionManager: AccessibilityPermissionManager

  private let windowStore: WindowStore
  private let pinnedStore: PinnedStore
  private let userDefaults: UserDefaults
  private let iconCache = NSCache<NSString, NSImage>()
  private var cancellables: Set<AnyCancellable> = []

  // Injects dependencies for testing and previews.
  init(
    permissionManager: AccessibilityPermissionManager,
    pinnedStore: PinnedStore,
    userDefaults: UserDefaults = .standard
  ) {
    self.permissionManager = permissionManager
    self.pinnedStore = pinnedStore
    self.userDefaults = userDefaults

    let storedMenuTrailingSpacing: Double
    if userDefaults.object(forKey: Self.menuTrailingSpacingKey) == nil {
      storedMenuTrailingSpacing = Self.defaultMenuTrailingSpacing
    } else {
      storedMenuTrailingSpacing = userDefaults.double(forKey: Self.menuTrailingSpacingKey)
    }

    menuTrailingSpacing = min(
      max(
        storedMenuTrailingSpacing,
        Self.menuTrailingSpacingRange.lowerBound),
      Self.menuTrailingSpacingRange.upperBound
    )
    menuPinnedItemMinWidth = min(
      max(
        userDefaults.double(forKey: Self.menuPinnedItemMinWidthKey),
        Self.menuPinnedItemMinWidthRange.lowerBound
      ),
      Self.menuPinnedItemMinWidthRange.upperBound
    )
    windowStore = WindowStore(permissionManager: permissionManager)
    bindStores()
  }

  // Creates production dependencies.
  convenience init() {
    self.init(
      permissionManager: AccessibilityPermissionManager(),
      pinnedStore: PinnedStore(),
      userDefaults: .standard
    )
  }

  // Pinned tabs shown directly in the strip.
  var visiblePinnedItems: [PinnedWindowItem] {
    Array(pinnedItems.prefix(maxVisiblePinnedTabs))
  }

  // Pinned tabs that overflow into the ellipsis menu.
  var overflowPinnedItems: [PinnedWindowItem] {
    Array(pinnedItems.dropFirst(maxVisiblePinnedTabs))
  }

  // Starts permission refresh and window tracking.
  func start() {
    permissionManager.refreshStatus()
    windowStore.startPolling()
  }

  // Stops background polling and observer work.
  func stop() {
    windowStore.stopPolling()
  }

  // Triggers the Accessibility permission prompt flow.
  func requestAccessibilityPermission() {
    permissionManager.requestPermissionPrompt()
  }

  // Opens System Settings directly to Accessibility controls.
  func openAccessibilitySettings() {
    permissionManager.openAccessibilitySettings()
  }

  // Forces an immediate AX window refresh.
  func refreshWindowsNow() {
    windowStore.refreshNow(reason: .manual)
  }

  // Rebuilds the AX session without clearing persisted pins.
  func resetAccessibilitySession() {
    permissionManager.refreshStatus()
    windowStore.stopPolling()
    windowStore.startPolling()
  }

  // Builds a copyable diagnostics report for bug triage.
  func diagnosticsReport() -> String {
    var lines: [String] = []
    lines.append("Toolbar Helper Diagnostics")
    lines.append("AX Trusted: \(windowDiagnostics.isTrusted ? "Yes" : "No")")
    lines.append("Open Windows: \(windowDiagnostics.windowCount)")
    lines.append("Pinned Items: \(pinnedDiagnostics.totalPins)")
    lines.append("Missing Pins: \(pinnedDiagnostics.missingPins)")

    if let reason = windowDiagnostics.lastRefreshReason?.rawValue {
      lines.append("Last Refresh Reason: \(reason)")
    } else {
      lines.append("Last Refresh Reason: N/A")
    }

    if let refreshedAt = windowDiagnostics.lastRefreshAt {
      let refreshedText = DateFormatter.localizedString(
        from: refreshedAt,
        dateStyle: .short,
        timeStyle: .medium
      )
      lines.append("Last Refresh At: \(refreshedText)")
    } else {
      lines.append("Last Refresh At: N/A")
    }

    return lines.joined(separator: "\n")
  }

  // Copies diagnostics report to the system pasteboard.
  func copyDiagnosticsToPasteboard() {
    let report = diagnosticsReport()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(report, forType: .string)
  }

  // Adds or removes a pin for a specific live window.
  func togglePin(for window: WindowSnapshot) {
    pinnedStore.togglePin(for: window)
  }

  // Removes a pin by id.
  func unpin(pinID: UUID) {
    pinnedStore.unpin(pinID: pinID)
  }

  // Saves or clears a custom display name for a pin.
  func renamePin(pinID: UUID, customName: String?) {
    pinnedStore.renamePin(pinID: pinID, customName: customName)
  }

  // Reorders pins from list-based drag move.
  func movePinnedItem(from source: IndexSet, to destination: Int) {
    pinnedStore.movePinnedItem(from: source, to: destination)
  }

  // Reorders a specific pin before a target index.
  func movePinnedItem(id: UUID, beforeIndex: Int?) {
    pinnedStore.movePinnedItem(id: id, beforeIndex: beforeIndex)
  }

  // Shows rename alert UI and applies save/reset actions.
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

  // Removes only pins that are currently unmatched.
  func removeAllMissingPins() {
    pinnedStore.removeAllMissingPins()
  }

  // Returns true when a live window is already pinned.
  func isPinned(window: WindowSnapshot) -> Bool {
    pinnedStore.isPinned(window: window)
  }

  // Returns pinned item metadata for a given live window.
  func pinnedItem(for window: WindowSnapshot) -> PinnedWindowItem? {
    pinnedStore.pinnedItem(for: window)
  }

  // Focuses the exact runtime window for a pinned item.
  func activatePinnedItem(_ item: PinnedWindowItem) {
    guard let runtimeID = item.window?.id else { return }
    _ = windowStore.activateWindow(runtimeID: runtimeID)
  }

  // Focuses a live window selected from the open-windows list.
  func activateWindow(_ window: WindowSnapshot) {
    _ = windowStore.activateWindow(runtimeID: window.id)
  }

  // Resolves and caches app icons for menu rows.
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

  // Wires store publishers into top-level observable properties.
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

    windowStore.$diagnostics
      .receive(on: DispatchQueue.main)
      .sink { [weak self] diagnostics in
        self?.windowDiagnostics = diagnostics
      }
      .store(in: &cancellables)

    pinnedStore.$pinnedItems
      .receive(on: DispatchQueue.main)
      .sink { [weak self] pinnedItems in
        self?.pinnedItems = pinnedItems
      }
      .store(in: &cancellables)

    pinnedStore.$diagnostics
      .receive(on: DispatchQueue.main)
      .sink { [weak self] diagnostics in
        self?.pinnedDiagnostics = diagnostics
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
