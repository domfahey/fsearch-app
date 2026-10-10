import AppKit
import FSearchKit
import KeyboardShortcuts
import SwiftUI

/// Wording for the Full Disk Access step. Task 0 (docs/notes/fda-attribution.md)
/// decides which variant is right; change it here only.
/// - "Turn on FSearch": the app's grant covers the bundled helper.
/// - "Add FSearch's helper": the user must add FSearch.app/Contents/Helpers/fsearch by hand.
enum FDACopy {
    static let buttonLabel = "Turn on FSearch"
    static let help = "In Privacy Settings, find FSearch in the list and turn it on."
    /// A daemon started from the CLI is a different binary with its own grant.
    static let existingDaemonHelp = "Full Disk Access belongs to the fsearch daemon that's already running. Grant it to your fsearch binary in Privacy Settings and restart that daemon, or skip for now."
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("onboarded") private var onboarded = false
    /// Read by the menu-bar reminder (a later task).
    @AppStorage("skippedFullDiskAccess") private var skippedFDA = false
    @State private var step: OnboardingStep = .welcome
    @State private var facts = OnboardingFacts()
    @State private var entries = 0
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
    /// While start() or restart() runs, the poll leaves the daemon alone so it
    /// can't overwrite their result (e.g. .needsApproval).
    @State private var busy = false
    /// Set when "Turn on FSearch" opens Settings; one restart on return clears it.
    @State private var pressedTurnOn = false
    /// The poll's in-flight refresh(); cancelled before start()/restart() so a
    /// slow refresh can't publish over their result.
    @State private var pollRefresh: Task<Void, Never>?

    private static let pollInterval = Duration.seconds(1)

    private var daemonRunning: Bool {
        switch app.daemon.state {
        case .running, .indexing: true
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step \(step.rawValue + 1) of 4").font(.caption).foregroundStyle(.secondary)
            switch step {
            case .welcome: welcome
            case .helper: helper
            case .fullDiskAccess: fullDiskAccess
            case .indexing:
                Text("Indexing your disk").font(.title3.bold())
                ProgressView().progressViewStyle(.linear)
                Text(indexingLine(entries: entries)).foregroundStyle(.secondary)
                Text(tryItLine(shortcut: shortcut?.description))
            }
            Spacer()
            HStack {
                Spacer()
                Button(step == .indexing ? "Done" : "Continue", action: next)
                    .buttonStyle(.borderedProminent).disabled(!canContinue(step, facts))
            }
        }
        .padding(20).frame(width: 440, height: 300)
        .onAppear { facts.skippedFullDiskAccess = skippedFDA }
        // The loop belongs to the view, so closing the window cancels it.
        .task {
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await returnedFromSettings() }
        }
    }

    @ViewBuilder private var welcome: some View {
        Text("Find anything on your Mac").font(.title3.bold())
        Text("Press your shortcut from anywhere, type a few letters, and every file on your disk shows up as you type. Even inside files.")
        HStack { Text("Your shortcut:"); KeyboardShortcuts.Recorder(for: .togglePanel) { shortcut = $0 } }
        if let w = hotkeyWarning(
            defaultIsOptionSpace: shortcut == .init(.space, modifiers: [.option]),
            runningBundleIds: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))) {
            Text("⚠ " + w).foregroundStyle(.orange).font(.callout)
        }
    }

    @ViewBuilder private var helper: some View {
        Text("Keep search ready in the background").font(.title3.bold())
        if helperStepMode(owns: app.daemon.ownsDaemon, running: daemonRunning) == .existingDaemon {
            Label("Using the fsearch daemon that's already running", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Text("A small background helper keeps the index up to date as files change, so results are instant. It starts when you log in.")
            if facts.helperEnabled {
                Label("Allowed in Login Items", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if case let .failed(message) = app.daemon.state, !busy {
                Text(message).foregroundStyle(.red).font(.callout)
                Button("Try Again") { startDaemon() }
            } else {
                Button("Open Login Items Settings") { app.daemon.openLoginItems() }
            }
        }
    }

    @ViewBuilder private var fullDiskAccess: some View {
        Text("Let FSearch see all your files").font(.title3.bold())
        Text("Without Full Disk Access, macOS hides Desktop, Documents, Downloads, Mail, Messages and iCloud Drive from every app. Nothing leaves your Mac: the index stays on this computer.")
        switch fullDiskAccessStepMode(owns: app.daemon.ownsDaemon, running: daemonRunning, fullDiskAccess: facts.fullDiskAccess) {
        case .granted:
            Label("Full Disk Access is on", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .bundledHelper:
            Text(FDACopy.help).font(.callout).foregroundStyle(.secondary)
            Button(FDACopy.buttonLabel) { pressedTurnOn = true; NSWorkspace.shared.open(FDACopy.settingsURL) }
            skipButton
        case .existingDaemon:
            Text(FDACopy.existingDaemonHelp).font(.callout).foregroundStyle(.secondary)
            Button("Open Privacy Settings") { NSWorkspace.shared.open(FDACopy.settingsURL) }
            skipButton
        }
    }

    private var skipButton: some View {
        Button("Skip for now") { pressedTurnOn = false; skippedFDA = true; facts.skippedFullDiskAccess = true }.buttonStyle(.link)
    }

    private func next() {
        if let n = OnboardingStep(rawValue: step.rawValue + 1) {
            step = n
            if n == .helper { startDaemon() }
        } else {
            onboarded = true
            OnboardingLauncher.close()
        }
    }

    /// Not tied to the view, so closing the window mid-start doesn't cancel it.
    private func startDaemon() {
        OnboardingLauncher.noteDaemonStarted()
        busy = true
        Task {
            await cancelPollRefresh()
            await app.daemon.start()
            busy = false
            apply()
        }
    }

    /// Facts come from the system and the daemon, never from button presses.
    private func poll() async {
        // Nothing talks to the daemon before the helper step: step 1 is only the shortcut.
        guard step != .welcome, !busy else { return }
        // A pending approval is re-checked when the app becomes active again.
        if app.daemon.state != .needsApproval {
            let t = Task { await app.daemon.refresh() }
            pollRefresh = t
            // Closing the window cancels the poll loop; pass that on.
            await withTaskCancellationHandler { await t.value } onCancel: { t.cancel() }
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

    private func apply() {
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
    private func returnedFromSettings() async {
        guard step != .welcome, !busy else { return }
        if app.daemon.state == .needsApproval { startDaemon(); return }
        if step == .fullDiskAccess,
           restartAfterSettings(pressedTurnOn: pressedTurnOn, owns: app.daemon.ownsDaemon, fullDiskAccess: facts.fullDiskAccess) {
            pressedTurnOn = false
            busy = true
            await cancelPollRefresh()
            await app.daemon.restart()
            busy = false
        }
        apply()
    }
}
