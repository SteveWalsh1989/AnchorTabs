import AppKit
import ApplicationServices
import Combine
import Foundation

private let windowStoreAXObserverEventNotification = Notification.Name(
  "ToolbarHelper.WindowStoreAXObserverEvent"
)

private let windowStoreAXObserverCallback: AXObserverCallback = { _, _, _, _ in
  NotificationCenter.default.post(name: windowStoreAXObserverEventNotification, object: nil)
}

// Enumerates AX windows, focuses windows, and tracks observer/polling diagnostics.
@MainActor
final class WindowStore: ObservableObject {
  @Published private(set) var windows: [WindowSnapshot] = []
  @Published private(set) var focusedRuntimeID: String?
  @Published private(set) var diagnostics = WindowStoreDiagnostics.empty

  private struct AXObserverRegistration {
    let observer: AXObserver
    let appElement: AXUIElement
  }

  private let permissionManager: AccessibilityPermissionManager
  private let observerCapablePollingInterval: TimeInterval = 3.0
  private let fallbackPollingInterval: TimeInterval = 2.0
  private let observerRefreshDebounceInterval: TimeInterval = 0.4
  private let observedAppNotifications: [CFString] = [
    kAXWindowCreatedNotification as CFString,
    kAXFocusedWindowChangedNotification as CFString,
    kAXMainWindowChangedNotification as CFString,
    kAXApplicationActivatedNotification as CFString,
    kAXApplicationHiddenNotification as CFString,
    kAXApplicationShownNotification as CFString,
  ]

  private var timer: Timer?
  private var observerRefreshTimer: Timer?
  private var activePollingInterval: TimeInterval?
  private var handlesByRuntimeID: [String: AXUIElement] = [:]
  private var observerRegistrationsByPID: [pid_t: AXObserverRegistration] = [:]
  private var notificationCancellables: Set<AnyCancellable> = []
  private var didStartObservers = false
  private var isAutomaticRefreshingPaused = false
  private var refreshCount = 0
  private var observerEventCount = 0
  private var lastRefreshAt: Date?
  private var lastRefreshReason: WindowRefreshReason?
  private var lastRefreshDurationMs: Double?

  // Injects the permission manager used for AX trust checks.
  init(permissionManager: AccessibilityPermissionManager) {
    self.permissionManager = permissionManager
  }

  // Starts observer subscriptions and polling with an immediate refresh.
  func startPolling() {
    stopPolling()
    startObserverNotifications()
    refreshNow(reason: .startup)
    updatePollingTimerIfNeeded()
  }

  // Stops all timers and observer run-loop registrations.
  func stopPolling() {
    isAutomaticRefreshingPaused = false
    timer?.invalidate()
    timer = nil
    observerRefreshTimer?.invalidate()
    observerRefreshTimer = nil
    activePollingInterval = nil
    if focusedRuntimeID != nil {
      focusedRuntimeID = nil
    }
    stopObserverNotifications()
    removeAllAXObservers()
    publishDiagnostics()
  }

  // Suspends automatic polling/observer refresh while allowing manual refreshes.
  func pauseAutomaticRefreshing() {
    guard !isAutomaticRefreshingPaused else { return }
    isAutomaticRefreshingPaused = true
    timer?.invalidate()
    timer = nil
    observerRefreshTimer?.invalidate()
    observerRefreshTimer = nil
    activePollingInterval = nil
    publishDiagnostics()
  }

  // Re-enables automatic refresh flow and performs one immediate sync.
  func resumeAutomaticRefreshing() {
    guard isAutomaticRefreshingPaused else { return }
    isAutomaticRefreshingPaused = false
    refreshNow(reason: .manual)
  }

