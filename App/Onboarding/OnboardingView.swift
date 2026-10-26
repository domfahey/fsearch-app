import AppKit
import FSearchKit
import KeyboardShortcuts
import SwiftUI
import os

/// Wording for the Full Disk Access step. Which variant is right depends on the attribution experiment still open in
/// docs/release-checklist.md ("Task 0"); change the wording here only.
/// - "Turn on FSearch": the app's grant covers the bundled helper.
/// - "Add FSearch's helper": the user must add FSearch.app/Contents/Helpers/fsearch by hand.
enum FDACopy {
    /// The button that opens Privacy settings.
    static let buttonLabel = "Turn on FSearch"
    /// What to do in Privacy settings.
    static let help = "In Privacy Settings, find FSearch in the list and turn it on."
    /// A daemon started from the CLI is a different binary with its own grant.
    static let existingDaemonHelp =
        "Full Disk Access belongs to the fsearch daemon that's already running. Grant it to your fsearch binary in Privacy Settings and restart that daemon, or skip for now."
    /// Privacy settings' Full Disk Access list.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

/// Onboarding's state and steps, apart from the view so each path is testable.
@MainActor
final class OnboardingFlow: ObservableObject {
    /// The page being shown.
    @Published var step: OnboardingStep
    /// What has been learned from the system and the daemon.
    @Published var facts = OnboardingFacts()
    /// Entries indexed so far, for the progress line.
    @Published private(set) var entries = 0
    /// While start() or restart() runs, the poll leaves the daemon alone so it
    /// can't overwrite their result (e.g. .needsApproval).
    @Published private(set) var busy = false
    /// Set when "Turn on FSearch" opens Settings; one restart on return clears it.
    @Published private(set) var pressedTurnOn = false
    /// The poll's in-flight refresh(); cancelled before start()/restart() so a
    /// slow refresh can't publish over their result.
    private var pollRefresh: Task<Void, Never>?
    /// The app state, whose daemon onboarding drives.
    let app: AppState
    private let defaults: UserDefaults
    /// Closes the onboarding window once the last step is done.
    var onFinish: @MainActor () -> Void = { OnboardingLauncher.close() }

    init(app: AppState, defaults: UserDefaults, step: OnboardingStep = .welcome) {
        self.app = app
        self.defaults = defaults
        self.step = step
    }

    /// Whether the daemon answers (even while indexing).
    var daemonRunning: Bool {
        switch app.daemon.state {
        case .running, .indexing: true
        default: false
        }
    }

    /// Whether the current step's result is in.
    var canContinue: Bool { Onboarding.canContinue(step, facts) }

    /// Reads the saved "skipped" flag when the window opens.
    func appeared() { facts.skippedFullDiskAccess = defaults.bool(forKey: "skippedFullDiskAccess") }

    /// Moves to the next step (starting the helper on reaching it) or finishes onboarding.
    func next() {
        if let n = OnboardingStep(rawValue: step.rawValue + 1) {
            Log.onboarding.info("step \(String(describing: self.step), privacy: .public) -> \(String(describing: n), privacy: .public)")
            step = n
            if n == .helper { startDaemon() }
        } else {
            Log.onboarding.info("finished")
            defaults.set(true, forKey: "onboarded")
            onFinish()
        }
    }

    /// Not tied to the view, so closing the window mid-start doesn't cancel it.
    @discardableResult
    func startDaemon() -> Task<Void, Never> {
        OnboardingLauncher.noteDaemonStarted()
        busy = true
        return Task {
            await cancelPollRefresh()
            await app.daemon.start(resumingAfterRemoval: true)
            busy = false
            apply()
        }
    }

    /// Opens Privacy settings and notes that the user went there to turn Full Disk Access on.
    func turnOnFullDiskAccess() {
        Log.onboarding.info("opening System Settings for Full Disk Access")
        pressedTurnOn = true
        FileActions.workspace.open(FDACopy.settingsURL)
    }

    /// Opens Privacy settings without arming the restart.
    func openPrivacySettings() { FileActions.workspace.open(FDACopy.settingsURL) }

    /// Remembers that the user chose to go on without Full Disk Access; the menu bar then shows a gentle reminder.
    func skipFullDiskAccess() {
        Log.onboarding.info("skipped Full Disk Access")
        pressedTurnOn = false
        defaults.set(true, forKey: "skippedFullDiskAccess")
        facts.skippedFullDiskAccess = true
    }

    /// Facts come from the system and the daemon, never from button presses.
    func poll() async {
        // Nothing talks to the daemon before the helper step: step 1 is only the shortcut.
        guard step != .welcome, !busy else { return }
        // A pending approval is re-checked when the app becomes active again.
        if app.daemon.state != .needsApproval {
            let t = Task { await app.daemon.refresh() }
            pollRefresh = t
            // Closing the window cancels the poll loop; pass that on.
            await withTaskCancellationHandler {
                await t.value
            } onCancel: {
                t.cancel()
            }
            pollRefresh = nil
        }
        apply()
    }

    /// refresh() returns without publishing once cancelled.
    private func cancelPollRefresh() async {
        guard let t = pollRefresh else { return }
        t.cancel()
        await t.value
    }

