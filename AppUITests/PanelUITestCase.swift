import AppKit
import XCTest

/// Launches the real app in test mode against the throwaway daemon that
/// scripts/ui-smoke.sh starts (temp HOME and FSEARCH_ROOT with fixtures).
///
/// Xcode runs UI tests in a sandboxed runner that cannot start the daemon,
/// so the script passes `TEST_RUNNER_FSEARCH_SOCKET`. It also sets
/// `TEST_RUNNER_FSEARCH_UI_REQUIRED=1`, which makes a missing socket a failure
/// rather than a skip. Every test launches its own app: tests are independent.
@MainActor
class PanelUITestCase: XCTestCase {
    var app: XCUIApplication!
    var field: XCUIElement { app.textFields["searchField"] }
    /// Every item on the general pasteboard, every type, as data.
    private var savedClipboard: [[NSPasteboard.PasteboardType: Data]] = []

    // Copying overwrites the general pasteboard; put back exactly what the user had.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        savedClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    override func tearDown() async throws {
        app?.terminate()
        let pb = NSPasteboard.general
        pb.clearContents()  // even if it was empty
        let items = savedClipboard.map { saved in
            let item = NSPasteboardItem()
            for (t, d) in saved { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
        try await super.tearDown()
    }

    /// Launches the app with the panel up. `debugMode` NO keeps a test from
    /// ever writing a search log, except the one test that checks where it goes.
    func launch(debugMode: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        guard let socket = env["FSEARCH_SOCKET"], !socket.isEmpty else {
            if env["FSEARCH_UI_REQUIRED"] == "1" { XCTFail("FSEARCH_SOCKET missing: run scripts/ui-smoke.sh") }
            throw XCTSkip("run scripts/ui-smoke.sh (needs TEST_RUNNER_FSEARCH_SOCKET)")
        }
        app = XCUIApplication()
        app.launchArguments = ["-UITestShowPanel", "-FSEARCH_SOCKET", socket, "-debugMode", debugMode ? "YES" : "NO"]
        app.launch()
        app.activate()
        let found = field.waitForExistence(timeout: 15)
        XCTAssertTrue(found, found ? "" : "state=\(app.state.rawValue) tree=\(app.debugDescription)")
    }

    /// Synthesized keys go to whatever app is frontmost. Send one only while
    /// FSearch is in front (and, for typing, its field has the keyboard), so a
    /// test can never type into another app the user has open.
    func requireFocus(field needsField: Bool, file: StaticString = #filePath, line: UInt = #line) {
        if app.state != .runningForeground { app.activate() }
        guard app.wait(for: .runningForeground, timeout: 5) else {
            return XCTFail("FSearch isn't frontmost: not sending keys", file: file, line: line)
        }
        guard needsField else { return }
        let focused = NSPredicate { _, _ in MainActor.assumeIsolated { self.field.exists && self.field.value(forKey: "hasKeyboardFocus") as? Bool == true } }
        if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: nil)], timeout: 5) != .completed {
            XCTFail("the search field doesn't have the keyboard: not sending keys", file: file, line: line)
        }
    }

    /// A key into the search field.
    func press(_ key: XCUIKeyboardKey, _ mods: XCUIElement.KeyModifierFlags = [], file: StaticString = #filePath, line: UInt = #line) {
        requireFocus(field: true, file: file, line: line)
        field.typeKey(key, modifierFlags: mods)
    }

    func press(_ key: String, _ mods: XCUIElement.KeyModifierFlags, file: StaticString = #filePath, line: UInt = #line) {
        requireFocus(field: true, file: file, line: line)
        field.typeKey(key, modifierFlags: mods)
    }

    /// A key to the app while something else of ours (a menu, Quick Look) has the keyboard.
    func pressInApp(_ key: XCUIKeyboardKey, _ mods: XCUIElement.KeyModifierFlags = [], file: StaticString = #filePath, line: UInt = #line) {
        requireFocus(field: false, file: file, line: line)
        app.typeKey(key, modifierFlags: mods)
    }

    func pressInApp(_ key: String, _ mods: XCUIElement.KeyModifierFlags, file: StaticString = #filePath, line: UInt = #line) {
        requireFocus(field: false, file: file, line: line)
        app.typeKey(key, modifierFlags: mods)
    }

    /// A click on one of our elements, only while FSearch is in front.
    func click(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        requireFocus(field: false, file: file, line: line)
        e.click()
    }

    /// Replaces the query, retyping if another app stole keystrokes (the
    /// runner shares the desktop with whatever else is open).
    func search(_ q: String, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 {
            press("a", .command, file: file, line: line)
            if q.isEmpty { press(.delete, file: file, line: line) } else {
                requireFocus(field: true, file: file, line: line)
                field.typeText(q)
            }
            if (field.value as? String ?? "") == q { return }
            app.activate()
        }
        XCTFail("couldn't type \(q): field shows \(field.value as? String ?? "nil")", file: file, line: line)
    }

    func text(_ label: String) -> XCUIElement { app.staticTexts[label] }

    /// A static text showing `s` somewhere (SwiftUI puts a Text's string in its value).
    func text(containing s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", s, s)).firstMatch
    }

    func waitFor(_ e: XCUIElement, _ timeout: TimeInterval = 20, _ file: StaticString = #filePath, _ line: UInt = #line) {
        let ok = e.waitForExistence(timeout: timeout)
        XCTAssertTrue(ok, "never appeared: \(e)\n" + tree(), file: file, line: line)
    }

    func waitUntil(_ timeout: TimeInterval = 10, _ what: String, _ cond: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let p = NSPredicate { _, _ in MainActor.assumeIsolated { cond() } }
        let r = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: nil)], timeout: timeout)
        XCTAssertEqual(r, .completed, what + "\n" + tree(), file: file, line: line)
    }

    /// Asserts `e` does not show up within `timeout` (for things that must stay absent).
    func assertStaysAbsent(_ e: XCUIElement, _ timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(e.waitForExistence(timeout: timeout), "unexpected: \(e)", file: file, line: line)
    }

    var clipboard: String? { NSPasteboard.general.string(forType: .string) }

    /// The accessibility tree without the menu bar noise.
    func tree() -> String {
        app.debugDescription.components(separatedBy: "\n")
            .filter { !$0.contains("MenuItem") && !$0.contains("Menu,") && !$0.contains("MenuBarItem") }
            .joined(separator: "\n")
    }

    /// Switches to "Search inside files" from the fallback rows, by keyboard.
    /// `query` must match no file name, so the first row is the fallback.
    func enterContentMode(_ query: String) {
        search(query)
        waitFor(text("Search inside files"))
        // ↵ must land on the fallback row, never on a file (which it would open).
        XCTAssertFalse(text("Files").exists, "a file matched \(query): not pressing ↵")
        press(.return)
        waitFor(text("Inside files"))
    }
}
