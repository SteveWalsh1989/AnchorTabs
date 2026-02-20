import Foundation
import XCTest

@testable import toolbar_helper

@MainActor
final class PinnedStoreTests: XCTestCase {
  func testPinMatcherPrefersRuntimeID() {
    let reference = makeReference(
      bundleID: "com.example.browser",
      title: "Project Plan",
      windowNumber: 7,
      runtimeID: "900-7",
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 10, y: 10, width: 1200, height: 760)
    )

    let matchingWindow = makeWindow(
      id: "900-7",
      pid: 900,
      bundleID: "com.example.browser",
      appName: "Browser",
      title: "Project Plan",
      windowNumber: 15,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 12, y: 11, width: 1200, height: 760)
    )

    let result = PinMatcher.findBestMatch(
      for: reference,
      in: [matchingWindow],
      consumedWindowIDs: []
    )

    XCTAssertEqual(result?.window.id, "900-7")
    XCTAssertEqual(result?.method, .runtimeID)
  }

  func testPinMatcherFallsBackToSignature() {
    let oldWindow = makeWindow(
      id: "700-31",
      pid: 700,
      bundleID: "com.example.editor",
      appName: "Editor",
      title: "Sprint Notes",
      windowNumber: 31,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 140, y: 120, width: 1100, height: 720)
    )

    var reference = makeReference(
      bundleID: oldWindow.bundleID,
      title: oldWindow.title,
      windowNumber: oldWindow.windowNumber,
      runtimeID: oldWindow.id,
      role: oldWindow.role,
      subrole: oldWindow.subrole,
      frame: oldWindow.frame
    )
    reference.signature = PinMatcher.signature(for: oldWindow)
    reference.lastKnownRuntimeID = "700-99"
    reference.windowNumber = 99

    let relaunchedWindow = makeWindow(
      id: "700-45",
      pid: 700,
      bundleID: "com.example.editor",
      appName: "Editor",
      title: "Sprint Notes",
      windowNumber: 45,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 148, y: 118, width: 1100, height: 720)
    )

    let result = PinMatcher.findBestMatch(
      for: reference,
      in: [relaunchedWindow],
      consumedWindowIDs: []
    )

    XCTAssertEqual(result?.window.id, relaunchedWindow.id)
    XCTAssertEqual(result?.method, .signature)
  }

  func testPinMatcherSignatureCollisionIsTreatedAsAmbiguous() {
    let reference = makeReference(
      bundleID: "com.example.cursor",
      title: "Workspace",
      windowNumber: nil,
      runtimeID: "1000-stale",
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 100, y: 100, width: 1200, height: 760)
    )

    let otherWindow = makeWindow(
      id: "1000-b",
      pid: 1000,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Workspace",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 130, y: 130, width: 1200, height: 760)
    )

    let expectedWindow = makeWindow(
      id: "1000-a",
      pid: 1000,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Workspace",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 100, y: 100, width: 1200, height: 760)
    )

    let result = PinMatcher.findBestMatch(
      for: reference,
      in: [otherWindow, expectedWindow],
      consumedWindowIDs: []
    )

    XCTAssertNil(result)
  }

  func testPinMatcherIgnoresLegacyFallbackRuntimeIDWhenSignatureIsAmbiguous() {
    let reference = makeReference(
      bundleID: "com.example.cursor",
      title: "Workspace",
      windowNumber: nil,
      runtimeID: "1000-fallback-abc12345-0",
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 100, y: 100, width: 1200, height: 760)
    )

    let wrongRuntimeMatch = makeWindow(
      id: "1000-fallback-abc12345-0",
      pid: 1000,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Workspace",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 130, y: 130, width: 1200, height: 760)
    )

    let otherWindow = makeWindow(
      id: "1000-fallback-abc12345-1",
      pid: 1000,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Workspace",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 100, y: 100, width: 1200, height: 760)
    )

    let result = PinMatcher.findBestMatch(
      for: reference,
      in: [wrongRuntimeMatch, otherWindow],
      consumedWindowIDs: []
    )

    XCTAssertNil(result)
  }

  func testPinMatcherDoesNotTitleFallbackAcrossMultipleAppWindows() {
    let reference = makeReference(
      bundleID: "com.example.browser",
      title: "Project Plan",
      windowNumber: nil,
      runtimeID: "stale-runtime-id",
      role: nil,
      subrole: nil,
      frame: nil
    )

    let exactTitleWindow = makeWindow(
      id: "700-1",
      pid: 700,
      bundleID: "com.example.browser",
      appName: "Browser",
      title: "Project Plan",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 10, y: 10, width: 1200, height: 760)
    )

    let otherWindow = makeWindow(
      id: "700-2",
      pid: 700,
      bundleID: "com.example.browser",
      appName: "Browser",
      title: "Release Notes",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 40, y: 40, width: 1200, height: 760)
    )

    let result = PinMatcher.findBestMatch(
      for: reference,
      in: [exactTitleWindow, otherWindow],
      consumedWindowIDs: []
    )

    XCTAssertNil(result)
  }

  func testWindowStoreFallbackRuntimeIDFingerprintNormalizesTitle() {
    let snapshotA = makeWindow(
      id: "",
      pid: 901,
      bundleID: "com.example.browser",
      appName: "Browser",
      title: "  Sprint Plan  ",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 10, y: 10, width: 1200, height: 760)
    )
    let snapshotB = makeWindow(
      id: "",
      pid: 901,
      bundleID: "com.example.browser",
      appName: "Browser",
      title: "sprint plan",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 10, y: 10, width: 1200, height: 760)
    )

    XCTAssertEqual(
      WindowStore.fallbackRuntimeIDFingerprint(for: snapshotA),
      WindowStore.fallbackRuntimeIDFingerprint(for: snapshotB)
    )
  }

  func testWindowStoreFallbackRuntimeIDIsDeterministicAndOccurrenceSensitive() {
    let snapshot = makeWindow(
      id: "",
      pid: 777,
      bundleID: "com.example.editor",
      appName: "Editor",
      title: "Release Notes",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 120, y: 80, width: 1180, height: 740)
    )

    let fingerprint = WindowStore.fallbackRuntimeIDFingerprint(for: snapshot)
    let firstID = WindowStore.fallbackRuntimeID(pid: snapshot.pid, fingerprint: fingerprint, occurrence: 0)
    let firstIDAgain = WindowStore.fallbackRuntimeID(
      pid: snapshot.pid,
      fingerprint: fingerprint,
      occurrence: 0
    )
    let secondID = WindowStore.fallbackRuntimeID(
      pid: snapshot.pid,
      fingerprint: fingerprint,
      occurrence: 1
    )

    XCTAssertEqual(firstID, firstIDAgain)
    XCTAssertNotEqual(firstID, secondID)
    XCTAssertTrue(firstID.hasPrefix("\(snapshot.pid)-fallback-"))
    XCTAssertTrue(secondID.hasSuffix("-1"))
  }

  @MainActor
  func testPinnedStorePersistsRenameAcrossReload() {
    let suiteName = "PinnedStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Unable to create test defaults suite")
      return
    }
    defaults.removePersistentDomain(forName: suiteName)

    let window = makeWindow(
      id: "501-2",
      pid: 501,
      bundleID: "com.example.mail",
      appName: "Mailer",
      title: "Inbox - Team",
      windowNumber: 2,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 80, y: 80, width: 1050, height: 700)
    )

    let store = PinnedStore(userDefaults: defaults)
    store.reconcile(with: [window])
    store.togglePin(for: window)

    guard let pinID = store.pinnedItems.first?.id else {
      XCTFail("Expected one pinned item")
      return
    }

    store.renamePin(pinID: pinID, customName: "Work Inbox")

    let reloadedStore = PinnedStore(userDefaults: defaults)
    reloadedStore.reconcile(with: [window])

    XCTAssertEqual(reloadedStore.pinnedItems.count, 1)
    XCTAssertEqual(reloadedStore.pinnedItems.first?.reference.customName, "Work Inbox")
    defaults.removePersistentDomain(forName: suiteName)
  }

  @MainActor
  func testPinnedStoreMarksMissingWhenWindowDisappears() {
    let suiteName = "PinnedStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Unable to create test defaults suite")
      return
    }
    defaults.removePersistentDomain(forName: suiteName)

    let window = makeWindow(
      id: "812-4",
      pid: 812,
      bundleID: "com.example.slides",
      appName: "Slides",
      title: "Quarterly Review",
      windowNumber: 4,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 40, y: 40, width: 1280, height: 820)
    )

    let store = PinnedStore(userDefaults: defaults)
    store.reconcile(with: [window])
    store.togglePin(for: window)
    store.reconcile(with: [])

    XCTAssertEqual(store.pinnedItems.count, 1)
    XCTAssertTrue(store.pinnedItems[0].isMissing)
    XCTAssertEqual(store.diagnostics.totalPins, 1)
    XCTAssertEqual(store.diagnostics.matchedPins, 0)
    XCTAssertEqual(store.diagnostics.missingPins, 1)
    defaults.removePersistentDomain(forName: suiteName)
  }

  @MainActor
  func testPinnedStoreKeepsAssignmentsStableWhenWindowOrderChanges() throws {
    let suiteName = "PinnedStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Unable to create test defaults suite")
      return
    }
    defaults.removePersistentDomain(forName: suiteName)

    let firstPinID = UUID()
    let secondPinID = UUID()

    let firstReference = makeReference(
      id: firstPinID,
      bundleID: "com.example.cursor",
      title: "Workspace",
      windowNumber: nil,
      runtimeID: "stale-1",
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 100, y: 100, width: 1200, height: 760)
    )
    let secondReference = makeReference(
      id: secondPinID,
      bundleID: "com.example.cursor",
      title: "Workspace",
      windowNumber: nil,
      runtimeID: "stale-2",
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 130, y: 130, width: 1200, height: 760)
    )

    let serializedReferences = try JSONEncoder().encode([firstReference, secondReference])
    defaults.set(serializedReferences, forKey: "PinnedWindows.v1")

    let firstWindow = makeWindow(
      id: "500-1",
      pid: 500,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Workspace",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 100, y: 100, width: 1200, height: 760)
    )
    let secondWindow = makeWindow(
      id: "500-2",
      pid: 500,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Workspace",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 130, y: 130, width: 1200, height: 760)
    )

    let store = PinnedStore(userDefaults: defaults)
    store.reconcile(with: [secondWindow, firstWindow])
    let firstMatchBefore = store.pinnedItems.first(where: { $0.id == firstPinID })?.window?.id
    let secondMatchBefore = store.pinnedItems.first(where: { $0.id == secondPinID })?.window?.id

    store.reconcile(with: [firstWindow, secondWindow])
    let firstMatchAfter = store.pinnedItems.first(where: { $0.id == firstPinID })?.window?.id
    let secondMatchAfter = store.pinnedItems.first(where: { $0.id == secondPinID })?.window?.id

    XCTAssertEqual(firstMatchBefore, firstWindow.id)
    XCTAssertEqual(secondMatchBefore, secondWindow.id)
    XCTAssertEqual(firstMatchAfter, firstWindow.id)
    XCTAssertEqual(secondMatchAfter, secondWindow.id)
    defaults.removePersistentDomain(forName: suiteName)
  }

  @MainActor
  func testPinnedStoreRefreshesStoredWindowNamesAndKeepsThemWhenMissing() {
    let suiteName = "PinnedStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Unable to create test defaults suite")
      return
    }
    defaults.removePersistentDomain(forName: suiteName)

    let initialWindow = makeWindow(
      id: "600-3",
      pid: 600,
      bundleID: "com.example.writer",
      appName: "Writer",
      title: "Draft",
      windowNumber: 3,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 140, y: 90, width: 1200, height: 780)
    )

    let renamedWindow = makeWindow(
      id: "600-3",
      pid: 600,
      bundleID: "com.example.writer",
      appName: "Writer Pro",
      title: "Final Draft",
      windowNumber: 3,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 140, y: 90, width: 1200, height: 780)
    )

    let store = PinnedStore(userDefaults: defaults)
    store.reconcile(with: [initialWindow])
    store.togglePin(for: initialWindow)
    store.reconcile(with: [renamedWindow])
    store.reconcile(with: [])

    XCTAssertEqual(store.pinnedItems.count, 1)
    XCTAssertTrue(store.pinnedItems[0].isMissing)
    XCTAssertEqual(store.pinnedItems[0].reference.title, "Final Draft")
    XCTAssertEqual(store.pinnedItems[0].reference.appName, "Writer Pro")
    XCTAssertEqual(store.pinnedItems[0].displayTitle, "Final Draft")
    XCTAssertEqual(store.pinnedItems[0].displayAppName, "Writer Pro")
    defaults.removePersistentDomain(forName: suiteName)
  }

  @MainActor
  func testPinnedStoreReassignPinKeepsCustomNameAndUpdatesIdentity() {
    let suiteName = "PinnedStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Unable to create test defaults suite")
      return
    }
    defaults.removePersistentDomain(forName: suiteName)

    let initialWindow = makeWindow(
      id: "901-generated-a",
      pid: 901,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Repo One",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 120, y: 80, width: 1200, height: 760)
    )
    let replacementWindow = makeWindow(
      id: "901-generated-b",
      pid: 901,
      bundleID: "com.example.cursor",
      appName: "Cursor",
      title: "Repo Two",
      windowNumber: nil,
      role: "AXWindow",
      subrole: nil,
      frame: WindowFrame(x: 220, y: 120, width: 1200, height: 760)
    )

    let store = PinnedStore(userDefaults: defaults)
    store.reconcile(with: [initialWindow, replacementWindow])
    store.togglePin(for: initialWindow)

    guard let pinnedItem = store.pinnedItems.first else {
      XCTFail("Expected one pinned item")
      return
    }

    store.renamePin(pinID: pinnedItem.id, customName: "Work Repo")
    store.reassignPin(pinID: pinnedItem.id, to: replacementWindow)

    guard let updatedPinnedItem = store.pinnedItems.first else {
      XCTFail("Expected one pinned item after reassignment")
      return
    }

    XCTAssertEqual(updatedPinnedItem.window?.id, replacementWindow.id)
    XCTAssertEqual(updatedPinnedItem.reference.lastKnownRuntimeID, replacementWindow.id)
    XCTAssertEqual(updatedPinnedItem.reference.title, replacementWindow.title)
    XCTAssertEqual(updatedPinnedItem.reference.customName, "Work Repo")
    XCTAssertEqual(updatedPinnedItem.tabLabel, "Work Repo")
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private func makeWindow(
  id: String,
  pid: pid_t,
  bundleID: String,
  appName: String,
  title: String,
  windowNumber: Int?,
  role: String,
  subrole: String?,
  frame: WindowFrame?
) -> WindowSnapshot {
  WindowSnapshot(
    id: id,
    pid: pid,
    bundleID: bundleID,
    appName: appName,
    title: title,
    windowNumber: windowNumber,
    role: role,
    subrole: subrole,
    frame: frame,
    isMinimized: false
  )
}

@MainActor
private func makeReference(
  id: UUID = UUID(),
  bundleID: String,
  title: String,
  windowNumber: Int?,
  runtimeID: String?,
  role: String?,
  subrole: String?,
  frame: WindowFrame?
) -> PinnedWindowReference {
  PinnedWindowReference(
    id: id,
    bundleID: bundleID,
    appName: "App",
    title: title,
    windowNumber: windowNumber,
    lastKnownRuntimeID: runtimeID,
    role: role,
    subrole: subrole,
    customName: nil,
    normalizedTitle: PinMatcher.normalizedTitle(title),
    frame: frame,
    signature: nil,
    pinnedAt: Date()
  )
}
