import AppKit
import FSearchKit
import Foundation
import SwiftUI

@testable import FSearch

struct TestError: Error, LocalizedError {
    let message: String
    init(_ m: String = "boom") { message = m }
    var errorDescription: String? { message }
}

/// DaemonStatus and GrepReply have no public init: build them the way the wire does.
enum Wire {
    static func status(entries: Int = 42, fullDiskAccess: Bool = true, owner: Bool = true) -> DaemonStatus {
        let json = """
            {"ok":true,"entries":\(entries),"dirs":3,"overlay":1,"removed":0,"event_id":7,"index_bytes":2048,\
            "content_docs":5,"content_segments":1,"content_bytes":4096,"content_pending":0,\
            "full_disk_access":\(fullDiskAccess),"owner":\(owner)}
            """
        return try! decodeReply(Data(json.utf8), as: DaemonStatus.self)
    }

    static func grep(_ files: [(String, [(Int, String)])], tookUs: UInt64 = 900) -> GrepReply {
        let fs = files.map { path, ms in
            ["path": path, "matches": ms.map { ["line": $0.0, "text": $0.1] }] as [String: Any]
        }
        let o: [String: Any] = [
            "ok": true, "took_us": tookUs, "source": "index", "candidates": files.count,
            "read": files.count, "complete": true, "files": fs,
        ]
        return try! decodeReply(try! JSONSerialization.data(withJSONObject: o), as: GrepReply.self)
    }

    static func hit(_ path: String) -> Hit { Hit(path: path, kind: "file", size: 1, mtime: 0, score: 1) }
}

/// A scripted daemon connection. Handlers get the 1-based call number.
final class StubDaemon: DaemonControl, @unchecked Sendable {
    private let lock = NSLock()
    private var _onPing: @Sendable (Int) -> Bool = { _ in true }
    private var _onStatus: @Sendable (Int) throws -> DaemonStatus = { _ in Wire.status() }
    private var _onSearch: @Sendable (String) throws -> SearchReply = { _ in SearchReply(tookUs: 1000, hits: []) }
    private var _onGrep: @Sendable (String, String, GrepMode) throws -> GrepReply = { _, _, _ in Wire.grep([]) }
    private var _pings = 0, _statuses = 0, _saves = 0
    private var _searches: [String] = []
    private var _greps: [(q: String, pattern: String, mode: GrepMode)] = []

    private func locked<T>(_ f: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try f() }

    var onPing: @Sendable (Int) -> Bool {
        get { locked { _onPing } }
        set { locked { _onPing = newValue } }
    }
    var onStatus: @Sendable (Int) throws -> DaemonStatus {
        get { locked { _onStatus } }
        set { locked { _onStatus = newValue } }
    }
    var onSearch: @Sendable (String) throws -> SearchReply {
        get { locked { _onSearch } }
        set { locked { _onSearch = newValue } }
    }
    var onGrep: @Sendable (String, String, GrepMode) throws -> GrepReply {
        get { locked { _onGrep } }
        set { locked { _onGrep = newValue } }
    }
    var pings: Int { locked { _pings } }
    var statuses: Int { locked { _statuses } }
    var saves: Int { locked { _saves } }
    var searches: [String] { locked { _searches } }
    var greps: [(q: String, pattern: String, mode: GrepMode)] { locked { _greps } }

    func ping() async throws {
        let (n, f) = locked {
            _pings += 1; return (_pings, _onPing)
        }
        if !f(n) { throw DaemonError.disconnected }
    }

    func status() async throws -> DaemonStatus {
        let (n, f) = locked {
            _statuses += 1; return (_statuses, _onStatus)
        }
        return try f(n)
    }

    func save() async throws { locked { _saves += 1 } }

    func search(_ q: String, limit: Int) async throws -> SearchReply {
        let f = locked {
            _searches.append(q); return _onSearch
        }
        return try f(q)
    }

    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply {
        let f = locked {
            _greps.append((q, pattern, mode)); return _onGrep
        }
        return try f(q, pattern, mode)
    }
}

/// Virtual time: sleeping advances the clock at once.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = ContinuousClock.now
    private var _slept: [Duration] = []

    var slept: [Duration] { lock.lock(); defer { lock.unlock() }; return _slept }

    private func advance(_ d: Duration) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.advanced(by: d)
        _slept.append(d)
    }

    var clock: DaemonClock {
        DaemonClock(
            now: { [self] in
                lock.lock(); defer { lock.unlock() }; return _now
            },
            sleep: { [self] d in
                try Task.checkCancellation()
                advance(d)
                await Task.yield()
                try Task.checkCancellation()
            })
    }
}

@MainActor
final class FakeHelper: HelperService {
    var status: DaemonPlan.ServiceStatus
    /// Thrown by register(); `statusOnFailure` is the status left behind.
    var registerError: Error?
    var statusOnFailure: DaemonPlan.ServiceStatus?
    var statusAfterRegister: DaemonPlan.ServiceStatus = .enabled
    private(set) var registered = 0, unregistered = 0, openedSettings = 0

    init(_ status: DaemonPlan.ServiceStatus = .notRegistered) { self.status = status }

    func register() throws {
        registered += 1
        if let registerError {
            if let statusOnFailure { status = statusOnFailure }
            throw registerError
        }
        status = statusAfterRegister
    }

    func unregister() async throws {
        unregistered += 1
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() { openedSettings += 1 }
}

@MainActor
final class FakeLoginItem: LoginItemService {
    var status: DaemonPlan.ServiceStatus
    var registerError: Error?
    var unregisterError: Error?
    var statusAfterRegister: DaemonPlan.ServiceStatus = .enabled
    private(set) var registered = 0, unregistered = 0, openedSettings = 0

