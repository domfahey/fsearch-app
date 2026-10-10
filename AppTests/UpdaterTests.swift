import FSearchKit
import Foundation
import Sparkle
import Testing
@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct UpdaterTests {
        @Test func notStartedWithThePlaceholderKey() {
            #expect(!Updater.isConfigured)
            #expect(Updater.controller == nil)
        }

        @Test func driverShowsScheduledUpdatesOnlyInImmediateFocus() {
            let driver = UpdateReminderDriver()
            let item = SUAppcastItem.empty()
            #expect(driver.supportsGentleScheduledUpdateReminders)
            #expect(driver.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: true))
            #expect(!driver.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: false))
        }

        @Test func attentionAndSessionEndClearTheSharedIndicator() {
            let model = UpdateReminderModel.shared
            let driver = UpdateReminderDriver()
            let item = SUAppcastItem.empty()
            model.update { $0.willShow(bySparkle: false, userInitiated: false) }
            #expect(model.indicatorVisible)
            driver.standardUserDriverDidReceiveUserAttention(forUpdate: item)
            #expect(!model.indicatorVisible)
            model.update { $0.willShow(bySparkle: false, userInitiated: false) }
            driver.standardUserDriverWillFinishUpdateSession()
            #expect(!model.indicatorVisible)
        }
    }
}
