import Testing

@testable import FSearchKit

@Suite struct OnboardingTests {
    @Test func eachStepWaitsForItsResult() {
        var f = OnboardingFacts()
        #expect(canContinue(.welcome, f))
        #expect(!canContinue(.helper, f)); f.helperEnabled = true; #expect(canContinue(.helper, f))
        #expect(!canContinue(.fullDiskAccess, f)); f.fullDiskAccess = true; #expect(canContinue(.fullDiskAccess, f))
        #expect(!canContinue(.indexing, f)); f.indexReady = true; #expect(canContinue(.indexing, f))
    }
    @Test func skippingFullDiskAccessIsAllowed() {
        var f = OnboardingFacts(); f.skippedFullDiskAccess = true
        #expect(canContinue(.fullDiskAccess, f))
    }
    @Test func hotkeyWarningWhenALauncherRuns() {
        let raycast = "Raycast uses ⌥ Space. Pick another shortcut, or turn Raycast's off."
        let alfred = "Alfred may use ⌥ Space. Pick another shortcut, or change Alfred's."
        #expect(hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: ["com.raycast.macos"]) == raycast)
        #expect(hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: ["com.runningwithcrayons.Alfred"]) == alfred)
        #expect(
            hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: ["com.runningwithcrayons.Alfred", "com.raycast.macos"]) == raycast,
            "Raycast takes precedence")
        #expect(hotkeyWarning(defaultIsOptionSpace: true, runningBundleIds: []) == nil)
        #expect(hotkeyWarning(defaultIsOptionSpace: false, runningBundleIds: ["com.raycast.macos"]) == nil)
    }
}
