import AppKit
import Combine
import Foundation

// App-level coordinator that binds permission, window, and pin stores.
@MainActor
final class AnchorTabsModel: ObservableObject {
  static let menuTrailingSpacingRange: ClosedRange<Double> = 0...5000
  static let menuPinnedItemMinWidthRange: ClosedRange<Double> = 0...5000
  private static let defaultMenuTrailingSpacing = 0.0
  private static let menuTrailingSpacingKey = "MenuStripTrailingSpacing.v2"
  private static let menuPinnedItemMinWidthKey = "MenuStripPinnedItemMinWidth.v2"
  private static let highlightMissingPinsKey = "HighlightMissingPins.v1"
  private static let highlightFocusedWindowKey = "HighlightFocusedWindow.v1"
  private static let hidePinnedItemsInMenuBarKey = "HidePinnedItemsInMenuBar.v1"

  @Published private(set) var windows: [WindowSnapshot] = []
  @Published private(set) var pinnedItems: [PinnedWindowItem] = []
  @Published private(set) var isAccessibilityTrusted = false
  @Published private(set) var maxVisiblePinnedTabs = 10
  @Published private(set) var focusedWindowRuntimeID: String?
  @Published private(set) var hidesPinnedItemsInMenuBar = false
  @Published private(set) var windowPopoverSettingsRequestID = 0

  // Controls whether missing pinned items are highlighted in red.
  @Published var highlightMissingPins = true {
    didSet {
      userDefaults.set(highlightMissingPins, forKey: Self.highlightMissingPinsKey)
    }
  }
  // Controls whether the currently focused pinned window gets a highlight marker.
  @Published var highlightFocusedWindow = true {
    didSet {
      userDefaults.set(highlightFocusedWindow, forKey: Self.highlightFocusedWindowKey)
    }
  }
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

  let permissionManager: AccessibilityPermissionService

  private let windowStore: OpenWindowsStore
  private let pinnedStore: PinnedWindowsStore
  private let userDefaults: UserDefaults
  private let iconCache = NSCache<NSString, NSImage>()
  private var cancellables: Set<AnyCancellable> = []
  @Published private(set) var isWindowPopoverVisible = false

  // Injects dependencies for testing and previews.
  init(
    permissionManager: AccessibilityPermissionService,
    pinnedStore: PinnedWindowsStore,
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
    if userDefaults.object(forKey: Self.highlightMissingPinsKey) == nil {
      highlightMissingPins = true
    } else {
      highlightMissingPins = userDefaults.bool(forKey: Self.highlightMissingPinsKey)
    }
    if userDefaults.object(forKey: Self.highlightFocusedWindowKey) == nil {
      highlightFocusedWindow = true
    } else {
      highlightFocusedWindow = userDefaults.bool(forKey: Self.highlightFocusedWindowKey)
    }
    if userDefaults.object(forKey: Self.hidePinnedItemsInMenuBarKey) == nil {
      hidesPinnedItemsInMenuBar = false
    } else {
      hidesPinnedItemsInMenuBar = userDefaults.bool(forKey: Self.hidePinnedItemsInMenuBarKey)
    }
    windowStore = OpenWindowsStore(permissionManager: permissionManager)
    bindStores()
  }

