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

    @Test func skippedFullDiskAccessStaysQuiet() {
        #expect(MenuBarWarning.evaluate(.running(fullDiskAccess: false), skippedFullDiskAccess: true) == nil)
    }
}
