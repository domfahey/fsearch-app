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

/// NSWorkspace, Process and FileManager's Trash.
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

    func run(_ executable: String, _ arguments: [String], onExit: @escaping @Sendable (Int32) -> Void) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.terminationHandler = { onExit($0.terminationStatus) }
        return (try? p.run()) != nil
    }

    func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}
