import Testing

@testable import FSearchKit

@Suite struct OnboardingCopyTests {
    @Test func helperStepNamesARunningCLIDaemon() {
        #expect(helperStepMode(owns: false, running: true) == .existingDaemon)
        #expect(helperStepMode(owns: true, running: true) == .bundledHelper)
        #expect(helperStepMode(owns: false, running: false) == .bundledHelper)
        #expect(helperStepMode(owns: true, running: false) == .bundledHelper)
    }

    @Test func fullDiskAccessStepBelongsToTheDaemonThatRuns() {
        #expect(fullDiskAccessStepMode(owns: true, running: true, fullDiskAccess: true) == .granted)
        #expect(fullDiskAccessStepMode(owns: false, running: true, fullDiskAccess: true) == .granted)
        #expect(fullDiskAccessStepMode(owns: false, running: true, fullDiskAccess: false) == .existingDaemon)
        #expect(fullDiskAccessStepMode(owns: true, running: true, fullDiskAccess: false) == .bundledHelper)
        #expect(fullDiskAccessStepMode(owns: false, running: false, fullDiskAccess: false) == .bundledHelper)
    }

    @Test func restartOnlyAfterTurnOnAndOnlyOurOwnHelper() {
        #expect(restartAfterSettings(pressedTurnOn: true, owns: true, fullDiskAccess: false))
        #expect(!restartAfterSettings(pressedTurnOn: false, owns: true, fullDiskAccess: false))
        #expect(!restartAfterSettings(pressedTurnOn: true, owns: false, fullDiskAccess: false))
        #expect(!restartAfterSettings(pressedTurnOn: true, owns: true, fullDiskAccess: true))
    }

    @Test func noCountBeforeTheFirstEntries() {
        #expect(indexingLine(entries: 0) == "Indexing your disk…")
        #expect(indexingLine(entries: 42) == "42 files so far… usually under a minute.")
    }

    @Test func tryItNamesTheShortcut() {
        #expect(tryItLine(shortcut: "⌥Space") == "Try it now: press ⌥Space and type part of any file name.")
        #expect(tryItLine(shortcut: nil) == "Try it now: set a shortcut in Settings, then type part of any file name.")
    }
}
