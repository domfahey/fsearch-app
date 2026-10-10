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
}

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("onboarded") private var onboarded = false
    /// Read by the menu-bar reminder (a later task).
    @AppStorage("skippedFullDiskAccess") private var skippedFDA = false
    @State private var step: OnboardingStep = .welcome
    @State private var facts = OnboardingFacts()
    @State private var entries = 0

    private static let pollInterval = Duration.seconds(1)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step \(step.rawValue + 1) of 4").font(.caption).foregroundStyle(.secondary)
            switch step {
            case .welcome:
                Text("Find anything on your Mac").font(.title3.bold())
                Text("Press your shortcut from anywhere, type a few letters, and every file on your disk shows up as you type. Even inside files.")
                HStack { Text("Your shortcut:"); KeyboardShortcuts.Recorder(for: .togglePanel) }
                if let w = hotkeyWarning(
                    defaultIsOptionSpace: KeyboardShortcuts.getShortcut(for: .togglePanel) == .init(.space, modifiers: [.option]),
                    runningBundleIds: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))) {
                    Text("⚠ " + w).foregroundStyle(.orange).font(.callout)
                }
            case .helper:
                Text("Keep search ready in the background").font(.title3.bold())
                Text("A small background helper keeps the index up to date as files change, so results are instant. It starts when you log in.")
                if facts.helperEnabled {
                    Label("Allowed in Login Items", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Open Login Items Settings") { app.daemon.openLoginItems() }
                }
            case .fullDiskAccess:
                Text("Let FSearch see all your files").font(.title3.bold())
                Text("Without Full Disk Access, macOS hides Desktop, Documents, Downloads, Mail, Messages and iCloud Drive from every app. Nothing leaves your Mac: the index stays on this computer.")
                if facts.fullDiskAccess {
                    Label("Full Disk Access is on", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text(FDACopy.help).font(.callout).foregroundStyle(.secondary)
                    Button(FDACopy.buttonLabel) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                    Button("Skip for now") { skippedFDA = true; facts.skippedFullDiskAccess = true }.buttonStyle(.link)
                }
            case .indexing:
                Text("Indexing your disk").font(.title3.bold())
                ProgressView().progressViewStyle(.linear)
                Text("\(entries.formatted()) files so far… usually under a minute.").foregroundStyle(.secondary)
                Text("Try it now: press your shortcut and type part of any file name.")
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

    private func next() {
        if let n = OnboardingStep(rawValue: step.rawValue + 1) {
            step = n
            if n == .helper { Task { await app.daemon.start(); apply() } }
        } else {
            onboarded = true
            OnboardingLauncher.close()
        }
    }

    /// Facts come from the system and the daemon, never from button presses.
    private func poll() async {
        // Nothing talks to the daemon before the helper step: step 1 is only the shortcut.
        guard step != .welcome else { return }
        // A pending approval is re-checked when the app becomes active again.
        if app.daemon.state != .needsApproval { await app.daemon.refresh() }
        apply()
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
    /// our own helper so it notices a new Full Disk Access grant. A daemon the
    /// app doesn't own is only polled.
    private func returnedFromSettings() async {
        guard step != .welcome else { return }
        if app.daemon.state == .needsApproval { await app.daemon.start() }
        if step == .fullDiskAccess, !facts.fullDiskAccess, app.daemon.ownsDaemon { await app.daemon.restart() }
        apply()
    }
}
