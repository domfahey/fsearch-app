import Combine
import SwiftUI
import Sparkle

/// Sparkle updater. Not started while Info.plist still carries the placeholder
/// public key (see docs/release-checklist.md), so dev builds never prompt.
@MainActor
enum Updater {
    static let isConfigured: Bool = {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && key != "REPLACE_WITH_SPARKLE_PUBLIC_KEY"
    }()

    /// nil until `start()` runs with a real key.
    private(set) static var controller: SPUStandardUpdaterController?

    /// Called once at launch. Creates (and so starts) Sparkle only when configured.
    static func start() {
        guard isConfigured, controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}

/// Mirrors `SPUUpdater.canCheckForUpdates` (KVO), false while a check runs.
@MainActor
private final class UpdateCheckState: ObservableObject {
    @Published private(set) var canCheck = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheck)
    }
}

/// Menu item: hidden unless the updater was started (real Sparkle key).
struct CheckForUpdatesItem: View {
    var body: some View {
        if let controller = Updater.controller {
            CheckForUpdatesButton(controller: controller)
        }
    }
}

private struct CheckForUpdatesButton: View {
    let controller: SPUStandardUpdaterController
    @StateObject private var state: UpdateCheckState

    init(controller: SPUStandardUpdaterController) {
        self.controller = controller
        _state = StateObject(wrappedValue: UpdateCheckState(updater: controller.updater))
    }

    var body: some View {
        Button("Check for Updates…") { controller.checkForUpdates(nil) }
            .disabled(!state.canCheck)
    }
}
