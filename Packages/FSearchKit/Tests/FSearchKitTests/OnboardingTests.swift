import Testing

@testable import FSearchKit

@Suite struct OnboardingTests {
    @Test func eachStepWaitsForItsResult() {
        var f = OnboardingFacts()
        #expect(Onboarding.canContinue(.welcome, f))
        #expect(!Onboarding.canContinue(.helper, f)); f.helperEnabled = true; #expect(Onboarding.canContinue(.helper, f))
        #expect(!Onboarding.canContinue(.fullDiskAccess, f)); f.fullDiskAccess = true; #expect(Onboarding.canContinue(.fullDiskAccess, f))
        #expect(!Onboarding.canContinue(.indexing, f)); f.indexReady = true; #expect(Onboarding.canContinue(.indexing, f))
    }
    @Test func skippingFullDiskAccessIsAllowed() {
        var f = OnboardingFacts(); f.skippedFullDiskAccess = true
        #expect(Onboarding.canContinue(.fullDiskAccess, f))
    }
    @Test func hotkeyWarningWhenALauncherRuns() {
        let raycast = "Raycast uses ⌥ Space. Pick another shortcut, or turn Raycast's off."
        let alfred = "Alfred may use ⌥ Space. Pick another shortcut, or change Alfred's."
        #expect(Onboarding.hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: ["com.raycast.macos"]) == raycast)
        #expect(Onboarding.hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: ["com.runningwithcrayons.Alfred"]) == alfred)
        let both: Set<String> = ["com.runningwithcrayons.Alfred", "com.raycast.macos"]
        #expect(Onboarding.hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: both) == raycast, "Raycast takes precedence")
        #expect(Onboarding.hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: []) == nil)
        #expect(Onboarding.hotkeyWarning(defaultIsOptionSpace: false, runningBundleIds: ["com.raycast.macos"]) == nil)
    }
}
