import AppKit
import FSearchKit
import Foundation
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

    func open(_ url: URL) { ws.open(url) }

    func open(_ urls: [URL], withApplicationAt app: URL, completion: (@Sendable (Error?) -> Void)?) {
        ws.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in completion?(error) }
    }

    func activateFileViewerSelecting(_ urls: [URL]) { ws.activateFileViewerSelecting(urls) }
    func urlForApplication(withBundleIdentifier id: String) -> URL? { ws.urlForApplication(withBundleIdentifier: id) }
    func urlsForApplications(toOpen url: URL) -> [URL] { ws.urlsForApplications(toOpen: url) }

    func fileInfo(atPath path: String) -> FileInfo? { FileInfo.onDisk(path) }

    func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}
