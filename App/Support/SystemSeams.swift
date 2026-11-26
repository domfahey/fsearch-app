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
/// The question is identity: is the app at this path the editor the user chose, or another app
/// claiming its bundle id? The code directory, main executable and Info.plist answer that, so the
/// bundle's resources (thousands of files in an Electron editor, gigabytes in Xcode) are not
/// re-hashed; macOS checks a bundle's seal itself when it launches it. Answers are cached per path
/// and requirement until the app's signature or executable changes, so moving through results
/// costs nothing after the first check.
@MainActor
enum CodeSignature {
    /// The validation flags: every architecture, strict, without hashing resources.
    static let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSDoNotValidateResources)
    /// How many real validations ran (not cache hits); tests read it.
    private(set) static var validations = 0

    private struct Key: Hashable {
        let path: String
        let requirement: String
        let stamp: [Date?]
    }
    private static var cache: [Key: Bool] = [:]

    /// Forgets every cached answer; tests call it.
    static func resetCache() {
        cache = [:]
        validations = 0
    }

    /// Whether the app at `app` has a valid static signature, on every architecture, that satisfies `requirement`.
    static func satisfies(_ app: URL, requirement: String) -> Bool {
        let key = Key(path: app.path, requirement: requirement, stamp: stamp(app))
        if let hit = cache[key] { return hit }
        let ok = validate(app, requirement: requirement)
        cache[key] = ok
        return ok
    }

    /// Modification dates that change when the app is replaced, updated or re-signed.
    private static func stamp(_ app: URL) -> [Date?] {
        let contents = app.appendingPathComponent("Contents")
        return [app, contents.appendingPathComponent("_CodeSignature/CodeResources"), contents.appendingPathComponent("MacOS")]
            .map { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
    }

    private static func validate(_ app: URL, requirement: String) -> Bool {
        validations += 1
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req
        else { return false }
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }
}
