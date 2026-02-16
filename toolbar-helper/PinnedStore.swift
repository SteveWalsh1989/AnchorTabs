import Combine
import Foundation
import SwiftUI

@MainActor
final class PinnedStore: ObservableObject {
  @Published private(set) var pinnedItems: [PinnedWindowItem] = []
  @Published private(set) var maxVisiblePinnedTabs = 10

  private var references: [PinnedWindowReference]
  private var lastSeenWindows: [WindowSnapshot] = []
  private let userDefaults: UserDefaults
  private let pinnedKey = "PinnedWindows.v1"

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

  func reconcile(with windows: [WindowSnapshot]) {
    lastSeenWindows = windows
    var updatedReferences = references
    var didMutateReferences = false
    var consumedWindowIDs: Set<String> = []
    var newPinnedItems: [PinnedWindowItem] = []

    for index in updatedReferences.indices {
      var reference = updatedReferences[index]
      let match = findBestMatch(for: reference, in: windows, consumedWindowIDs: consumedWindowIDs)

      if let match {
        consumedWindowIDs.insert(match.id)
        if reference.title != match.title
          || reference.appName != match.appName
          || reference.windowNumber != match.windowNumber
          || reference.lastKnownRuntimeID != match.id
        {
          reference.title = match.title
          reference.appName = match.appName
          reference.windowNumber = match.windowNumber
          reference.lastKnownRuntimeID = match.id
          updatedReferences[index] = reference
          didMutateReferences = true
        }
        newPinnedItems.append(
          PinnedWindowItem(id: reference.id, reference: reference, window: match)
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
    pinnedItems = newPinnedItems
  }

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
        customName: nil,
        pinnedAt: Date()
      )
    )
    save()
    reconcile(with: lastSeenWindows)
  }

  func unpin(pinID: UUID) {
    references.removeAll { $0.id == pinID }
    save()
    reconcile(with: lastSeenWindows)
  }

  func removeAllMissingPins() {
    references =
      pinnedItems
      .filter { !$0.isMissing }
      .map(\.reference)
    save()
    reconcile(with: lastSeenWindows)
  }

  func renamePin(pinID: UUID, customName: String?) {
    guard let index = references.firstIndex(where: { $0.id == pinID }) else { return }
    let cleanedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
    references[index].customName = cleanedName?.isEmpty == true ? nil : cleanedName
    save()
    reconcile(with: lastSeenWindows)
  }

  func isPinned(window: WindowSnapshot) -> Bool {
    existingPinID(for: window) != nil
  }

  func pinnedItem(for window: WindowSnapshot) -> PinnedWindowItem? {
    guard let pinID = existingPinID(for: window) else { return nil }
    return pinnedItems.first(where: { $0.id == pinID })
  }

  /// Move a pinned item from one index to another and persist the change.
  func movePinnedItem(from source: IndexSet, to destination: Int) {
    references.move(fromOffsets: source, toOffset: destination)
    save()
    reconcile(with: lastSeenWindows)
  }

  /// Move a pinned item identified by its id to be before the item at `beforeIndex`.
  /// If `beforeIndex` is nil or out of bounds, moves it to the end.
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

  private func findBestMatch(
    for reference: PinnedWindowReference,
    in windows: [WindowSnapshot],
    consumedWindowIDs: Set<String>
  ) -> WindowSnapshot? {
    let candidates = windows.filter {
      $0.bundleID == reference.bundleID && !consumedWindowIDs.contains($0.id)
    }
    guard !candidates.isEmpty else { return nil }

    if let runtimeID = reference.lastKnownRuntimeID,
      let runtimeMatch = candidates.first(where: { $0.id == runtimeID })
    {
      return runtimeMatch
    }

    if let windowNumber = reference.windowNumber,
      let numberMatch = candidates.first(where: { $0.windowNumber == windowNumber })
    {
      return numberMatch
    }

    let normalizedPinnedTitle = reference.title.normalizedForMatching()
    if let titleMatch = candidates.first(where: {
      $0.title.normalizedForMatching() == normalizedPinnedTitle
    }) {
      return titleMatch
    }

    if let fuzzyTitleMatch = candidates.first(
      where: {
        let normalizedCandidate = $0.title.normalizedForMatching()
        return normalizedCandidate.contains(normalizedPinnedTitle)
          || normalizedPinnedTitle.contains(normalizedCandidate)
      }
    ) {
      return fuzzyTitleMatch
    }

    return nil
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(references) else { return }
    userDefaults.set(data, forKey: pinnedKey)
  }
}
