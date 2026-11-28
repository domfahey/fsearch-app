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

/// Convenience builders for wire replies in tests.
enum Wire {
    static func status(entries: Int = 42, fullDiskAccess: Bool = true, owner: Bool = true) -> DaemonStatus {
        DaemonStatus(
            entries: entries, dirs: 3, overlay: 1, removed: 0, eventId: 7, indexBytes: 2048,
            contentDocs: 5, contentSegments: 1, contentBytes: 4096, contentPending: 0,
            fullDiskAccess: fullDiskAccess, owner: owner)
    }

    static func grep(_ files: [(String, [(Int, String)])], tookUs: UInt64 = 900) -> GrepReply {
        let fm = files.map { path, ms in FileMatches(path: path, matches: ms.map { Match(line: $0.0, text: $0.1) }) }
        return GrepReply(tookUs: tookUs, source: "index", candidates: files.count, read: files.count, complete: true, files: fm)
    }

    static func hit(_ path: String) -> Hit { Hit(path: path, kind: "file", size: 1, mtime: 0, score: 1) }
}

/// One-shot async barrier for tests, without blocking a Swift concurrency pool thread.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                waiters.append(c)
                return false
            }
            if resumeNow { c.resume() }
        }
    }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            released = true
            let w = waiters
            waiters.removeAll()
            return w
        }
        for c in pending { c.resume() }
    }
}

/// A scripted daemon connection. Handlers get the 1-based call number.
final class StubDaemon: DaemonControl, @unchecked Sendable {
    private let lock = NSLock()
    private var _onPing: @Sendable (Int) -> Bool = { _ in true }
    private var _onStatus: @Sendable (Int) throws -> DaemonStatus = { _ in Wire.status() }
    private var _onStatusAsync: (@Sendable (Int) async throws -> DaemonStatus)?
    private var _onSearch: @Sendable (String) throws -> SearchReply = { _ in SearchReply(tookUs: 1000, hits: []) }
    private var _onSearchAsync: (@Sendable (String) async throws -> SearchReply)?
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
    var onStatusAsync: (@Sendable (Int) async throws -> DaemonStatus)? {
        get { locked { _onStatusAsync } }
        set { locked { _onStatusAsync = newValue } }
    }
    var onSearch: @Sendable (String) throws -> SearchReply {
        get { locked { _onSearch } }
        set { locked { _onSearch = newValue } }
    }
    var onSearchAsync: (@Sendable (String) async throws -> SearchReply)? {
        get { locked { _onSearchAsync } }
        set { locked { _onSearchAsync = newValue } }
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
        let (n, f, fa) = locked {
            _statuses += 1; return (_statuses, _onStatus, _onStatusAsync)
        }
        if let fa { return try await fa(n) }
        return try f(n)
    }

    func save() async throws { locked { _saves += 1 } }

