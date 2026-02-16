import Foundation

struct WindowSnapshot: Identifiable, Hashable {
  let id: String
  let pid: pid_t
  let bundleID: String
  let appName: String
  let title: String
  let windowNumber: Int?
  let role: String
  let subrole: String?
  let isMinimized: Bool

  var menuTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeTitle = trimmedTitle.isEmpty ? "Untitled Window" : trimmedTitle
    return "\(safeTitle) — \(appName)"
  }
}

struct PinnedWindowReference: Identifiable, Codable, Hashable {
  let id: UUID
  var bundleID: String
  var appName: String
  var title: String
  var windowNumber: Int?
  var lastKnownRuntimeID: String?
  var customName: String?
  var pinnedAt: Date
}

struct PinnedWindowItem: Identifiable {
  let id: UUID
  let reference: PinnedWindowReference
  let window: WindowSnapshot?

  var isMissing: Bool {
    window == nil
  }

  var displayTitle: String {
    let source = window?.title ?? reference.title
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled" : trimmed
  }

  var displayAppName: String {
    window?.appName ?? reference.appName
  }

  var tabLabel: String {
    if let customName = reference.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !customName.isEmpty
    {
      return customName
    }

    return "\(displayAppName) • \(displayTitle)"
  }
}