  // Refreshes open windows and updates diagnostics for the given trigger.
  func refreshNow(reason: WindowRefreshReason = .manual) {
    let refreshStartedAt = Date()
    permissionManager.refreshStatus()
    guard permissionManager.isTrusted else {
      if !windows.isEmpty {
        windows = []
      }
      if focusedRuntimeID != nil {
        focusedRuntimeID = nil
      }
      handlesByRuntimeID = [:]
      removeAllAXObservers()
      updatePollingTimerIfNeeded()
      recordRefresh(reason: reason, startedAt: refreshStartedAt)
      return
    }

    let runningApps = eligibleRunningApps()
    syncAXObservers(for: runningApps)
    let result = enumerateWindows(in: runningApps)
    let sortedWindows = result.windows.sorted {
      if $0.appName == $1.appName {
        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
      return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
    }
    if windows != sortedWindows {
      windows = sortedWindows
    }
    handlesByRuntimeID = result.handlesByRuntimeID
    let resolvedFocusedRuntimeID = resolveFocusedRuntimeID(in: sortedWindows)
    if focusedRuntimeID != resolvedFocusedRuntimeID {
      focusedRuntimeID = resolvedFocusedRuntimeID
    }
    updatePollingTimerIfNeeded()
    recordRefresh(reason: reason, startedAt: refreshStartedAt)
  }

  // Activates and focuses a specific runtime window id.
  func activateWindow(runtimeID: String) -> Bool {
    guard permissionManager.isTrusted else { return false }
    guard let snapshot = windows.first(where: { $0.id == runtimeID }) else { return false }
    guard let windowElement = handlesByRuntimeID[runtimeID] else { return false }

    if let runningApp = NSRunningApplication(processIdentifier: snapshot.pid) {
      _ = runningApp.activate(options: [.activateAllWindows])
    }

    _ = setBooleanAttribute(
      for: windowElement,
      attribute: kAXMinimizedAttribute as CFString,
      value: false
    )

    let appElement = AXUIElementCreateApplication(snapshot.pid)
    _ = AXUIElementSetAttributeValue(
      appElement, kAXFocusedWindowAttribute as CFString, windowElement)
    _ = AXUIElementSetAttributeValue(windowElement, kAXMainAttribute as CFString, kCFBooleanTrue)
    _ = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
    _ = AXUIElementSetAttributeValue(windowElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    return true
  }

  // Enumerates candidate windows for each eligible running application.
  private func enumerateWindows(in apps: [NSRunningApplication]) -> (
    windows: [WindowSnapshot], handlesByRuntimeID: [String: AXUIElement]
  ) {
    var snapshots: [WindowSnapshot] = []
    var handles: [String: AXUIElement] = [:]

    for app in apps {
      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      guard let windowElements = axWindowList(for: appElement) else { continue }

      for windowElement in windowElements {
        guard
          let snapshot = buildSnapshot(
            app: app,
            windowElement: windowElement
          )
        else { continue }

        snapshots.append(snapshot)
        handles[snapshot.id] = windowElement
      }
    }

    return (snapshots, handles)
  }

  // Filters to regular, non-terminated apps other than Toolbar Helper.
  private func eligibleRunningApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular
        && !$0.isTerminated
        && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        && ($0.bundleIdentifier?.isEmpty == false)
    }
  }

