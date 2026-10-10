public enum OnboardingStep: Int, CaseIterable, Sendable { case welcome, helper, fullDiskAccess, indexing }

public struct OnboardingFacts: Equatable, Sendable {
    public var helperEnabled = false
    public var fullDiskAccess = false
    public var skippedFullDiskAccess = false
    public var indexReady = false
    public init() {}
}

/// Each step checks its own result before moving on.
public func canContinue(_ step: OnboardingStep, _ f: OnboardingFacts) -> Bool {
    switch step {
    case .welcome: true
    case .helper: f.helperEnabled
    case .fullDiskAccess: f.fullDiskAccess || f.skippedFullDiskAccess
    case .indexing: f.indexReady
    }
}

/// macOS gives no way to ask who owns a hotkey, so warn when a launcher
/// known to use ⌥ Space is running.
public func hotkeyWarning(defaultIsOptionSpace: Bool, runningBundleIds: Set<String>) -> String? {
    guard defaultIsOptionSpace else { return nil }
    if runningBundleIds.contains("com.raycast.macos") { return "Raycast uses ⌥ Space. Pick another shortcut, or turn Raycast's off." }
    if runningBundleIds.contains("com.runningwithcrayons.Alfred") {
        return "Alfred may use ⌥ Space. Pick another shortcut, or change Alfred's."
    }
    return nil
}
