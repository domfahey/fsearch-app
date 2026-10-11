import Testing

@testable import FSearchKit

@Suite struct OnboardingCopyTests {
    @Test func helperStepNamesARunningCLIDaemon() {
        #expect(Onboarding.helperStepMode(owns: false, running: true) == .existingDaemon)
        #expect(Onboarding.helperStepMode(owns: true, running: true) == .bundledHelper)
        #expect(Onboarding.helperStepMode(owns: false, running: false) == .bundledHelper)
        #expect(Onboarding.helperStepMode(owns: true, running: false) == .bundledHelper)
    }

    @Test func fullDiskAccessStepBelongsToTheDaemonThatRuns() {
        #expect(Onboarding.fullDiskAccessStepMode(owns: true, running: true, fullDiskAccess: true) == .granted)
        #expect(Onboarding.fullDiskAccessStepMode(owns: false, running: true, fullDiskAccess: true) == .granted)
        #expect(Onboarding.fullDiskAccessStepMode(owns: false, running: true, fullDiskAccess: false) == .existingDaemon)
        #expect(Onboarding.fullDiskAccessStepMode(owns: true, running: true, fullDiskAccess: false) == .bundledHelper)
        #expect(Onboarding.fullDiskAccessStepMode(owns: false, running: false, fullDiskAccess: false) == .bundledHelper)
    }

    @Test func restartOnlyAfterTurnOnAndOnlyOurOwnHelper() {
        #expect(Onboarding.restartAfterSettings(pressedTurnOn: true, owns: true, fullDiskAccess: false))
        #expect(!Onboarding.restartAfterSettings(pressedTurnOn: false, owns: true, fullDiskAccess: false))
        #expect(!Onboarding.restartAfterSettings(pressedTurnOn: true, owns: false, fullDiskAccess: false))
        #expect(!Onboarding.restartAfterSettings(pressedTurnOn: true, owns: true, fullDiskAccess: true))
    }

    @Test func noCountBeforeTheFirstEntries() {
        #expect(Onboarding.indexingLine(entries: 0) == "Indexing your disk…")
        #expect(Onboarding.indexingLine(entries: 42) == "42 files so far… usually under a minute.")
    }

    @Test func tryItNamesTheShortcut() {
        #expect(Onboarding.tryItLine(shortcut: "⌥Space") == "Try it now: press ⌥Space and type part of any file name.")
        #expect(Onboarding.tryItLine(shortcut: nil) == "Try it now: set a shortcut in Settings, then type part of any file name.")
    }
}
