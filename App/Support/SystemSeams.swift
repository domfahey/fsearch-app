import AppKit
import FSearchKit
import Foundation
import Security
import ServiceManagement

// The real implementations of the seams in Seams.swift. Each is a thin
// pass-through to a system API with side effects outside the app (login
// items, System Settings, launching apps, Trash), so tests never run them.

/// The bundled helper's login item.
@MainActor
final class SMAppHelperService: HelperService {
    /// The helper's launch agent, registered from the app bundle (Contents/Library/LaunchAgents).
    private var service: SMAppService { .agent(plistName: DaemonManager.agentPlistName) }

    var status: DaemonPlan.ServiceStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openSystemSettingsLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

/// The app's own login item (the main app, not the helper).
@MainActor
final class SMAppLoginItemService: LoginItemService {
    private var service: SMAppService { .mainApp }

    var status: DaemonPlan.ServiceStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openSystemSettingsLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}

/// NSWorkspace and FileManager's Trash. No child processes: an app FSearch
/// started itself would run with FSearch's Full Disk Access.
@MainActor
final class SystemWorkspace: Workspace {
    private var ws: NSWorkspace { .shared }

    @discardableResult func open(_ url: URL) -> Bool { ws.open(url) }

    func open(_ urls: [URL], withApplicationAt app: URL, completion: (@Sendable (Error?) -> Void)?) {
        ws.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in completion?(error) }
    }

    func activateFileViewerSelecting(_ urls: [URL]) { ws.activateFileViewerSelecting(urls) }
    func urlForApplication(withBundleIdentifier id: String) -> URL? { ws.urlForApplication(withBundleIdentifier: id) }
    func urlsForApplications(toOpen url: URL) -> [URL] { ws.urlsForApplications(toOpen: url) }

    func isTrustedApp(at app: URL, requirement: String) -> Bool { CodeSignature.satisfies(app, requirement: requirement) }

    func fileInfo(atPath path: String) -> FileInfo? { FileInfo.onDisk(path) }

    func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}

/// Static code-signature checks (read-only: nothing is launched).
///
/// Two checks, so moving through results never waits on a large bundle:
/// - The identity check (code directory, main executable, Info.plist; not resources) answers at
///   once: is this the editor the user chose, or another app claiming its bundle id?
/// - The full check, resources included (an Electron editor's code is a resource), then runs once
///   off the main thread. Until it finishes, the identity answer stands; once it fails, the app is
///   not trusted.
///
/// Answers are cached per path and requirement until the app changes. The cache key uses status
/// change times (ctime), which a process can't set back the way it can modification times.
@MainActor
enum CodeSignature {
    /// Identity only: every architecture, strict, without hashing resources.
    nonisolated static let identityFlags = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSDoNotValidateResources)
    /// Everything, resources included.
    nonisolated static let fullFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)

    /// Which check ran; tests read ``checks``.
    enum Check: Equatable { case identity, full }
    /// Every check that ran, in order (not cache hits).
    private(set) static var checks: [Check] = []
    /// Validates `app` against `requirement` with `flags`; tests replace it.
    static var validator: @Sendable (URL, String, SecCSFlags) -> Bool = validate

    private struct Key: Hashable {
        let path: String
        let requirement: String
        let stamp: [timespec?]
        static func == (a: Key, b: Key) -> Bool {
            a.path == b.path && a.requirement == b.requirement
                && a.stamp.map { $0.map { [$0.tv_sec, $0.tv_nsec] } } == b.stamp.map { $0.map { [$0.tv_sec, $0.tv_nsec] } }
        }
        func hash(into h: inout Hasher) {
            h.combine(path)
            h.combine(requirement)
            for t in stamp { h.combine(t?.tv_sec); h.combine(t?.tv_nsec) }
        }
    }
    private static var identity: [Key: Bool] = [:]
    private static var full: [Key: Bool] = [:]
    private static var pending: [Key: Task<Void, Never>] = [:]

    /// Forgets every answer and restores the real validator; tests call it.
    static func reset() {
        identity = [:]
        full = [:]
        pending = [:]
        checks = []
        validator = validate
    }

    /// Waits for every full check in flight; tests call it.
    static func settle() async {
        while let task = pending.values.first { await task.value }
    }

    /// Whether the app at `app` has a valid static signature, on every architecture, that satisfies
    /// `requirement`: the full check's answer once it has one, else the identity check's.
    static func satisfies(_ app: URL, requirement: String) -> Bool {
        let key = Key(path: app.path, requirement: requirement, stamp: stamp(app))
        if let ok = full[key] { return ok }
        let ok: Bool
        if let cached = identity[key] {
            ok = cached
        } else {
            checks.append(.identity)
            ok = validator(app, requirement, identityFlags)
            identity[key] = ok
        }
        if ok && pending[key] == nil { startFullCheck(app, requirement: requirement, key: key) }
        return ok
    }

    private static func startFullCheck(_ app: URL, requirement: String, key: Key) {
        checks.append(.full)
        let validator = validator
        pending[key] = Task {
            let ok = await Task.detached(priority: .utility) { validator(app, requirement, fullFlags) }.value
            full[key] = ok
            pending[key] = nil
            if !ok { Log.actions.error("\(app.path, privacy: .private) failed its full code signature check") }
        }
    }

    /// Status change times that move when the app is replaced, updated, re-signed or edited.
    private static func stamp(_ app: URL) -> [timespec?] {
        let contents = app.appendingPathComponent("Contents")
        return [
            app, contents, contents.appendingPathComponent("_CodeSignature/CodeResources"), contents.appendingPathComponent("MacOS"),
            contents.appendingPathComponent("Resources"),
        ].map { url in
            var st = stat()
            return stat(url.path, &st) == 0 ? st.st_ctimespec : nil
        }
    }

    nonisolated private static func validate(_ app: URL, requirement: String, flags: SecCSFlags) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req
        else { return false }
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }
}