    func search(_ q: String, limit: Int) async throws -> SearchReply {
        let (f, fa) = locked {
            _searches.append(q); return (_onSearch, _onSearchAsync)
        }
        if let fa { return try await fa(q) }
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
    var onUnregister: (() async throws -> Void)?
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

    /// Like SMAppService, unregistering takes a while: callers suspend here.
    func unregister() async throws {
        unregistered += 1
        try await onUnregister?()
        await Task.yield()
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
    /// The apps registered for a URL scheme (`vscode`), which urlsForApplications(toOpen:) returns for such a URL.
    var schemeHandlers: [String: [URL]] = [:]
    var openWithError: Error?
    var defaultOpenSucceeds = true
    /// Paths that don't exist. Any other path that isn't on disk either is a
    /// plain file, so tests can use made-up paths like /p/x.txt.
    var missing: Set<String> = []
    /// Canned `FileInfo` overrides by path (checked after `missing`, before disk).
    var fileInfos: [String: FileInfo] = [:]
    var trashError: Error?
    /// Apps whose code signature check fails. Any other app passes.
    var untrustedApps: Set<URL> = []
    /// The requirements `isTrustedApp` was asked about.
    private(set) var checkedRequirements: [String] = []

    private(set) var opened: [URL] = []
    private(set) var openedWith: [(urls: [URL], app: URL)] = []
    private(set) var revealed: [[URL]] = []
    private(set) var trashed: [URL] = []
    /// LaunchServices lookups by bundle id.
    private(set) var appLookups = 0

    @discardableResult func open(_ url: URL) -> Bool {
        opened.append(url)
        return defaultOpenSucceeds
    }

    /// Like NSWorkspace, the completion runs off the main thread.
    func open(_ urls: [URL], withApplicationAt app: URL, completion: (@Sendable (Error?) -> Void)?) {
        openedWith.append((urls, app))
        let error = openWithError.map { $0 as NSError }
        DispatchQueue.global().async { completion?(error) }
    }

    func activateFileViewerSelecting(_ urls: [URL]) { revealed.append(urls) }
    func urlForApplication(withBundleIdentifier id: String) -> URL? {
        appLookups += 1
        return apps[id]
    }
    func urlsForApplications(toOpen url: URL) -> [URL] {
        url.isFileURL ? appsToOpen : schemeHandlers[url.scheme ?? ""] ?? []
    }

    func fileInfo(atPath path: String) -> FileInfo? {
        if missing.contains(path) { return nil }
        if let info = fileInfos[path] { return info }
        return FileInfo.onDisk(path) ?? FileInfo()
    }

    func isTrustedApp(at app: URL, requirement: String) -> Bool {
        checkedRequirements.append(requirement)
        return !untrustedApps.contains(app)
    }

    func trash(_ url: URL) throws {
        if let trashError { throw trashError }
        trashed.append(url)
    }
}

@MainActor
final class FakePanel: PanelHost {
    var isVisible = false
    private(set) var shows = 0, hides = 0, externalShows = 0
    private(set) var openedSearches: [SearchURL] = []
    func toggle(app: AppState) { isVisible ? hide(returnFocus: true) : show(app: app) }
    func show(app: AppState) { shows += 1; isVisible = true }
    func showExternally(app: AppState) {
        externalShows += 1
        show(app: app)
    }
    func show(app: AppState, search: SearchURL) {
        shows += 1
        isVisible = true
        openedSearches.append(search)
    }
    func hide(returnFocus: Bool) { hides += 1; isVisible = false }
}

/// One app with fakes everywhere, an isolated throwaway defaults suite inside its
/// own temp folder (so cfprefsd never bleeds state across tests and never touches
/// `~/Library/Preferences`).
@MainActor
final class TestEnv {
    /// Per-process temp directory holding standalone test suites, deleted on process exit.
    private nonisolated static let suitesDir: URL = {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("com.domfahey.fsearch.apptests.suites-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: TestEnv.suitesDir) }
        return dir
    }()
    /// Fresh temp-directory suite path for standalone defaults tests outside `TestEnv`;
    /// isolated per call so `cfprefsd` never bleeds state across tests and never touches `~/Library/Preferences`.
    nonisolated static var unitSuite: String {
        suitesDir.appendingPathComponent("unit-\(UUID().uuidString.prefix(8))").path
    }
    let suite: String
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
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsa-unit-\(UUID().uuidString.prefix(8))")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suite = dir.appendingPathComponent("com.domfahey.fsearch.apptests.unit").path
        defaults = UserDefaults(suiteName: suite)!
        self.daemon = daemon
        self.helper = helper
        let options = LaunchOptions(
            socketPath: dir.path + "/Library/Application Support/FSearch/fsearch.sock",
            testMode: helper == nil, unitTestHost: false, showPanel: false,
            // With a helper this isn't test mode; keep the log out of ~/Library/Logs.
            searchLogOverride: dir.appendingPathComponent("searches.jsonl"))
        app = AppState(
            options: options, defaults: defaults, helper: helper,
            names: daemon, content: daemon, control: daemon, clock: clock.clock,
            cliAgentInstalled: { false })  // never the real ~/Library/LaunchAgents
        precondition(app.log.file.path.hasPrefix(dir.path), "TestEnv's search log escaped its temp folder")
        app.panel = panel
        app.status = MenuBarStatus(defaults: defaults)
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
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Once per run: cleans up any legacy plists an older checkout left in `~/Library/Preferences`.
    static let sweptStaleSuites: Void = {
        let prefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: prefs.path)) ?? []
        for n in names
        where n.hasPrefix("com.domfahey.fsearch.apptests.") && n.hasSuffix(".plist") {
            try? FileManager.default.removeItem(at: prefs.appendingPathComponent(n))
        }
    }()

    /// The suite, emptied and flushed, so cfprefsd holds no stale keys for it.
    nonisolated static func emptySuite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        if let domain = d.persistentDomain(forName: name) {
            for key in domain.keys {
                d.removeObject(forKey: key)
            }
        }
        d.removePersistentDomain(forName: name)
        d.synchronize()
        return d
    }

    nonisolated static func deletePlist(_ name: String) {
        let path =
            name.hasPrefix("/")
            ? name + ".plist"
            : FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(name).plist").path
        try? FileManager.default.removeItem(atPath: path)
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
func render<V: View>(_ view: V, size: NSSize = NSSize(width: 680, height: 460), settle: Duration = .milliseconds(40)) async -> NSWindow {
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
