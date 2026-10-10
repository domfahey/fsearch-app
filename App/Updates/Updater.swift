import Combine
import FSearchKit
import Observation
import Sparkle
import SwiftUI

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

    /// Never under test: a UI-test launch would check the real feed, write
    /// SULastCheckTime to the real defaults and could put up update windows.
    static func shouldStart(configured: Bool, testMode: Bool) -> Bool { configured && !testMode }

    /// Called once at launch. Creates (and so starts) Sparkle only when configured, outside test mode.
    static func start() {
        guard shouldStart(configured: isConfigured, testMode: LaunchOptions.current.testMode), controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: UpdateReminderDriver.shared)
    }
}

/// Whether a scheduled update is waiting behind the menu-bar indicator.
/// `@Observable` so the menu-bar icon and menu redraw.
@MainActor @Observable
final class UpdateReminderModel {
    static let shared = UpdateReminderModel()
    private(set) var reminder = UpdateReminder()
    var indicatorVisible: Bool { reminder.indicatorVisible }

    func update(_ change: (inout UpdateReminder) -> Void) { change(&reminder) }
}

/// Sparkle gentle reminders: an LSUIElement app is never frontmost, so a
/// scheduled update shows as a menu-bar indicator plus "Update Available…"
/// instead of a window that steals focus.
@MainActor
final class UpdateReminderDriver: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = UpdateReminderDriver()

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        UpdateReminderModel.shared.reminder.sparkleShouldShowScheduled(immediateFocus: immediateFocus)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        UpdateReminderModel.shared.update {
            $0.willShow(bySparkle: handleShowingUpdate, userInitiated: state.userInitiated)
        }
        // Sparkle's own window is about to appear: bring it to the front.
        if handleShowingUpdate { AppActivation.activate() }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        UpdateReminderModel.shared.update { $0.userDidReceiveAttention() }
    }

    func standardUserDriverWillFinishUpdateSession() {
        UpdateReminderModel.shared.update { $0.sessionWillFinish() }
    }
}

/// Menu item shown while a scheduled update waits; resumes it in Sparkle's window.
struct UpdateAvailableItem: View {
    var body: some View {
        if UpdateReminderModel.shared.indicatorVisible, let controller = Updater.controller {
            Button("Update Available…") {
                AppActivation.activate()
                controller.checkForUpdates(nil)
            }
            Divider()
        }
    }
}

/// Mirrors `SPUUpdater.automaticallyChecksForUpdates` (KVO) and writes changes back.
@MainActor
final class AutoCheckState: ObservableObject {
    @Published var automatic: Bool {
        didSet { if automatic != updater.automaticallyChecksForUpdates { updater.automaticallyChecksForUpdates = automatic } }
    }
    @Published private(set) var canCheck = false
    private let updater: SPUUpdater
    private var cancellables: Set<AnyCancellable> = []

    init(updater: SPUUpdater) {
        self.updater = updater
        automatic = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main).sink { [weak self] in
                if self?.automatic != $0 { self?.automatic = $0 }
            }.store(in: &cancellables)
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main).assign(to: &$canCheck)
    }
}

/// The Settings "Updates" section; empty (so hidden) without a configured updater.
struct UpdatesSettingsSection: View {
    var body: some View {
        if let controller = Updater.controller {
            UpdatesSettingsContent(controller: controller)
        }
    }
}

private struct UpdatesSettingsContent: View {
    let controller: SPUStandardUpdaterController
    @StateObject private var state: AutoCheckState

    init(controller: SPUStandardUpdaterController) {
        self.controller = controller
        _state = StateObject(wrappedValue: AutoCheckState(updater: controller.updater))
    }

    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: $state.automatic)
            Button("Check Now") { controller.checkForUpdates(nil) }
                .disabled(!state.canCheck)
        }
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
