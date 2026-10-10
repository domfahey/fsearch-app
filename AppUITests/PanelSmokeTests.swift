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
    private var savedClipboard: String?

    // ⌘⇧C overwrites the general pasteboard; put the user's text back afterwards.
    override func setUp() {
        super.setUp()
        savedClipboard = NSPasteboard.general.string(forType: .string)
    }

    override func tearDown() {
        if let s = savedClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
        }
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
