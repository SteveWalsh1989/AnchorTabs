import Foundation
import XCTest

@testable import toolbar_helper

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

private func makeReference(
  bundleID: String,
  title: String,
  windowNumber: Int?,
  runtimeID: String?,
  role: String?,
  subrole: String?,
  frame: WindowFrame?
) -> PinnedWindowReference {
  PinnedWindowReference(
    id: UUID(),
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
