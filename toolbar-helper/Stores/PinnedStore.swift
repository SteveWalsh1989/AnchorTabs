import Combine
import Foundation
import SwiftUI

// Persists pinned windows and reconciles them against current AX snapshots.
@MainActor
final class PinnedStore: ObservableObject {
  @Published private(set) var pinnedItems: [PinnedWindowItem] = []
  @Published private(set) var maxVisiblePinnedTabs = 10
  @Published private(set) var diagnostics = PinnedStoreDiagnostics.empty

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
      let match = PinMatcher.findBestMatch(
        for: reference,
        in: windows,
        consumedWindowIDs: consumedWindowIDs
      )

      if let match {
        consumedWindowIDs.insert(match.window.id)
        matchedPins += 1
        methodCounts[match.method, default: 0] += 1
        let normalizedTitle = PinMatcher.normalizedTitle(match.window.title)
        let signature = PinMatcher.signature(for: match.window)
        if reference.title != match.window.title
          || reference.appName != match.window.appName
          || reference.windowNumber != match.window.windowNumber
          || reference.lastKnownRuntimeID != match.window.id
          || reference.role != match.window.role
          || reference.subrole != match.window.subrole
          || reference.normalizedTitle != normalizedTitle
          || reference.frame != match.window.frame
          || reference.signature != signature
        {
          reference.title = match.window.title
          reference.appName = match.window.appName
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
    diagnostics = PinnedStoreDiagnostics(
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

    references.append(
      PinnedWindowReference(
        id: UUID(),
        bundleID: window.bundleID,
        appName: window.appName,
        title: window.title,
        windowNumber: window.windowNumber,
        lastKnownRuntimeID: window.id,
        role: window.role,
        subrole: window.subrole,
        customName: nil,
        normalizedTitle: PinMatcher.normalizedTitle(window.title),
        frame: window.frame,
        signature: PinMatcher.signature(for: window),
        pinnedAt: Date()
      )
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

    let signature = PinMatcher.signature(for: window)
    let signatureMatches = references.filter { PinMatcher.signature(for: $0) == signature }
    if signatureMatches.count == 1 {
      return signatureMatches[0].id
    }
    return nil
  }

  // Serializes references to user defaults.
  private func save() {
    guard let data = try? JSONEncoder().encode(references) else { return }
    userDefaults.set(data, forKey: pinnedKey)
  }
}