  // Subscribes to observer events and app lifecycle notifications.
  private func startObserverNotifications() {
    guard !didStartObservers else { return }
    didStartObservers = true

    NotificationCenter.default.publisher(for: windowStoreAXObserverEventNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.scheduleObserverRefresh()
      }
      .store(in: &notificationCancellables)

    let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    let appLifecyclePublisher = workspaceNotificationCenter.publisher(
      for: NSWorkspace.didLaunchApplicationNotification
    )
    .merge(
      with: workspaceNotificationCenter.publisher(
        for: NSWorkspace.didTerminateApplicationNotification
      )
    )

    appLifecyclePublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        guard !self.isAutomaticRefreshingPaused else { return }
        Task { @MainActor in
          self.refreshNow(reason: .workspaceLifecycle)
        }
      }
      .store(in: &notificationCancellables)
  }

  // Tears down Combine subscriptions for observer and lifecycle notifications.
  private func stopObserverNotifications() {
    didStartObservers = false
    for cancellable in notificationCancellables {
      cancellable.cancel()
    }
    notificationCancellables.removeAll()
  }

  // Debounces observer bursts before triggering a refresh pass.
  private func scheduleObserverRefresh() {
    guard permissionManager.isTrusted else { return }
    guard !isAutomaticRefreshingPaused else { return }
    observerEventCount += 1
    observerRefreshTimer?.invalidate()
    observerRefreshTimer = Timer.scheduledTimer(
      withTimeInterval: observerRefreshDebounceInterval,
      repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.refreshNow(reason: .observerEvent)
      }
    }
    publishDiagnostics()
  }

  // Chooses fallback vs observer-backed polling interval.
  private func desiredPollingInterval() -> TimeInterval {
    guard permissionManager.isTrusted else { return fallbackPollingInterval }
    if observerRegistrationsByPID.isEmpty {
      return fallbackPollingInterval
    }
    return observerCapablePollingInterval
  }

  // Rebuilds the polling timer when the desired interval changes.
  private func updatePollingTimerIfNeeded() {
    if isAutomaticRefreshingPaused {
      timer?.invalidate()
      timer = nil
      activePollingInterval = nil
      publishDiagnostics()
      return
    }

    let desiredInterval = desiredPollingInterval()
    if let activePollingInterval, abs(activePollingInterval - desiredInterval) < 0.001 {
      return
    }

    activePollingInterval = desiredInterval
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: desiredInterval, repeats: true) {
      [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.refreshNow(reason: .polling)
      }
    }
    timer?.tolerance = min(0.5, desiredInterval * 0.25)
    publishDiagnostics()
  }

  // Adds/removes AX observers to match the currently running apps.
  private func syncAXObservers(for apps: [NSRunningApplication]) {
    let activePIDs = Set(apps.map(\.processIdentifier))
    let stalePIDs = observerRegistrationsByPID.keys.filter { !activePIDs.contains($0) }
    for pid in stalePIDs {
      removeAXObserver(for: pid)
    }

    for app in apps where observerRegistrationsByPID[app.processIdentifier] == nil {
      addAXObserver(for: app.processIdentifier)
    }
  }

  // Registers AX notifications for one process id if supported.
  private func addAXObserver(for pid: pid_t) {
    var observer: AXObserver?
    let createError = AXObserverCreate(pid, windowStoreAXObserverCallback, &observer)
    guard createError == .success, let observer else { return }

    let appElement = AXUIElementCreateApplication(pid)
    var supportsAnyNotification = false

    for notification in observedAppNotifications {
      let addError = AXObserverAddNotification(observer, appElement, notification, nil)
      if addError == .success || addError == .notificationAlreadyRegistered {
        supportsAnyNotification = true
      }
    }

    guard supportsAnyNotification else { return }

    let source = AXObserverGetRunLoopSource(observer)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    observerRegistrationsByPID[pid] = AXObserverRegistration(
      observer: observer,
      appElement: appElement
    )
  }

  // Unregisters all AX notifications for one process id.
  private func removeAXObserver(for pid: pid_t) {
    guard let registration = observerRegistrationsByPID.removeValue(forKey: pid) else { return }

    for notification in observedAppNotifications {
      _ = AXObserverRemoveNotification(
        registration.observer,
        registration.appElement,
        notification
      )
    }

    let source = AXObserverGetRunLoopSource(registration.observer)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
  }

  // Removes all currently registered AX observers.
  private func removeAllAXObservers() {
    for pid in Array(observerRegistrationsByPID.keys) {
      removeAXObserver(for: pid)
    }
  }

  // Converts an AX window element into a normalized snapshot model.
  private func buildSnapshot(app: NSRunningApplication, windowElement: AXUIElement)
    -> WindowSnapshot?
  {
    let role = axStringAttribute(for: windowElement, attribute: kAXRoleAttribute as CFString) ?? ""
    guard role == (kAXWindowRole as String) else { return nil }

    let subrole = axStringAttribute(for: windowElement, attribute: kAXSubroleAttribute as CFString)
    if let subrole, excludedSubroles.contains(subrole) {
      return nil
    }

    let rawTitle =
      axStringAttribute(for: windowElement, attribute: kAXTitleAttribute as CFString) ?? ""
    if rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && subrole == "AXUnknown"
    {
      return nil
    }

    let windowNumber = axIntAttribute(
      for: windowElement, attribute: "AXWindowNumber" as CFString)
    let runtimeID = buildRuntimeID(
      pid: app.processIdentifier,
      windowNumber: windowNumber,
      windowElement: windowElement
    )

    return WindowSnapshot(
      id: runtimeID,
      pid: app.processIdentifier,
      bundleID: app.bundleIdentifier ?? "unknown.bundle.id",
      appName: app.localizedName ?? "Unknown App",
      title: rawTitle.isEmpty ? "Untitled Window" : rawTitle,
      windowNumber: windowNumber,
      role: role,
      subrole: subrole,
      frame: axWindowFrame(for: windowElement),
      isMinimized: axBoolAttribute(for: windowElement, attribute: kAXMinimizedAttribute as CFString)
        ?? false
    )
  }

  private var excludedSubroles: Set<String> {
    [
      kAXFloatingWindowSubrole as String,
      kAXSystemDialogSubrole as String,
    ]
  }

  // Builds runtime id from stable window number when available.
  private func buildRuntimeID(pid: pid_t, windowNumber: Int?, windowElement: AXUIElement) -> String
  {
    if let windowNumber {
      return "\(pid)-\(windowNumber)"
    }

    let pointer = Unmanaged.passUnretained(windowElement).toOpaque()
    return "\(pid)-\(Int(bitPattern: pointer))"
  }

  // Reads the app-level AX window list and safely downcasts values.
  private func axWindowList(for appElement: AXUIElement) -> [AXUIElement]? {
    guard
      let value = axAttributeValue(
        for: appElement,
        attribute: kAXWindowsAttribute as CFString
      )
    else {
      return nil
    }

    if let windows = value as? [AXUIElement] {
      return windows
    }

    if let array = value as? NSArray {
      return array.compactMap { item in
        let cfValue = item as CFTypeRef
        guard CFGetTypeID(cfValue) == AXUIElementGetTypeID() else {
          return nil
        }
        return unsafeDowncast(item as AnyObject, to: AXUIElement.self)
      }
    }

    return nil
  }

  // Resolves the currently focused runtime window id from the frontmost app.
  private func resolveFocusedRuntimeID(in windows: [WindowSnapshot]) -> String? {
    guard !windows.isEmpty else { return nil }

    let toolbarHelperPID = ProcessInfo.processInfo.processIdentifier
    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }

    // Keep the last known focused runtime id while this menu-bar app is frontmost.
    if frontmostApp.processIdentifier == toolbarHelperPID {
      guard let focusedRuntimeID else { return nil }
      return windows.contains(where: { $0.id == focusedRuntimeID }) ? focusedRuntimeID : nil
    }

    let pid = frontmostApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)
    guard
      let focusedWindowValue = axAttributeValue(
        for: appElement,
        attribute: kAXFocusedWindowAttribute as CFString
      )
    else {
      return nil
    }
    let focusedWindowCFValue = focusedWindowValue as CFTypeRef
    guard CFGetTypeID(focusedWindowCFValue) == AXUIElementGetTypeID() else {
      return nil
    }
    let focusedWindowElement = unsafeDowncast(focusedWindowValue, to: AXUIElement.self)

    let focusedWindowNumber = axIntAttribute(
      for: focusedWindowElement,
      attribute: "AXWindowNumber" as CFString
    )
    let focusedRuntimeID = buildRuntimeID(
      pid: pid,
      windowNumber: focusedWindowNumber,
      windowElement: focusedWindowElement
    )
    if windows.contains(where: { $0.id == focusedRuntimeID }) {
      return focusedRuntimeID
    }

    let candidateWindows = windows.filter { $0.pid == pid }
    if let focusedWindowNumber,
      let numberMatch = candidateWindows.first(where: { $0.windowNumber == focusedWindowNumber })
    {
      return numberMatch.id
    }

    let focusedWindowTitle =
      axStringAttribute(for: focusedWindowElement, attribute: kAXTitleAttribute as CFString)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let focusedWindowFrame = axWindowFrame(for: focusedWindowElement)

    if let focusedWindowFrame,
      let frameMatch = candidateWindows.first(where: {
        $0.frame == focusedWindowFrame
          && $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == focusedWindowTitle
      })
    {
      return frameMatch.id
    }

    if let titleMatch = candidateWindows.first(where: {
      $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == focusedWindowTitle
    }) {
      return titleMatch.id
    }

    return nil
  }

  // Reads a string AX attribute.
  private func axStringAttribute(for element: AXUIElement, attribute: CFString) -> String? {
    axAttributeValue(for: element, attribute: attribute) as? String
  }

  // Reads an integer AX attribute.
  private func axIntAttribute(for element: AXUIElement, attribute: CFString) -> Int? {
    guard let value = axAttributeValue(for: element, attribute: attribute) else { return nil }
    if let number = value as? NSNumber {
      return number.intValue
    }
    return nil
  }

  // Reads a boolean AX attribute.
  private func axBoolAttribute(for element: AXUIElement, attribute: CFString) -> Bool? {
    guard let value = axAttributeValue(for: element, attribute: attribute) else { return nil }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  // Reads a CGPoint AXValue attribute.
  private func axCGPointAttribute(for element: AXUIElement, attribute: CFString) -> CGPoint? {
    guard let value = axAttributeValue(for: element, attribute: attribute) else { return nil }
    let cfValue = value as CFTypeRef
    guard CFGetTypeID(cfValue) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
  }

  // Reads a CGSize AXValue attribute.
  private func axCGSizeAttribute(for element: AXUIElement, attribute: CFString) -> CGSize? {
    guard let value = axAttributeValue(for: element, attribute: attribute) else { return nil }
    let cfValue = value as CFTypeRef
    guard CFGetTypeID(cfValue) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
  }

  // Builds a coarse frame snapshot from AX position and size attributes.
  private func axWindowFrame(for element: AXUIElement) -> WindowFrame? {
    guard
      let position = axCGPointAttribute(for: element, attribute: kAXPositionAttribute as CFString),
      let size = axCGSizeAttribute(for: element, attribute: kAXSizeAttribute as CFString)
    else {
      return nil
    }

    return WindowFrame(
      x: Int(position.x.rounded()),
      y: Int(position.y.rounded()),
      width: max(0, Int(size.width.rounded())),
      height: max(0, Int(size.height.rounded()))
    )
  }

  // Reads a raw AX attribute value.
  private func axAttributeValue(for element: AXUIElement, attribute: CFString) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success, let value else {
      return nil
    }
    return value
  }

  // Sets a boolean AX attribute value.
  private func setBooleanAttribute(for element: AXUIElement, attribute: CFString, value: Bool)
    -> AXError
  {
    AXUIElementSetAttributeValue(element, attribute, value ? kCFBooleanTrue : kCFBooleanFalse)
  }

  // Captures refresh timing metadata and republishes diagnostics.
  private func recordRefresh(reason: WindowRefreshReason, startedAt: Date) {
    refreshCount += 1
    lastRefreshAt = Date()
    lastRefreshReason = reason
    lastRefreshDurationMs = Date().timeIntervalSince(startedAt) * 1000
    publishDiagnostics()
  }

  // Publishes the latest runtime diagnostics snapshot.
  private func publishDiagnostics() {
    diagnostics = WindowStoreDiagnostics(
      isTrusted: permissionManager.isTrusted,
      observerRegistrationCount: observerRegistrationsByPID.count,
      activePollingInterval: activePollingInterval,
      refreshCount: refreshCount,
      observerEventCount: observerEventCount,
      lastRefreshAt: lastRefreshAt,
      lastRefreshReason: lastRefreshReason,
      lastRefreshDurationMs: lastRefreshDurationMs,
      windowCount: windows.count
    )
  }
}
