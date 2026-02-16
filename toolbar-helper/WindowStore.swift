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

@MainActor
final class WindowStore: ObservableObject {
  @Published private(set) var windows: [WindowSnapshot] = []

  private struct AXObserverRegistration {
    let observer: AXObserver
    let appElement: AXUIElement
  }

  private let permissionManager: AccessibilityPermissionManager
  private let observerCapablePollingInterval: TimeInterval = 3.0
  private let fallbackPollingInterval: TimeInterval = 1.2
  private let observerRefreshDebounceInterval: TimeInterval = 0.2
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

  init(permissionManager: AccessibilityPermissionManager) {
    self.permissionManager = permissionManager
  }

  func startPolling() {
    stopPolling()
    startObserverNotifications()
    refreshNow()
    updatePollingTimerIfNeeded()
  }

  func stopPolling() {
    timer?.invalidate()
    timer = nil
    observerRefreshTimer?.invalidate()
    observerRefreshTimer = nil
    activePollingInterval = nil
    stopObserverNotifications()
    removeAllAXObservers()
  }

  func refreshNow() {
    permissionManager.refreshStatus()
    guard permissionManager.isTrusted else {
      windows = []
      handlesByRuntimeID = [:]
      removeAllAXObservers()
      updatePollingTimerIfNeeded()
      return
    }

    let runningApps = eligibleRunningApps()
    syncAXObservers(for: runningApps)
    let result = enumerateWindows(in: runningApps)
    windows = result.windows.sorted {
      if $0.appName == $1.appName {
        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
      return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
    }
    handlesByRuntimeID = result.handlesByRuntimeID
    updatePollingTimerIfNeeded()
  }

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

  private func eligibleRunningApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular
        && !$0.isTerminated
        && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        && ($0.bundleIdentifier?.isEmpty == false)
    }
  }

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
        Task { @MainActor in
          self.refreshNow()
        }
      }
      .store(in: &notificationCancellables)
  }

  private func stopObserverNotifications() {
    didStartObservers = false
    for cancellable in notificationCancellables {
      cancellable.cancel()
    }
    notificationCancellables.removeAll()
  }

  private func scheduleObserverRefresh() {
    guard permissionManager.isTrusted else { return }
    observerRefreshTimer?.invalidate()
    observerRefreshTimer = Timer.scheduledTimer(
      withTimeInterval: observerRefreshDebounceInterval,
      repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.refreshNow()
      }
    }
  }

  private func desiredPollingInterval() -> TimeInterval {
    guard permissionManager.isTrusted else { return fallbackPollingInterval }
    if observerRegistrationsByPID.isEmpty {
      return fallbackPollingInterval
    }
    return observerCapablePollingInterval
  }

  private func updatePollingTimerIfNeeded() {
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
        self.refreshNow()
      }
    }
    timer?.tolerance = min(0.5, desiredInterval * 0.25)
  }

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

  private func removeAllAXObservers() {
    for pid in Array(observerRegistrationsByPID.keys) {
      removeAXObserver(for: pid)
    }
  }

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

  private func buildRuntimeID(pid: pid_t, windowNumber: Int?, windowElement: AXUIElement) -> String
  {
    if let windowNumber {
      return "\(pid)-\(windowNumber)"
    }

    let pointer = Unmanaged.passUnretained(windowElement).toOpaque()
    return "\(pid)-\(Int(bitPattern: pointer))"
  }

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

  private func axStringAttribute(for element: AXUIElement, attribute: CFString) -> String? {
    axAttributeValue(for: element, attribute: attribute) as? String
  }

  private func axIntAttribute(for element: AXUIElement, attribute: CFString) -> Int? {
    guard let value = axAttributeValue(for: element, attribute: attribute) else { return nil }
    if let number = value as? NSNumber {
      return number.intValue
    }
    return nil
  }

  private func axBoolAttribute(for element: AXUIElement, attribute: CFString) -> Bool? {
    guard let value = axAttributeValue(for: element, attribute: attribute) else { return nil }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  private func axAttributeValue(for element: AXUIElement, attribute: CFString) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success, let value else {
      return nil
    }
    return value
  }

  private func setBooleanAttribute(for element: AXUIElement, attribute: CFString, value: Bool)
    -> AXError
  {
    AXUIElementSetAttributeValue(element, attribute, value ? kCFBooleanTrue : kCFBooleanFalse)
  }
}
