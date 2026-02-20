import Combine
import Foundation
import SwiftUI

// Persists pinned windows and reconciles them against current AX snapshots.
@MainActor
final class PinnedWindowsStore: ObservableObject {
  @Published private(set) var pinnedItems: [PinnedWindowItem] = []
  @Published private(set) var maxVisiblePinnedTabs = 10
  @Published private(set) var diagnostics = PinnedWindowsStoreDiagnostics.empty

  private var references: [PinnedWindowReference]
  private var lastSeenWindows: [WindowSnapshot] = []
  private let userDefaults: UserDefaults
  private let pinnedKey = "PinnedWindows.v1"

  // Loads persisted pin references from user defaults.
  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults

    if let data = userDefaults.data(forKey: pinnedKey),
      let decoded = try? JSONDecoder().decode([PinnedWindowReference].self, from: data)
    {
      references = decoded
    } else {
      references = []
    }
  }

  // Rebuilds pinned items by matching persisted references to live windows.
  func reconcile(with windows: [WindowSnapshot]) {
    let reconcileStart = Date()
    lastSeenWindows = windows
    var updatedReferences = references
    var didMutateReferences = false
    var consumedWindowIDs: Set<String> = []
    var newPinnedItems: [PinnedWindowItem] = []
    var methodCounts: [PinMatchMethod: Int] = [:]
    var matchedPins = 0

    for index in updatedReferences.indices {
      var reference = updatedReferences[index]
      let match = PinnedWindowMatcher.findBestMatch(
        for: reference,
        in: windows,
        consumedWindowIDs: consumedWindowIDs
      )

      if let match {
        consumedWindowIDs.insert(match.window.id)
        matchedPins += 1
        methodCounts[match.method, default: 0] += 1
        let storedTitle = canonicalStoredTitle(for: match.window)
        let storedAppName = canonicalStoredAppName(for: match.window)
        let normalizedTitle = PinnedWindowMatcher.normalizedTitle(match.window.title)
        let signature = PinnedWindowMatcher.signature(for: match.window)
        if reference.title != storedTitle
          || reference.appName != storedAppName
          || reference.windowNumber != match.window.windowNumber
          || reference.lastKnownRuntimeID != match.window.id
          || reference.role != match.window.role
          || reference.subrole != match.window.subrole
          || reference.normalizedTitle != normalizedTitle
          || reference.frame != match.window.frame
          || reference.signature != signature
        {
          reference.title = storedTitle
          reference.appName = storedAppName
          reference.windowNumber = match.window.windowNumber
          reference.lastKnownRuntimeID = match.window.id
          reference.role = match.window.role
          reference.subrole = match.window.subrole
          reference.normalizedTitle = normalizedTitle
          reference.frame = match.window.frame
          reference.signature = signature
          updatedReferences[index] = reference
          didMutateReferences = true
        }
        newPinnedItems.append(
          PinnedWindowItem(id: reference.id, reference: reference, window: match.window)
        )
      } else {
        newPinnedItems.append(
          PinnedWindowItem(id: reference.id, reference: reference, window: nil)
        )
      }
    }

    if didMutateReferences {
      references = updatedReferences
      save()
    }
    if pinnedItems != newPinnedItems {
      pinnedItems = newPinnedItems
    }
    diagnostics = PinnedWindowsStoreDiagnostics(
      totalPins: updatedReferences.count,
      matchedPins: matchedPins,
      missingPins: max(0, updatedReferences.count - matchedPins),
      lastReconcileAt: Date(),
      lastReconcileDurationMs: Date().timeIntervalSince(reconcileStart) * 1000,
      matchCountsByMethod: methodCounts
    )
  }

  // Toggles a window pin on/off using the strongest available identity match.
  func togglePin(for window: WindowSnapshot) {
    if let existing = existingPinID(for: window) {
      unpin(pinID: existing)
      return
    }

    var reference = PinnedWindowReference(
      id: UUID(),
      bundleID: window.bundleID,
      appName: canonicalStoredAppName(for: window),
      title: canonicalStoredTitle(for: window),
      windowNumber: window.windowNumber,
      lastKnownRuntimeID: window.id,
      role: window.role,
      subrole: window.subrole,
      customName: nil,
      normalizedTitle: PinnedWindowMatcher.normalizedTitle(window.title),
      frame: window.frame,
      signature: PinnedWindowMatcher.signature(for: window),
      pinnedAt: Date()
    )
    updateReferenceIdentity(&reference, from: window)
    references.append(
      reference
    )
    save()
    reconcile(with: lastSeenWindows)
  }

  // Removes a pin and persists the updated list.
  func unpin(pinID: UUID) {
    references.removeAll { $0.id == pinID }
    save()
    reconcile(with: lastSeenWindows)
  }

  // Drops all pins that no longer resolve to live windows.
  func removeAllMissingPins() {
    references =
      pinnedItems
      .filter { !$0.isMissing }
      .map(\.reference)
    save()
    reconcile(with: lastSeenWindows)
  }

  // Saves or clears a custom display name for a pin.
  func renamePin(pinID: UUID, customName: String?) {
    guard let index = references.firstIndex(where: { $0.id == pinID }) else { return }
    let cleanedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
    references[index].customName = cleanedName?.isEmpty == true ? nil : cleanedName
    save()
    reconcile(with: lastSeenWindows)
  }

  // Rebinds an existing pin to a selected live window while preserving custom pin naming.
  func reassignPin(pinID: UUID, to window: WindowSnapshot) {
    guard let index = references.firstIndex(where: { $0.id == pinID }) else { return }
    var reference = references[index]
    updateReferenceIdentity(&reference, from: window)
    references[index] = reference
    save()
    reconcile(with: lastSeenWindows)
  }

  // Returns true when a given live window is already pinned.
  func isPinned(window: WindowSnapshot) -> Bool {
    existingPinID(for: window) != nil
  }

  // Returns the pinned item that maps to a given live window.
  func pinnedItem(for window: WindowSnapshot) -> PinnedWindowItem? {
    guard let pinID = existingPinID(for: window) else { return nil }
    return pinnedItems.first(where: { $0.id == pinID })
  }

  // Reorders pins from list drag-move and persists the updated order.
  func movePinnedItem(from source: IndexSet, to destination: Int) {
    references.move(fromOffsets: source, toOffset: destination)
    save()
    reconcile(with: lastSeenWindows)
  }

  // Reorders a pin by id for custom drag/drop placement.
  func movePinnedItem(id: UUID, beforeIndex: Int?) {
    guard let currentIndex = references.firstIndex(where: { $0.id == id }) else { return }
    var refs = references
    let item = refs.remove(at: currentIndex)

    let clampedBefore: Int
    if let idx = beforeIndex, idx >= 0 && idx <= refs.count {
      clampedBefore = idx
    } else {
      clampedBefore = refs.count
    }

    refs.insert(item, at: clampedBefore)
    references = refs
    save()
    reconcile(with: lastSeenWindows)
  }

  // Stores a non-empty title so missing pins keep a stable readable name.
  private func canonicalStoredTitle(for window: WindowSnapshot) -> String {
    let trimmedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "Untitled Window" : trimmedTitle
  }

  // Stores a non-empty app name so missing pins still show identifiable source apps.
  private func canonicalStoredAppName(for window: WindowSnapshot) -> String {
    let trimmedAppName = window.appName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedAppName.isEmpty {
      return trimmedAppName
    }

    let trimmedBundleID = window.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedBundleID.isEmpty ? "Unknown App" : trimmedBundleID
  }

  // Updates identity fields for a reference using the selected live window snapshot.
  private func updateReferenceIdentity(_ reference: inout PinnedWindowReference, from window: WindowSnapshot)
  {
    reference.bundleID = window.bundleID
    reference.appName = canonicalStoredAppName(for: window)
    reference.title = canonicalStoredTitle(for: window)
    reference.windowNumber = window.windowNumber
    reference.lastKnownRuntimeID = window.id
    reference.role = window.role
    reference.subrole = window.subrole
    reference.normalizedTitle = PinnedWindowMatcher.normalizedTitle(window.title)
    reference.frame = window.frame
    reference.signature = PinnedWindowMatcher.signature(for: window)
  }

  // Finds an existing pin id for a live window using strict identities first.
  private func existingPinID(for window: WindowSnapshot) -> UUID? {
    if let exactRuntimeMatch = pinnedItems.first(where: { $0.window?.id == window.id }) {
      return exactRuntimeMatch.id
    }

    if let directMatch = references.first(where: {
      $0.bundleID == window.bundleID
        && (($0.windowNumber != nil && $0.windowNumber == window.windowNumber)
          || ($0.lastKnownRuntimeID != nil && $0.lastKnownRuntimeID == window.id))
    }) {
      return directMatch.id
    }
    return nil
  }

  // Serializes references to user defaults.
  private func save() {
    guard let data = try? JSONEncoder().encode(references) else { return }
    userDefaults.set(data, forKey: pinnedKey)
  }
}
