import AppKit
import FSearchKit
import Foundation

/// The bundled helper's login item (SMAppService). The real one is
/// `SMAppHelperService`; tests use a fake. nil in test mode: never touched.
///
/// A seam so no test can register a real login item.
@MainActor
protocol HelperService: AnyObject {
    /// The registration state, as macOS reports it.
    var status: DaemonPlan.ServiceStatus { get }
    /// Registers the item; the user may still have to approve it.
    func register() throws
    /// Removes the registration.
    func unregister() async throws
    /// Opens System Settings at Login Items.
    func openSystemSettingsLoginItems()
}

/// The app's own "Open FSearch at login" item (SMAppService.mainApp). The real
/// one is `SMAppLoginItemService`; tests use a fake. nil in test mode: never touched.
@MainActor
protocol LoginItemService: AnyObject {
    /// The registration state, as macOS reports it.
    var status: DaemonPlan.ServiceStatus { get }
    /// Registers the item; the user may still have to approve it.
    func register() throws
    /// Removes the registration.
    func unregister() async throws
    /// Opens System Settings at Login Items.
    func openSystemSettingsLoginItems()
}

/// What DaemonManager needs from a daemon connection: searches, plus "Save Now".
protocol DaemonControl: SearchBackend {
    /// Asks the daemon to compact and save its index.
    func save() async throws
}

extension DaemonClient: DaemonControl {}

/// What file actions need to know about a path on disk.
struct FileInfo: Equatable, Sendable {
    /// A folder (packages included).
    var isDirectory = false
    /// The user may execute it.
    var isExecutable = false
    /// A folder Finder shows as one file: an app, an .rtfd, an .xcodeproj.
    var isPackage = false

    /// The path's info, or nil if nothing is there. Read-only.
    @MainActor
    static func onDisk(_ path: String) -> FileInfo? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        return FileInfo(
            isDirectory: isDir.boolValue, isExecutable: FileManager.default.isExecutableFile(atPath: path),
            isPackage: isDir.boolValue && NSWorkspace.shared.isFilePackage(atPath: path))
    }
}

/// Everything that sends the user to another app or changes files: opening
/// (editors too, through LaunchServices, never as a child process), revealing,
/// Trash. The real one is `SystemWorkspace`; test mode uses
/// `TestModeWorkspace`, which records instead of acting.
@MainActor
protocol Workspace: AnyObject {
    /// Opens a file or URL in its default app.
    func open(_ url: URL)
    /// `completion` gets the launch error, if any.
    func open(_ urls: [URL], withApplicationAt app: URL, completion: (@Sendable (Error?) -> Void)?)
    /// Reveals the files in Finder.
    func activateFileViewerSelecting(_ urls: [URL])
    /// The app with a bundle id, or nil if it isn't installed.
    func urlForApplication(withBundleIdentifier id: String) -> URL?
    /// The apps that can open a file.
    func urlsForApplications(toOpen url: URL) -> [URL]
    /// The file at `path`, or nil if it is gone.
    func fileInfo(atPath path: String) -> FileInfo?
    /// Moves a file to the Trash; throws if it can't.
    func trash(_ url: URL) throws
}

/// Timers, so the daemon's wait loops run instantly under test.
struct DaemonClock: Sendable {
    /// The current instant.
    var now: @Sendable () -> ContinuousClock.Instant
    /// Waits for a duration; throws if the task is cancelled.
    var sleep: @Sendable (Duration) async throws -> Void

    /// The real clock.
    static let live = DaemonClock(now: { ContinuousClock.now }, sleep: { try await Task.sleep(for: $0) })
}

/// The panel as AppState sees it: an action error brings it back.
@MainActor
protocol PanelHost: AnyObject {
    /// Whether the panel is on screen.
    var isVisible: Bool { get }
    /// Shows the panel, resuming the recent query.
    func show(app: AppState)
    /// Hides the panel; `returnFocus` is false when the user already moved to another app.
    func hide(returnFocus: Bool)
}

/// Bringing FSearch to the front. In the unit-test host the real closure does
/// nothing, for every test, so showing the panel or onboarding never takes
/// focus from the user's apps (tests need not remember to stub it).
@MainActor
enum AppActivation {
    /// What to call to bring the app forward; tests may replace it.
    static var activate: @MainActor () -> Void = live()

    /// Builds an activation closure.
    ///
    /// `inert` is read on every call (not captured once), so the answer is current when the closure runs;
    /// the unit-test host never activates.
    ///
    /// - Parameters:
    ///   - inert: Whether activation must be skipped.
    ///   - real: The real activation.
    static func live(
        inert: @escaping @MainActor () -> Bool = { Presentation.inert },
        activate real: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) -> @MainActor () -> Void {
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
    ///
    /// `orderFrontRegardless` puts a window on screen without making it key; zero alpha and ignoring mouse events keep it
    /// from showing or catching clicks.
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
///
/// Outside the host it behaves as a plain `NSWindow`.
final class HostSafeWindow: NSWindow {
    override var canBecomeKey: Bool { !LaunchOptions.current.unitTestHost && super.canBecomeKey }
    override var canBecomeMain: Bool { !LaunchOptions.current.unitTestHost && super.canBecomeMain }
}
