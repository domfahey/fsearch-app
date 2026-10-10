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

/// The app's own "Open FSearch at login" item (SMAppService.mainApp). The real
/// one is `SMAppLoginItemService`; tests use a fake. nil in test mode: never touched.
@MainActor
protocol LoginItemService: AnyObject {
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
    func hide(returnFocus: Bool)
}

/// Bringing FSearch to the front. In the unit-test host the real closure does
/// nothing, for every test, so showing the panel or onboarding never takes
/// focus from the user's apps (tests need not remember to stub it).
@MainActor
enum AppActivation {
    static var activate: @MainActor () -> Void = live()

    /// `inert` is read on every call: the unit-test host never activates.
    static func live(inert: @escaping @MainActor () -> Bool = { Presentation.inert },
                     activate real: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }) -> @MainActor () -> Void {
        { if !inert() { real() } }
    }
}

/// Putting our windows on screen. The unit-test host (AppTests) shares the
/// desktop with whatever the user is doing, so there every window is ordered
/// in fully transparent and deaf to the mouse, and none can become key.
@MainActor
enum Presentation {
    /// True in the AppTests host.
    static var inert: Bool { LaunchOptions.current.unitTestHost }

    /// Shows `w` and makes it key; the inert host only orders it in, invisibly.
    static func present(_ w: NSWindow, inert: Bool = Presentation.inert) {
        if inert {
            w.alphaValue = 0
            w.ignoresMouseEvents = true
            w.orderFrontRegardless()
        } else {
            w.alphaValue = 1
            w.ignoresMouseEvents = false
            w.makeKeyAndOrderFront(nil)
        }
    }
}

/// A window that can never become key or main in the unit-test host.
final class HostSafeWindow: NSWindow {
    override var canBecomeKey: Bool { !LaunchOptions.current.unitTestHost && super.canBecomeKey }
    override var canBecomeMain: Bool { !LaunchOptions.current.unitTestHost && super.canBecomeMain }
}
