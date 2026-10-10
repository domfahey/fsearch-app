import Foundation

/// Which daemon onboarding is talking about: the bundled helper the app
/// registers, or an fsearch daemon that was already running (started from the CLI).
public enum OnboardingDaemonMode: Equatable, Sendable { case bundledHelper, existingDaemon }

/// Step 2: a running daemon the app doesn't own is used as is.
public func helperStepMode(owns: Bool, running: Bool) -> OnboardingDaemonMode {
    !owns && running ? .existingDaemon : .bundledHelper
}

public enum FullDiskAccessStepMode: Equatable, Sendable { case granted, bundledHelper, existingDaemon }

/// Step 3: Full Disk Access belongs to whichever daemon is indexing.
public func fullDiskAccessStepMode(owns: Bool, running: Bool, fullDiskAccess: Bool) -> FullDiskAccessStepMode {
    if fullDiskAccess { return .granted }
    return helperStepMode(owns: owns, running: running) == .existingDaemon ? .existingDaemon : .bundledHelper
}

/// Back from System Settings on step 3: restart only our own helper, and
/// only when the user went there to turn Full Disk Access on.
public func restartAfterSettings(pressedTurnOn: Bool, owns: Bool, fullDiskAccess: Bool) -> Bool {
    pressedTurnOn && owns && !fullDiskAccess
}

/// Step 4's progress line; no count until the first entries arrive.
public func indexingLine(entries: Int) -> String {
    entries == 0 ? "Indexing your disk…" : "\(entries.formatted()) files so far… usually under a minute."
}

/// Step 4's ending, naming the user's actual shortcut.
public func tryItLine(shortcut: String?) -> String {
    guard let shortcut else { return "Try it now: set a shortcut in Settings, then type part of any file name." }
    return "Try it now: press \(shortcut) and type part of any file name."
}
