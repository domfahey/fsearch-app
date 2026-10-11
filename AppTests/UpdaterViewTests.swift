import AppKit
import FSearchKit
import Foundation
import Sparkle
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    /// The update items with a Sparkle controller that is never started: no
    /// check runs, nothing is written, and its buttons are never pressed.
    @Suite @MainActor
    struct UpdaterViewTests {
        /// Installs an unstarted controller; the caller removes it with `Updater.setController(nil)`.
        func installController() -> SPUStandardUpdaterController {
            let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            Updater.setController(c)
            return c
        }

        /// The Settings section mirrors the updater's setting, and Check Now waits until a check can run.
        @Test func theSettingsSectionMirrorsTheUpdater() async throws {
            let c = installController()
            defer { Updater.setController(nil) }
            let w = await render(Form { UpdatesSettingsSection() }, size: NSSize(width: 440, height: 160))
            defer { w.close() }
            let toggle = try #require(await axWait("Automatically check for updates", in: w))
            let on = c.updater.automaticallyChecksForUpdates
            #expect(await eventually { (toggle.object.value(forKey: "accessibilityValue") as? NSNumber)?.boolValue == on })
            // Not started, so no check can run yet.
            #expect(!c.updater.canCheckForUpdates)
            #expect(try #require(axNode("Check Now", in: w)).isEnabled == false)
        }

        /// The model mirrors the updater's setting and whether a check can run.
        @Test func autoCheckStateStartsFromTheUpdater() {
            let c = installController()
            defer { Updater.setController(nil) }
            let state = AutoCheckState(updater: c.updater)
            #expect(state.automatic == c.updater.automaticallyChecksForUpdates)
            #expect(!state.canCheck)
        }

        /// The menu's update items: Check for Updates… always, Update Available… only while one waits.
        @Test func theMenuItemsFollowTheReminder() async throws {
            let model = UpdateReminderModel.shared
            defer { model.update { $0.userDidReceiveAttention() } }
            _ = installController()
            defer { Updater.setController(nil) }
            let w = await render(
                VStack {
                    UpdateAvailableItem(); CheckForUpdatesItem()
                }, size: NSSize(width: 300, height: 80))
            defer { w.close() }
            #expect(try #require(await axWait("Check for Updates…", in: w)).isEnabled == false)
            #expect(!axTexts(in: w).contains("Update Available…"))
            model.update { $0.willShow(bySparkle: false, userInitiated: false) }
            #expect(await eventually { axTexts(in: w).contains("Update Available…") })
        }

        /// Without a configured updater the update items stay out of the menu and Settings.
        @Test func noControllerNoUpdateItems() async {
            #expect(Updater.controller == nil)
            let w = await render(
                VStack {
                    Text(axSentinel); UpdateAvailableItem(); CheckForUpdatesItem(); Form { UpdatesSettingsSection() }
                },
                size: NSSize(width: 300, height: 120))
            defer { w.close() }
            #expect(await axWait(axSentinel, in: w) != nil)
            #expect(!axTexts(in: w).contains("Check for Updates…"))
            #expect(!axTexts(in: w).contains("Automatically check for updates"))
        }
    }

    @Suite @MainActor
    struct UpdateDriverShowingTests {
        /// Sparkle's own state object has no public init: decode one, as Sparkle's XPC path does.
        func state(userInitiated: Bool) throws -> SPUUserUpdateState {
            let archiver = NSKeyedArchiver(requiringSecureCoding: true)
            archiver.setClassName("SPUUserUpdateState", for: StateStandIn.self)
            archiver.encode(StateStandIn(userInitiated: userInitiated), forKey: NSKeyedArchiveRootObjectKey)
            archiver.finishEncoding()
            return try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: SPUUserUpdateState.self, from: archiver.encodedData))
        }

        @Test func theStandInDecodes() throws {
            #expect(try state(userInitiated: true).userInitiated)
            #expect(try !state(userInitiated: false).userInitiated)
        }

        /// A scheduled update Sparkle leaves to us shows as the menu-bar indicator, without activating the app.
        @Test func aGentleReminderShowsTheIndicator() throws {
            let model = UpdateReminderModel.shared
            defer { model.update { $0.userDidReceiveAttention() } }
            var activations = 0
            let saved = AppActivation.activate
            AppActivation.activate = { activations += 1 }
            defer { AppActivation.activate = saved }
            let driver = UpdateReminderDriver()

            driver.standardUserDriverWillHandleShowingUpdate(false, forUpdate: .empty(), state: try state(userInitiated: false))
            #expect(model.indicatorVisible)
            #expect(activations == 0)
        }

        /// Sparkle showing its own window (a check the user asked for) brings the app forward for it.
        @Test func sparklesOwnWindowActivatesTheApp() throws {
            let model = UpdateReminderModel.shared
            defer { model.update { $0.userDidReceiveAttention() } }
            var activations = 0
            let saved = AppActivation.activate
            AppActivation.activate = { activations += 1 }
            defer { AppActivation.activate = saved }
            let driver = UpdateReminderDriver()

            driver.standardUserDriverWillHandleShowingUpdate(true, forUpdate: .empty(), state: try state(userInitiated: true))
            #expect(activations == 1)
            #expect(!model.indicatorVisible)
        }
    }

    @Suite @MainActor
    struct ActivationObserverTests {
        /// Coming back to the app after the menu's Full Disk Access item restarts our helper once.
        @Test func becomingActiveRestartsAnArmedHelper() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            d.onPing = { _ in false }
            let m = DaemonManager(
                client: d, service: h, cliAgentInstalled: { false }, clock: FakeClock().clock, socketHolder: { .ours },
                defaults: TestEnv.emptySuite(TestEnv.unitSuite), helperIdentity: { nil }, fullDiskAccessGranted: { false })
            defer { _ = TestEnv.emptySuite(TestEnv.unitSuite) }
            await m.refresh()
            m.armFullDiskAccessRestart()
            let center = NotificationCenter()
            LaunchGuards.observeActivation(daemon: m, center: center)
            defer { LaunchGuards.stopObservingActivation(center: center) }
            #expect(h.unregistered == 0)
            center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            #expect(await eventually { h.unregistered == 1 })
            #expect(!m.fullDiskAccessRestartArmed)
        }
    }
}

/// Encodes the two fields SPUUserUpdateState decodes.
@objc(FSearchTestsStateStandIn)
private final class StateStandIn: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let userInitiated: Bool
    init(userInitiated: Bool) { self.userInitiated = userInitiated }
    required init?(coder: NSCoder) { userInitiated = coder.decodeBool(forKey: "SPUUserUpdateStateUserInitiated") }
    func encode(with coder: NSCoder) {
        coder.encode(0, forKey: "SPUUserUpdateStateStage")
        coder.encode(userInitiated, forKey: "SPUUserUpdateStateUserInitiated")
    }
}