  // Creates production dependencies.
  convenience init() {
    self.init(
      permissionManager: AccessibilityPermissionService(),
      pinnedStore: PinnedWindowsStore(),
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
    updateWindowRefreshPolicy()
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
    windowStore.refreshWindowsNow(reason: .manual)
  }

  // Tracks popover visibility and reapplies the shared refresh policy.
  func setWindowPopoverVisibility(_ isVisible: Bool) {
    guard isWindowPopoverVisible != isVisible else { return }
    isWindowPopoverVisible = isVisible
    updateWindowRefreshPolicy()
  }

  // Toggles the window manager popover visibility.
  func toggleWindowPopoverVisibility() {
    setWindowPopoverVisibility(!isWindowPopoverVisible)
  }

  // Opens the popover directly in settings mode.
  func openWindowPopoverSettings() {
    windowPopoverSettingsRequestID += 1
    setWindowPopoverVisibility(true)
  }

  // Hides or shows pinned tabs in the menu bar strip while keeping the gear button visible.
  func setMenuBarPinnedItemsHidden(_ isHidden: Bool) {
    guard hidesPinnedItemsInMenuBar != isHidden else { return }
    hidesPinnedItemsInMenuBar = isHidden
    userDefaults.set(isHidden, forKey: Self.hidePinnedItemsInMenuBarKey)
    updateWindowRefreshPolicy()
  }

  // Toggles pinned tab visibility in the menu bar strip.
  func toggleMenuBarPinnedItemsHidden() {
    setMenuBarPinnedItemsHidden(!hidesPinnedItemsInMenuBar)
  }

  // Resets layout/highlight preferences to product defaults.
  func resetMenuLayoutSettingsToDefaults() {
    menuTrailingSpacing = 0
    menuPinnedItemMinWidth = 0
    highlightMissingPins = true
    highlightFocusedWindow = true
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

    if let saveButton = alert.buttons.first {
      textField.target = saveButton
      textField.action = #selector(NSButton.performClick(_:))
    }
    alert.window.initialFirstResponder = textField

    NSApp.activate(ignoringOtherApps: true)
    alert.window.makeFirstResponder(textField)
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
    _ = windowStore.focusWindow(runtimeID: runtimeID)
  }

  // Reassigns a pin to another live window while preserving its custom label.
  func reassignPinnedItem(_ item: PinnedWindowItem, to window: WindowSnapshot) {
    pinnedStore.reassignPin(pinID: item.id, to: window)
  }

  // Candidate windows for quick pin reassignment within the same app only.
  func reassignmentWindows(for item: PinnedWindowItem) -> [WindowSnapshot] {
    windows
      .filter { $0.bundleID == item.reference.bundleID }
      .sorted { lhs, rhs in
        if lhs.menuTitle != rhs.menuTitle {
          return lhs.menuTitle < rhs.menuTitle
        }
        return lhs.id < rhs.id
      }
  }

  // Human-readable description of the currently mapped window for a pinned item.
  func pinnedWindowMappingDescription(for item: PinnedWindowItem) -> String {
    if let window = item.window {
      return "\(window.title) — \(window.appName)"
    }
    return "Missing: \(item.reference.title) — \(item.reference.appName)"
  }

  // Focuses a live window selected from the open-windows list.
  func activateWindow(_ window: WindowSnapshot) {
    _ = windowStore.focusWindow(runtimeID: window.id)
  }

  // Returns true when a pinned item currently matches the focused runtime window.
  func isPinnedItemFocused(_ item: PinnedWindowItem) -> Bool {
    guard highlightFocusedWindow else { return false }
    guard let runtimeID = item.window?.id else { return false }
    return runtimeID == focusedWindowRuntimeID
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
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] isTrusted in
        self?.isAccessibilityTrusted = isTrusted
      }
      .store(in: &cancellables)

    windowStore.$windows
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] windows in
        guard let self else { return }
        self.windows = windows
        self.pinnedStore.reconcile(with: windows)
      }
      .store(in: &cancellables)

    windowStore.$focusedRuntimeID
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] focusedRuntimeID in
        self?.focusedWindowRuntimeID = focusedRuntimeID
      }
      .store(in: &cancellables)

    pinnedStore.$pinnedItems
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] pinnedItems in
        self?.pinnedItems = pinnedItems
      }
      .store(in: &cancellables)

    pinnedStore.$maxVisiblePinnedTabs
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] maxVisiblePinnedTabs in
        self?.maxVisiblePinnedTabs = maxVisiblePinnedTabs
      }
      .store(in: &cancellables)
  }

  // Applies the shared refresh policy for popover visibility and hidden-strip mode.
  private func updateWindowRefreshPolicy() {
    if isWindowPopoverVisible || hidesPinnedItemsInMenuBar {
      windowStore.pauseAutomaticRefreshing()
    } else {
      windowStore.resumeAutomaticRefreshing()
    }
  }

}
