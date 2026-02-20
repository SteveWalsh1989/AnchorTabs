import Foundation

// Captures coarse window geometry for matching across app restarts.
struct WindowFrame: Codable, Hashable {
  let x: Int
  let y: Int
  let width: Int
  let height: Int
}

// Live snapshot of an Accessibility window discovered from a running app.
struct WindowSnapshot: Identifiable, Hashable {
  let id: String
  let pid: pid_t
  let bundleID: String
  let appName: String
  let title: String
  let windowNumber: Int?
  let role: String
  let subrole: String?
  let frame: WindowFrame?
  let isMinimized: Bool

  // Readable window title used in menu rows.
  var menuTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeTitle = trimmedTitle.isEmpty ? "Untitled Window" : trimmedTitle
    return "\(safeTitle) — \(appName)"
  }
}

// Persisted identity and display metadata for a pinned window.
struct PinnedWindowReference: Identifiable, Codable, Hashable {
  let id: UUID
  var bundleID: String
  var appName: String
  var title: String
  var windowNumber: Int?
  var lastKnownRuntimeID: String?
  var role: String?
  var subrole: String?
  var customName: String?
  var normalizedTitle: String?
  var frame: WindowFrame?
  var signature: String?
  var pinnedAt: Date
}

// View model that joins persisted pin data with the current window snapshot.
struct PinnedWindowItem: Identifiable, Equatable {
  let id: UUID
  let reference: PinnedWindowReference
  let window: WindowSnapshot?

  // True when the persisted pin no longer matches any open window.
  var isMissing: Bool {
    window == nil
  }

  // Prefer live title while available, otherwise fallback to persisted title.
  var displayTitle: String {
    let source = window?.title ?? reference.title
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled" : trimmed
  }

  // Prefer live app name while available, otherwise fallback to persisted app name.
  var displayAppName: String {
    window?.appName ?? reference.appName
  }

  // Uses custom label first, then a readable app + title fallback.
  var tabLabel: String {
    if let customName = reference.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !customName.isEmpty
    {
      return customName
    }

    return "\(displayAppName) • \(displayTitle)"
  }
}