    /// Copies the daemon's state into ``facts``.
    func apply() {
        switch app.daemon.state {
        case let .running(s):
            facts.helperEnabled = true
            entries = s.entries
            facts.indexReady = s.entries > 0
            facts.fullDiskAccess = s.fullDiskAccess
        case .indexing:
            facts.helperEnabled = true
        case .needsApproval:
            facts.helperEnabled = false
        case .checking, .failed:
            break
        }
    }

    /// Back from System Settings: pick up a Login Items approval, or restart
    /// our own helper once so it notices a Full Disk Access grant the user
    /// went to turn on. A daemon the app doesn't own is only polled.
    func returnedFromSettings() async {
        guard step != .welcome, !busy else { return }
        Log.onboarding.info("returned from System Settings at step \(String(describing: self.step), privacy: .public)")
        if app.daemon.state == .needsApproval { await startDaemon().value; return }
        if step == .fullDiskAccess,
            Onboarding.restartAfterSettings(pressedTurnOn: pressedTurnOn, owns: app.daemon.ownsDaemon, fullDiskAccess: facts.fullDiskAccess)
        {
            Log.onboarding.info("restarting the helper to pick up Full Disk Access")
            pressedTurnOn = false
            busy = true
            await cancelPollRefresh()
            await app.daemon.restart()
            busy = false
        }
        apply()
    }
}

/// The first-launch window: the four steps of ``OnboardingStep``, driven by an ``OnboardingFlow``.
struct OnboardingView: View {
    @StateObject private var flow: OnboardingFlow
    /// Observed directly: AppState doesn't forward DaemonManager's changes.
    @ObservedObject private var daemon: DaemonManager
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)

    private static let pollInterval = Duration.seconds(1)

    init(flow: OnboardingFlow) {
        _flow = StateObject(wrappedValue: flow)
        daemon = flow.app.daemon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step \(flow.step.rawValue + 1) of 4").font(.caption).foregroundStyle(.secondary)
            switch flow.step {
            case .welcome: welcome
            case .helper: helper
            case .fullDiskAccess: fullDiskAccess
            case .indexing:
                Text("Indexing your disk").font(.title3.bold())
                ProgressView().progressViewStyle(.linear)
                Text(Onboarding.indexingLine(entries: flow.entries)).foregroundStyle(.secondary)
                Text(Onboarding.tryItLine(shortcut: shortcut?.description))
            }
            Spacer()
            HStack {
                Spacer()
                Button(flow.step == .indexing ? "Done" : "Continue", action: flow.next)
                    .buttonStyle(.borderedProminent).disabled(!flow.canContinue)
            }
        }
        .padding(20).frame(width: 440, height: 300)
        .onAppear { flow.appeared() }
        // The loop belongs to the view, so closing the window cancels it.
        .task {
            while !Task.isCancelled {
                await flow.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await flow.returnedFromSettings() }
        }
    }

    @ViewBuilder private var welcome: some View {
        Text("Find anything on your Mac").font(.title3.bold())
        Text("Press your shortcut from anywhere, type a few letters, and every file on your disk shows up as you type. Even inside files.")
        HStack {
            Text("Your shortcut:"); KeyboardShortcuts.Recorder(for: .togglePanel) { shortcut = $0 }
        }
        if let w = Onboarding.hotkeyWarning(
            defaultIsOptionSpace: shortcut == .init(.space, modifiers: [.option]),
            runningBundleIds: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
        {
            Text("⚠ " + w).foregroundStyle(.orange).font(.callout)
        }
    }

    @ViewBuilder private var helper: some View {
        Text("Keep search ready in the background").font(.title3.bold())
        if Onboarding.helperStepMode(owns: daemon.ownsDaemon, running: flow.daemonRunning) == .existingDaemon {
            Label("Using the fsearch daemon that's already running", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Text("A small background helper keeps the index up to date as files change, so results are instant. It starts when you log in.")
            if flow.facts.helperEnabled {
                Label("Allowed in Login Items", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if case let .failed(message) = daemon.state, !flow.busy {
                Text(message).foregroundStyle(.red).font(.callout)
                Button("Try Again") { flow.startDaemon() }
            } else {
                Button("Open Login Items Settings") { daemon.openLoginItems() }
            }
        }
    }

    @ViewBuilder private var fullDiskAccess: some View {
        Text("Let FSearch see all your files").font(.title3.bold())
        Text(
            "Without Full Disk Access, macOS hides Desktop, Documents, Downloads, Mail, Messages and iCloud Drive from every app. Nothing leaves your Mac: the index stays on this computer."
        )
        switch Onboarding.fullDiskAccessStepMode(
            owns: daemon.ownsDaemon, running: flow.daemonRunning, fullDiskAccess: flow.facts.fullDiskAccess)
        {
        case .granted:
            Label("Full Disk Access is on", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .bundledHelper:
            Text(FDACopy.help).font(.callout).foregroundStyle(.secondary)
            Button(FDACopy.buttonLabel, action: flow.turnOnFullDiskAccess)
            skipButton
        case .existingDaemon:
            Text(FDACopy.existingDaemonHelp).font(.callout).foregroundStyle(.secondary)
            Button("Open Privacy Settings", action: flow.openPrivacySettings)
            skipButton
        }
    }

    private var skipButton: some View {
        Button("Skip for now", action: flow.skipFullDiskAccess).buttonStyle(.link)
    }
}
