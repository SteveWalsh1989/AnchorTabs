import Foundation

// Labels the source of the most recent window refresh cycle.
enum WindowRefreshReason: String {
  case startup = "Startup"
  case polling = "Polling"
  case observerEvent = "Observer Event"
  case workspaceLifecycle = "App Launch/Terminate"
  case manual = "Manual"
}

// Runtime health metrics emitted by OpenWindowsStore.
struct OpenWindowsStoreDiagnostics {
  var isTrusted: Bool
  var observerRegistrationCount: Int
  var activePollingInterval: TimeInterval?
  var refreshCount: Int
  var observerEventCount: Int
  var lastRefreshAt: Date?
  var lastRefreshReason: WindowRefreshReason?
  var lastRefreshDurationMs: Double?
  var windowCount: Int

  static let empty = OpenWindowsStoreDiagnostics(
    isTrusted: false,
    observerRegistrationCount: 0,
    activePollingInterval: nil,
    refreshCount: 0,
    observerEventCount: 0,
    lastRefreshAt: nil,
    lastRefreshReason: nil,
    lastRefreshDurationMs: nil,
    windowCount: 0
  )
}

// Matching strategy used when reconciling a persisted pin to a live window.
enum PinMatchMethod: String, CaseIterable {
  case runtimeID = "Runtime ID"
  case windowNumber = "Window Number"
  case signature = "Signature"
  case exactTitle = "Exact Title"
  case fuzzyTitle = "Fuzzy Title"
}

// Runtime health metrics emitted by PinnedWindowsStore reconciliation.
struct PinnedWindowsStoreDiagnostics {
  var totalPins: Int
  var matchedPins: Int
  var missingPins: Int
  var lastReconcileAt: Date?
  var lastReconcileDurationMs: Double?
  var matchCountsByMethod: [PinMatchMethod: Int]

  static let empty = PinnedWindowsStoreDiagnostics(
    totalPins: 0,
    matchedPins: 0,
    missingPins: 0,
    lastReconcileAt: nil,
    lastReconcileDurationMs: nil,
    matchCountsByMethod: [:]
  )
}
