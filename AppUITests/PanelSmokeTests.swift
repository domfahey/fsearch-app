import Darwin
import AppKit
import XCTest

/// Types a query into the real panel against a real, throwaway daemon.
///
/// Xcode runs UI tests in a sandboxed runner that cannot write to /private/tmp,
/// so the daemon is normally started by the caller (scripts/ui-smoke.sh style):
/// pass `TEST_RUNNER_FSEARCH_SOCKET=<socket of a daemon started with a temp
/// HOME and FSEARCH_ROOT containing proj/heronfile.txt>`. Without it the test
/// tries to start the daemon itself (`TEST_RUNNER_FSEARCH_BIN`), which only
/// works where the runner is not sandboxed.
@MainActor
final class PanelSmokeTests: XCTestCase {
    /// Every item on the general pasteboard, every type, as data.
    private var savedClipboard: [[NSPasteboard.PasteboardType: Data]] = []

    // ⌘⇧C overwrites the general pasteboard; put back exactly what the user had.
    override func setUp() {
        super.setUp()
        savedClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    override func tearDown() {
        let pb = NSPasteboard.general
        pb.clearContents()  // even if it was empty
        let items = savedClipboard.map { saved in
            let item = NSPasteboardItem()
            for (t, d) in saved { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
        super.tearDown()
    }

    func testTypingShowsResults() throws {
        let env = ProcessInfo.processInfo.environment
        var socket = env["FSEARCH_SOCKET"]
        var cleanup: () -> Void = {}
        defer { cleanup() }

        if socket == nil {
            let bin = env["FSEARCH_BIN"] ?? ""
            try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: bin), "set FSEARCH_SOCKET or FSEARCH_BIN")
            let home = "/private/tmp/fsa-ui-\(UUID().uuidString.prefix(6))"
            let root = home + "/root"
            let daemon = Process()
            cleanup = {
                if daemon.isRunning {
                    daemon.terminate()
                    let deadline = Date().addingTimeInterval(5)
                    while daemon.isRunning && Date() < deadline { usleep(50_000) }
                    if daemon.isRunning { kill(daemon.processIdentifier, SIGKILL) }
                    daemon.waitUntilExit()
                }
                try? FileManager.default.removeItem(atPath: home)
            }
            try FileManager.default.createDirectory(atPath: root + "/proj", withIntermediateDirectories: true)
            try "x".write(toFile: root + "/proj/heronfile.txt", atomically: true, encoding: .utf8)
            daemon.executableURL = URL(fileURLWithPath: bin)
            daemon.arguments = ["serve"]
            daemon.environment = ["HOME": home, "FSEARCH_ROOT": root]
            daemon.standardOutput = FileHandle.nullDevice
            daemon.standardError = FileHandle.nullDevice
            try daemon.run()
            socket = home + "/Library/Application Support/FSearch/fsearch.sock"
        }

        let app = XCUIApplication()
        app.launchArguments = ["-UITestShowPanel", "-FSEARCH_SOCKET", socket!]
        app.launch()
        defer { app.terminate() }
        let field = app.textFields["searchField"]
        let found = field.waitForExistence(timeout: 10)
        XCTAssertTrue(found, found ? "" : "state=\(app.state.rawValue) tree=\(app.debugDescription)")
        field.typeText("heronfile")
        let row = app.staticTexts["heronfile.txt"].waitForExistence(timeout: 20)
        XCTAssertTrue(row, row ? "" : "value=\(field.value as? String ?? "nil") " + app.debugDescription.components(separatedBy: "\n").filter { !$0.contains("MenuItem") && !$0.contains("Menu,") && !$0.contains("MenuBarItem") }.joined(separator: "\n"))
        field.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string)?.hasSuffix("/proj/heronfile.txt"), true)

        // ⌘Y opens Quick Look over the launcher; ⌘Y again closes it and the field gets the keyboard back.
        let windows = app.windows.count
        field.typeKey("y", modifierFlags: .command)
        let previewUp = NSPredicate { _, _ in app.windows.count > windows }
        let opened = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: previewUp, object: nil)], timeout: 10) == .completed
        XCTAssertTrue(opened, "windows=\(app.windows.count) " + app.debugDescription)
        app.typeKey("y", modifierFlags: .command)
        let previewGone = NSPredicate { _, _ in app.windows.count == windows }
        let closed = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: previewGone, object: nil)], timeout: 10) == .completed
        XCTAssertTrue(closed, "windows=\(app.windows.count) " + app.debugDescription)
        let refocused = NSPredicate { _, _ in field.value(forKey: "hasKeyboardFocus") as? Bool == true }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: refocused, object: nil)], timeout: 5), .completed)

        // A path with a space and an emoji copies intact.
        field.typeKey("a", modifierFlags: .command)
        field.typeText("a b")
        let emojiRow = app.staticTexts["🏡 a b.txt"].waitForExistence(timeout: 20)
        XCTAssertTrue(emojiRow)
        field.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string)?.hasSuffix("/🏡 a b.txt"), true)

        // A bad query shows one line under the field, and results resume once it's fixed.
        field.typeKey("a", modifierFlags: .command)
        field.typeText("re:(")
        XCTAssertTrue(app.staticTexts["queryError"].waitForExistence(timeout: 5))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("heronfile")
        XCTAssertTrue(app.staticTexts["heronfile.txt"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["queryError"].exists)

        field.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(field.value as? String ?? "", "")
    }
}
