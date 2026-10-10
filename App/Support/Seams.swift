import AppKit
import FSearchKit
import Foundation

/// The bundled helper's login item (SMAppService). The real one is
/// `SMAppHelperService`; tests use a fake. nil in test mode: never touched.
@MainActor
protocol HelperService: AnyObject {
    var status: DaemonPlan.ServiceStatus { get }
    func register() throws
    func unregister() async throws
    func openSystemSettingsLoginItems()
}

/// What DaemonManager needs from a daemon connection: searches, plus "Save Now".
protocol DaemonControl: SearchBackend {
    func save() async throws
}

extension DaemonClient: DaemonControl {}

/// Everything that sends the user to another app or changes files: opening,
/// revealing, launching an editor's CLI, Trash. The real one is `SystemWorkspace`.
@MainActor
protocol Workspace: AnyObject {
    func open(_ url: URL)
    /// `completion` gets the launch error, if any.
    func open(_ urls: [URL], withApplicationAt app: URL, completion: (@Sendable (Error?) -> Void)?)
    func activateFileViewerSelecting(_ urls: [URL])
    func urlForApplication(withBundleIdentifier id: String) -> URL?
    func urlsForApplications(toOpen url: URL) -> [URL]
    /// Starts a process; `onExit` gets its status. False if it couldn't start.
    func run(_ executable: String, _ arguments: [String], onExit: @escaping @Sendable (Int32) -> Void) -> Bool
    func trash(_ url: URL) throws
}

/// Timers, so the daemon's wait loops run instantly under test.
struct DaemonClock: Sendable {
    var now: @Sendable () -> ContinuousClock.Instant
    var sleep: @Sendable (Duration) async throws -> Void

    static let live = DaemonClock(now: { ContinuousClock.now }, sleep: { try await Task.sleep(for: $0) })
}

/// The panel as AppState sees it: an action error brings it back.
@MainActor
protocol PanelHost: AnyObject {
    var isVisible: Bool { get }
    func show(app: AppState)
}

/// Bringing FSearch to the front. Hosted unit tests replace it with a no-op so
/// showing the panel or onboarding never takes focus from the user's apps.
@MainActor
enum AppActivation {
    static var activate: @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
}
