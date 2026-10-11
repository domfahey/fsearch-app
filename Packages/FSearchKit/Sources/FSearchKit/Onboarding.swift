/// The onboarding pages, in order.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    /// Introduction.
    case welcome
    /// Enable the background helper.
    case helper
    /// Grant Full Disk Access (or skip it).
    case fullDiskAccess
    /// Wait for the first index.
    case indexing
}

/// What onboarding has learned so far; each step reads its own flag.
public struct OnboardingFacts: Equatable, Sendable {
    /// The helper is registered and enabled.
    public var helperEnabled = false
    /// The daemon has Full Disk Access.
    public var fullDiskAccess = false
    /// The user chose to continue without it.
    public var skippedFullDiskAccess = false
    /// The first index is built.
    public var indexReady = false
    /// Creates facts with nothing done yet.
    public init() {}
}

/// Onboarding's rules and copy: when a step may continue, the shortcut warning,
/// which daemon steps 2 and 3 talk about, when to restart the helper after
/// System Settings, and step 4's lines (the last ones in OnboardingCopy.swift).
public enum Onboarding {
    /// Each step checks its own result before moving on.
    ///
    /// - Parameters:
    ///   - step: The page being shown.
    ///   - f: What onboarding knows.
    public static func canContinue(_ step: OnboardingStep, _ f: OnboardingFacts) -> Bool {
        switch step {
        case .welcome: true
        case .helper: f.helperEnabled
        case .fullDiskAccess: f.fullDiskAccess || f.skippedFullDiskAccess
        case .indexing: f.indexReady
        }
    }

    /// macOS gives no way to ask who owns a hotkey, so warn when a launcher
    /// known to use ⌥ Space is running.
    ///
    /// - Parameters:
    ///   - defaultIsOptionSpace: Whether the chosen shortcut is the default ⌥ Space.
    ///   - runningBundleIds: Bundle ids of the running apps.
    /// - Returns: A warning, or nil when there is no known clash.
    public static func hotkeyWarning(defaultIsOptionSpace: Bool, runningBundleIds: Set<String>) -> String? {
        guard defaultIsOptionSpace else { return nil }
        if runningBundleIds.contains("com.raycast.macos") { return "Raycast uses ⌥ Space. Pick another shortcut, or turn Raycast's off." }
        if runningBundleIds.contains("com.runningwithcrayons.Alfred") {
            return "Alfred may use ⌥ Space. Pick another shortcut, or change Alfred's."
        }
        return nil
    }
}
