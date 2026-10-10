import Testing

@testable import FSearchKit

@Suite struct UpdateReminderTests {
    @Test func sparkleShowsAScheduledUpdateOnlyWhenInImmediateFocus() {
        let r = UpdateReminder()
        #expect(r.sparkleShouldShowScheduled(immediateFocus: true))
        #expect(!r.sparkleShouldShowScheduled(immediateFocus: false))
    }

    @Test func indicatorAppearsWhenSparkleLeavesTheUpdateToUs() {
        var r = UpdateReminder()
        r.willShow(bySparkle: false, userInitiated: false)
        #expect(r.indicatorVisible)
    }

    @Test func indicatorStaysOffWhenSparkleShowsItOrTheUserAskedForIt() {
        var r = UpdateReminder()
        r.willShow(bySparkle: true, userInitiated: false)
        #expect(!r.indicatorVisible)
        r.willShow(bySparkle: false, userInitiated: true)
        #expect(!r.indicatorVisible)
    }

    @Test func attentionAndSessionEndClearTheIndicator() {
        var r = UpdateReminder()
        r.willShow(bySparkle: false, userInitiated: false)
        r.userDidReceiveAttention()
        #expect(!r.indicatorVisible)
        r.willShow(bySparkle: false, userInitiated: false)
        r.sessionWillFinish()
        #expect(!r.indicatorVisible)
    }

    @Test func aRemindedUpdateIsLookedUpAgainAtLaunch() {
        #expect(UpdateReminder.checkAtLaunch(persistedVisible: true, updaterRunning: true))
        #expect(!UpdateReminder.checkAtLaunch(persistedVisible: true, updaterRunning: false))
        #expect(!UpdateReminder.checkAtLaunch(persistedVisible: false, updaterRunning: true))
    }
}