    init(_ status: DaemonPlan.ServiceStatus = .notRegistered) { self.status = status }

    func register() throws {
        registered += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() async throws {
        unregistered += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() { openedSettings += 1 }
}

@MainActor
final class FakeWorkspace: Workspace {
    var apps: [String: URL] = [:]
    var appsToOpen: [URL] = []
    var runStarts = true
    /// The exit status the started process reports; nil: it never exits.
    var runExitStatus: Int32? = 0
    var openWithError: Error?
    var trashError: Error?

    private(set) var opened: [URL] = []
    private(set) var openedWith: [(urls: [URL], app: URL)] = []
    private(set) var revealed: [[URL]] = []
    private(set) var runs: [(exe: String, args: [String])] = []
    private(set) var trashed: [URL] = []

    func open(_ url: URL) { opened.append(url) }

    /// Like NSWorkspace, the completion runs off the main thread.
    func open(_ urls: [URL], withApplicationAt app: URL, completion: (@Sendable (Error?) -> Void)?) {
        openedWith.append((urls, app))
        let error = openWithError.map { $0 as NSError }
        DispatchQueue.global().async { completion?(error) }
    }

    func activateFileViewerSelecting(_ urls: [URL]) { revealed.append(urls) }
    func urlForApplication(withBundleIdentifier id: String) -> URL? { apps[id] }
    func urlsForApplications(toOpen url: URL) -> [URL] { appsToOpen }

    func run(_ executable: String, _ arguments: [String], onExit: @escaping @Sendable (Int32) -> Void) -> Bool {
        runs.append((executable, arguments))
        guard runStarts else { return false }
        // Like Process.terminationHandler, off the main thread.
        if let s = runExitStatus { DispatchQueue.global().async { onExit(s) } }
        return true
    }

    func trash(_ url: URL) throws {
        if let trashError { throw trashError }
        trashed.append(url)
    }
}

@MainActor
final class FakePanel: PanelHost {
    var isVisible = false
    private(set) var shows = 0, hides = 0
    func show(app: AppState) { shows += 1; isVisible = true }
    func hide(returnFocus: Bool) { hides += 1; isVisible = false }
}

/// One app with fakes everywhere, a throwaway defaults suite and a temp folder.
@MainActor
final class TestEnv {
    let suite = "com.domfahey.fsearch.apptests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let dir: URL
    let daemon: StubDaemon
    let helper: FakeHelper?
    let clock = FakeClock()
    let workspace = FakeWorkspace()
    let panel = FakePanel()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.domfahey.fsearch.apptests.\(UUID().uuidString)"))
    let app: AppState

    init(helper: FakeHelper? = nil, daemon: StubDaemon = StubDaemon()) {
        _ = TestEnv.sweptStaleSuites
        defaults = UserDefaults(suiteName: suite)!
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsa-unit-\(UUID().uuidString.prefix(8))")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.daemon = daemon
        self.helper = helper
        let options = LaunchOptions(
            socketPath: dir.path + "/Library/Application Support/FSearch/fsearch.sock",
            testMode: helper == nil, unitTestHost: false, showPanel: false)
        app = AppState(
            options: options, defaults: defaults, helper: helper,
            names: daemon, content: daemon, control: daemon, clock: clock.clock,
            cliAgentInstalled: { false })  // never the real ~/Library/LaunchAgents
        app.panel = panel
        app.actionErrorDuration = .milliseconds(20)
        FileActions.workspace = workspace
        FileActions.pasteboard = pasteboard
        OnboardingLauncher.defaults = defaults
        // AppActivation needs no stub: in this host its real closure does nothing.
    }

    /// A real file in the temp folder (Recents only keeps files that exist).
    func file(_ name: String, _ body: String = "x") -> String {
        let url = dir.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! body.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func tearDown() {
        OnboardingLauncher.reset()
        FileActions.workspace = FakeWorkspace()
        FileActions.pasteboard = NSPasteboard(name: NSPasteboard.Name("com.domfahey.fsearch.apptests.idle"))
        pasteboard.releaseGlobally()
        TestEnv.removeSuite(suite)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Once per run: deletes suites an earlier, interrupted run left behind
    /// (never the app's own test-mode suite, which this host has open).
    static let sweptStaleSuites: Void = {
        let prefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: prefs.path)) ?? []
        for n in names
        where n.hasPrefix("com.domfahey.fsearch.apptests.") && n.hasSuffix(".plist")
            && n != AppDefaults.testSuiteName + ".plist"
        {
            try? FileManager.default.removeItem(at: prefs.appendingPathComponent(n))
        }
    }()

    /// Clears a throwaway suite and deletes the plist cfprefsd leaves behind.
    static func removeSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}

/// Waits (letting the main run loop turn) until `cond` holds, up to `timeout`.
@MainActor
func eventually(_ timeout: Duration = .seconds(3), _ cond: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if cond() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return cond()
}

/// Where render windows go: far off every screen (borderless windows aren't
/// pulled back onto one), so nothing shows even if alpha were ignored.
let offscreenOrigin = NSPoint(x: -20_000, y: -20_000)

/// Hosts a view so SwiftUI evaluates its body and runs its onAppear/task
/// modifiers, without anything the user could see or that could take the
/// keyboard: off screen, fully transparent, deaf to the mouse, never key.
/// Close the returned window when done.
@MainActor
func render<V: View>(_ view: V, size: NSSize = NSSize(width: 680, height: 460), settle: Duration = .milliseconds(150)) async -> NSWindow {
    let w = HostSafeWindow(
        contentRect: NSRect(origin: offscreenOrigin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: view)
    w.setFrameOrigin(offscreenOrigin)
    Presentation.present(w, inert: true)
    try? await Task.sleep(for: settle)
    w.contentView?.layoutSubtreeIfNeeded()
    return w
}
