import Testing

@testable import FSearchKit

@Suite struct MenuBarWarningTests {
    @Test func healthyShowsNothing() {
        #expect(MenuBarWarning.evaluate(.running(fullDiskAccess: true), skippedFullDiskAccess: false) == nil)
        #expect(MenuBarWarning.evaluate(.checking, skippedFullDiskAccess: false) == nil)
        #expect(MenuBarWarning.evaluate(.indexing, skippedFullDiskAccess: false) == nil)
    }

    @Test func failureOffersFix() {
        let w = MenuBarWarning.evaluate(.failed, skippedFullDiskAccess: true)
        #expect(w?.offersFix == true)
        #expect(MenuBarWarning.evaluate(.needsApproval, skippedFullDiskAccess: false)?.offersFix == true)
    }

    @Test func revokedFullDiskAccessIsAGentleReminder() {
        let w = MenuBarWarning.evaluate(.running(fullDiskAccess: false), skippedFullDiskAccess: false)
        #expect(w?.offersFix == false)
        #expect(w?.message.contains("Full Disk Access") == true)
    }

    @Test func skippedThenStillOffIsASubtleReminder() {
        let w = MenuBarWarning.evaluate(.running(fullDiskAccess: false), skippedFullDiskAccess: true)
        #expect(w?.offersFix == false)
        #expect(w?.offersFullDiskAccess == true)
        #expect(w?.message.contains("Full Disk Access") == true)
        #expect(w?.symbol == "magnifyingglass.circle")
        #expect(w?.symbol != MenuBarWarning.evaluate(.failed, skippedFullDiskAccess: true)?.symbol)
    }

    @Test func dismissedReminderStaysQuiet() {
        #expect(MenuBarWarning.evaluate(.running(fullDiskAccess: false), skippedFullDiskAccess: true, dismissedReminder: true) == nil)
    }

    @Test func grantedAfterSkipClearsTheReminder() {
        #expect(MenuBarWarning.evaluate(.running(fullDiskAccess: true), skippedFullDiskAccess: true) == nil)
    }

    @Test func neverSkippedKeepsTheFailureStyleReminder() {
        let w = MenuBarWarning.evaluate(.running(fullDiskAccess: false), skippedFullDiskAccess: false, dismissedReminder: true)
        #expect(w?.symbol == "exclamationmark.magnifyingglass")
        #expect(w?.offersFullDiskAccess == false)
    }

    @Test func failureStillWinsOverTheReminder() {
        let w = MenuBarWarning.evaluate(.failed, skippedFullDiskAccess: true, dismissedReminder: false)
        #expect(w?.offersFix == true)
        #expect(w?.offersFullDiskAccess == false)
        #expect(w?.symbol == "exclamationmark.magnifyingglass")
    }

    @Test func reminderWordingNamesTheFsearchBinaryForACLIDaemon() {
        #expect(MenuBarWarning.fullDiskAccessItemTitle(ownsDaemon: true) == "Turn On Full Disk Access…")
        #expect(MenuBarWarning.fullDiskAccessItemTitle(ownsDaemon: false) == "Grant Full Disk Access to fsearch…")
    }

    @Test func anUnresponsiveHelperSaysSo() {
        let w = MenuBarWarning.evaluate(.unresponsive, skippedFullDiskAccess: false)
        #expect(w?.message == "The search helper isn't answering")
        #expect(w?.offersFix == true)
        #expect(w?.offersFullDiskAccess == false)
    }
}
