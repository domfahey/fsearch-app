import AppKit
import XCTest

/// Why a helper refused to send an event; thrown so the caller stops there.
struct UITestRefusal: Error, CustomStringConvertible {
    let description: String
    init(_ why: String, file: StaticString, line: UInt) { description = "\(why) (\(file):\(line))" }
}

/// Launches the real app in test mode against the throwaway daemon that
/// scripts/ui-smoke.sh starts (temp HOME and FSEARCH_ROOT with fixtures).
///
/// Xcode runs UI tests in a sandboxed runner that cannot start the daemon,
/// so the script passes `TEST_RUNNER_FSEARCH_SOCKET`. It also sets
/// `TEST_RUNNER_FSEARCH_UI_REQUIRED=1`, which makes a missing socket a failure
/// rather than a skip. Every test launches its own app: tests are independent.
///
/// The app under test has the same bundle id as a FSearch the user runs, and
/// `XCUIApplication.launch()` quits any running copy of it. `launch()` below
/// refuses to start while a FSearch from anywhere but this build is running.
/// In test mode the app keeps its settings in a throwaway defaults suite and
/// records file actions instead of performing them, but AppKit's window-frame
/// autosave (e.g. the Settings window) still lands in com.domfahey.fsearch.
@MainActor
class PanelUITestCase: XCTestCase {
    var app: XCUIApplication!
    var field: XCUIElement { app.textFields["searchField"] }
    /// Every item on the general pasteboard, every type, as data.
    private var savedClipboard: [[NSPasteboard.PasteboardType: Data]] = []
    /// The pasteboard's change count before the test, and after the last copy
    /// the test saw land (a path under the fixtures). Restored only if it
    /// still is that: anything newer is the user's, and is left alone.
    private var changeCountAtStart = 0
    private var changeCountAfterOwnCopy: Int?
    private var socket = ""

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        let pb = NSPasteboard.general
        changeCountAtStart = pb.changeCount
        changeCountAfterOwnCopy = nil
        savedClipboard = (pb.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    override func tearDown() async throws {
        app?.terminate()
        restoreClipboardIfStillOurs()
        try await super.tearDown()
    }

    /// Puts back what the user had, only if the last change was the test's own copy.
    private func restoreClipboardIfStillOurs() {
        let pb = NSPasteboard.general
        guard let ours = changeCountAfterOwnCopy, pb.changeCount == ours, ours != changeCountAtStart else { return }
        pb.clearContents()
        let items = savedClipboard.map { saved in
            let item = NSPasteboardItem()
            for (t, d) in saved { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// The fixtures' root (`$H/root`), from the socket at `$H/Library/Application Support/FSearch/`.
    var fixtureRoot: String {
        var u = URL(fileURLWithPath: socket)
        for _ in 0..<4 { u.deleteLastPathComponent() }
        return u.appendingPathComponent("root").path
    }

    /// What the app's test-mode workspace recorded instead of opening anything.
    var recordedActions: [String] {
        let log = URL(fileURLWithPath: socket).deletingLastPathComponent().appendingPathComponent("actions.log")
        return ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    /// Launches the app with the panel up. `debugMode` NO keeps a test from
    /// ever writing a search log, except the one test that checks where it goes.
    func launch(debugMode: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        let env = ProcessInfo.processInfo.environment
        guard let s = env["FSEARCH_SOCKET"], !s.isEmpty else {
            if env["FSEARCH_UI_REQUIRED"] == "1" { XCTFail("FSEARCH_SOCKET missing: run scripts/ui-smoke.sh") }
            throw XCTSkip("run scripts/ui-smoke.sh (needs TEST_RUNNER_FSEARCH_SOCKET)")
        }
        socket = s
        try refuseIfTheUsersFSearchIsRunning(file: file, line: line)
        app = XCUIApplication()
        app.launchArguments = ["-UITestShowPanel", "-FSEARCH_SOCKET", s, "-debugMode", debugMode ? "YES" : "NO"]
        app.launch()
        app.activate()
        let found = field.waitForExistence(timeout: 15)
        XCTAssertTrue(found, found ? "" : "state=\(app.state.rawValue) tree=\(app.debugDescription)")
    }

    /// `launch()` quits every running app with our bundle id. One that isn't
    /// this build's (in the products folder next to the test runner) is the
    /// user's: stop instead of quitting it.
    private func refuseIfTheUsersFSearchIsRunning(file: StaticString, line: UInt) throws {
        // .../Debug/AppUITests-Runner.app/Contents/PlugIns/AppUITests.xctest
        var products = Bundle(for: PanelUITestCase.self).bundleURL
        for _ in 0..<4 { products.deleteLastPathComponent() }
        let ours = products.standardizedFileURL.path + "/"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.domfahey.fsearch")
            .filter { !$0.isTerminated && !($0.bundleURL?.standardizedFileURL.path.hasPrefix(ours) ?? false) }
        if !others.isEmpty {
            throw UITestRefusal(
                "FSearch is running from \(others.compactMap { $0.bundleURL?.path }): quit it first; launching the test app would quit it",
                file: file, line: line)
        }
    }

    /// Synthesized keys go to whatever app is frontmost. Send one only while
    /// FSearch is in front (and, for typing, its field has the keyboard), so a
    /// test can never type into another app the user has open. Throws, so the
    /// caller never sends the event when the check fails.
    func requireFocus(field needsField: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        if app.state != .runningForeground { app.activate() }
        guard app.wait(for: .runningForeground, timeout: 5) else {
            throw UITestRefusal("FSearch isn't frontmost: not sending keys", file: file, line: line)
        }
        guard needsField else { return }
        let focused = NSPredicate { _, _ in MainActor.assumeIsolated { self.fieldHasKeyboard } }
        if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: nil)], timeout: 5) != .completed {
            throw UITestRefusal("the search field doesn't have the keyboard: not sending keys", file: file, line: line)
        }
    }

    private var fieldHasKeyboard: Bool { field.exists && field.value(forKey: "hasKeyboardFocus") as? Bool == true }

    /// A key into the search field.
    func press(_ key: XCUIKeyboardKey, _ mods: XCUIElement.KeyModifierFlags = [], file: StaticString = #filePath, line: UInt = #line) throws
    {
        try requireFocus(field: true, file: file, line: line)
        field.typeKey(key, modifierFlags: mods)
    }

    func press(_ key: String, _ mods: XCUIElement.KeyModifierFlags, file: StaticString = #filePath, line: UInt = #line) throws {
        try requireFocus(field: true, file: file, line: line)
        field.typeKey(key, modifierFlags: mods)
    }

    /// A key to the app while something else of ours (a menu, Quick Look) has the keyboard.
    func pressInApp(_ key: XCUIKeyboardKey, _ mods: XCUIElement.KeyModifierFlags = [], file: StaticString = #filePath, line: UInt = #line)
        throws
    {
        try requireFocus(field: false, file: file, line: line)
        app.typeKey(key, modifierFlags: mods)
    }

    func pressInApp(_ key: String, _ mods: XCUIElement.KeyModifierFlags, file: StaticString = #filePath, line: UInt = #line) throws {
        try requireFocus(field: false, file: file, line: line)
        app.typeKey(key, modifierFlags: mods)
    }

    /// A click on one of our elements, only while FSearch is in front.
    func click(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        try requireFocus(field: false, file: file, line: line)
        e.click()
    }

    /// Types into the field one character at a time, checking focus before
    /// each, so a focus change mid-word sends nothing more.
    func type(_ s: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for ch in s {
            try requireFocus(field: true, file: file, line: line)
            field.typeText(String(ch))
        }
    }

    /// Replaces the query, retyping if another app stole keystrokes (the
    /// runner shares the desktop with whatever else is open).
    func search(_ q: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for _ in 0..<3 {
            try press("a", .command, file: file, line: line)
            if q.isEmpty { try press(.delete, file: file, line: line) } else { try type(q, file: file, line: line) }
            if (field.value as? String ?? "") == q { return }
            app.activate()
        }
        throw UITestRefusal("couldn't type \(q): field shows \(field.value as? String ?? "nil")", file: file, line: line)
    }

    func text(_ label: String) -> XCUIElement { app.staticTexts[label] }

    /// A static text showing `s` somewhere (SwiftUI puts a Text's string in its value).
    func text(containing s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", s, s)).firstMatch
    }

    /// Any element with this accessibility identifier.
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// The general pasteboard's string. Reading one of the fixtures' paths
    /// marks it as the test's own copy, so tearDown may put the user's back.
    var clipboard: String? {
        let pb = NSPasteboard.general
        let s = pb.string(forType: .string)
        if let s, !socket.isEmpty, s.hasPrefix(fixtureRoot + "/") { changeCountAfterOwnCopy = pb.changeCount }
        return s
    }

    func waitFor(_ e: XCUIElement, _ timeout: TimeInterval = 20, _ file: StaticString = #filePath, _ line: UInt = #line) {
        let ok = e.waitForExistence(timeout: timeout)
        XCTAssertTrue(ok, "never appeared: \(e)\n" + tree(), file: file, line: line)
    }

    func waitUntil(
        _ timeout: TimeInterval = 10, _ what: String, _ cond: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        let p = NSPredicate { _, _ in MainActor.assumeIsolated { cond() } }
        let r = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: nil)], timeout: timeout)
        XCTAssertEqual(r, .completed, what + "\n" + tree(), file: file, line: line)
    }

    /// Asserts `e` does not show up within `timeout` (for things that must stay absent).
    func assertStaysAbsent(_ e: XCUIElement, _ timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(e.waitForExistence(timeout: timeout), "unexpected: \(e)", file: file, line: line)
    }

    /// The accessibility tree without the menu bar noise.
    func tree() -> String {
        app.debugDescription.components(separatedBy: "\n")
            .filter { !$0.contains("MenuItem") && !$0.contains("Menu,") && !$0.contains("MenuBarItem") }
            .joined(separator: "\n")
    }

    /// Presses ↵ on a fallback row (`fallback-content`, `fallback-symbols` or a `command-…` row)
    /// only once the name search has finished (no late file row can take the
    /// selection) and that row is the selected one. Even if a file row were
    /// selected, the test-mode workspace would only record the open.
    func pressReturnOnFallback(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let header = element("fallbacks"), row = element(id)
        waitUntil(10, "the name search finished", { header.value as? String == "done" }, file: file, line: line)
        waitUntil(5, "\(id) is selected", { row.value as? String == "selected" }, file: file, line: line)
        guard header.value as? String == "done", row.value as? String == "selected" else {
            throw UITestRefusal("\(id) isn't the selected row: not pressing ↵", file: file, line: line)
        }
        try press(.return, file: file, line: line)
    }

    /// Switches to "Search inside files" from the fallback rows, by keyboard.
    /// `query` must match no file name, so the first row is the fallback.
    func enterContentMode(_ query: String, file: StaticString = #filePath, line: UInt = #line) throws {
        try search(query, file: file, line: line)
        waitFor(text("Search inside files"), 20, file, line)
        try pressReturnOnFallback("fallback-content", file: file, line: line)
        waitFor(text("Inside files"), 20, file, line)
    }
}
