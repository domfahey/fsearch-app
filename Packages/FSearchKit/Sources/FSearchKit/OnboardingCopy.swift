import Foundation

/// Which daemon onboarding is talking about: the bundled helper the app
/// registers, or an fsearch daemon that was already running (started from the CLI).
public enum OnboardingDaemonMode: Equatable, Sendable {
    /// The helper inside the app.
    case bundledHelper
    /// A daemon the app doesn't own.
    case existingDaemon
}

/// Step 2: a running daemon the app doesn't own is used as is.
///
/// - Parameters:
///   - owns: Whether the app registered the helper.
///   - running: Whether a daemon answers.
public func helperStepMode(owns: Bool, running: Bool) -> OnboardingDaemonMode {
    !owns && running ? .existingDaemon : .bundledHelper
}

/// What step 3 should say: already granted, or whose grant is needed.
public enum FullDiskAccessStepMode: Equatable, Sendable {
    /// Nothing left to do.
    case granted
    /// The user must grant it to the bundled helper.
    case bundledHelper
    /// The user must grant it to the existing daemon's binary.
    case existingDaemon
}

/// Step 3: Full Disk Access belongs to whichever daemon is indexing.
///
/// - Parameters:
///   - owns: Whether the app registered the helper.
///   - running: Whether a daemon answers.
///   - fullDiskAccess: Whether the daemon already has it.
public func fullDiskAccessStepMode(owns: Bool, running: Bool, fullDiskAccess: Bool) -> FullDiskAccessStepMode {
    if fullDiskAccess { return .granted }
    return helperStepMode(owns: owns, running: running) == .existingDaemon ? .existingDaemon : .bundledHelper
}

/// Back from System Settings on step 3: restart only our own helper, and
/// only when the user went there to turn Full Disk Access on.
///
/// A foreign daemon is never restarted; the new grant only reaches a process when it starts.
///
/// - Parameters:
///   - pressedTurnOn: Whether the user pressed the "Turn On" button.
///   - owns: Whether the app registered the helper.
///   - fullDiskAccess: Whether the daemon now reports it.
public func restartAfterSettings(pressedTurnOn: Bool, owns: Bool, fullDiskAccess: Bool) -> Bool {
    pressedTurnOn && owns && !fullDiskAccess
}

/// Step 4's progress line; no count until the first entries arrive.
///
/// - Parameter entries: Files indexed so far.
public func indexingLine(entries: Int) -> String {
    entries == 0 ? "Indexing your disk…" : "\(entries.formatted()) files so far… usually under a minute."
}

/// Step 4's ending, naming the user's actual shortcut.
///
/// - Parameter shortcut: The shortcut's display text, or nil if none is set.
public func tryItLine(shortcut: String?) -> String {
    guard let shortcut else { return "Try it now: set a shortcut in Settings, then type part of any file name." }
    return "Try it now: press \(shortcut) and type part of any file name."
}
