import AppKit
import FSearchKit
import Foundation
import Quartz
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    /// The user works at this Mac while AppTests run: nothing here may show a
    /// window they can see, take the keyboard, or bring FSearch to the front.
    @Suite @MainActor
    struct TestHostSafetyTests {
        /// The menu-bar item's own window is the one visible window the host may have.
        private static func isStatusItem(_ w: NSWindow) -> Bool {
            NSStringFromClass(type(of: w)).contains("StatusBar")
        }

        /// Every way the app can put a window up or activate itself, run in
        /// this host: afterwards no window is key and none shows at alpha > 0.
        @Test func noWindowIsKeyOrVisible() async {
            #expect(LaunchOptions.current.unitTestHost)
            #expect(Presentation.inert)
            let wasActive = NSApp.isActive
            // A helper and no "onboarded" flag: launch() shows onboarding.
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            let path = env.file("x.txt")
            let items: [ResultItem] = [.file(Wire.hit(path))]

            AppActivation.activate()
            PanelController.openSettings()
            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            #expect(pc.panel?.canBecomeKey == false)
            OnboardingLauncher.launch(app: env.app)
            let onboarding = OnboardingLauncher.window
            #expect(onboarding != nil)
            #expect(onboarding?.canBecomeKey == false)
            #expect(onboarding?.canBecomeMain == false)
            OnboardingLauncher.reopen(app: env.app)
            #expect(OnboardingLauncher.window === onboarding)
            // The real popUp: inert here, so no modal menu comes up.
            ActionsMenu.show(for: items[0], in: pc.panel, app: env.app)
            pc.perform(.showActions(0), items)
            QuickLookSource.shared.toggle(URL(fileURLWithPath: path))
            #expect(QuickLookSource.shared.item == URL(fileURLWithPath: path))
            pc.perform(.quickLook(0), items)
            let w = await render(Text("render"), size: NSSize(width: 100, height: 40))
            defer { w.close() }
            #expect(w.canBecomeKey == false)
            // Hiding with "return focus" moves no focus between apps here.
            pc.hide()
            pc.show(app: env.app)
            // Let AppKit settle key and active state.
            try? await Task.sleep(for: .milliseconds(300))

            #expect(NSApp.keyWindow == nil)
            let key = NSApp.windows.filter(\.isKeyWindow)
            #expect(key.isEmpty, "key: \(key.map { NSStringFromClass(type(of: $0)) })")
            let shown = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 && !Self.isStatusItem($0) }
            #expect(shown.isEmpty, "visible: \(shown.map { "\(NSStringFromClass(type(of: $0))) '\($0.title)' \($0.frame)" })")
            #expect(!QLPreviewPanel.sharedPreviewPanelExists() || !QLPreviewPanel.shared().isVisible)
            if !wasActive { #expect(!NSApp.isActive) }
        }

        /// The real activation closure checks the host on every call.
        @Test func activationIsANoOpWhenInert() {
            var calls = 0
            AppActivation.live(inert: { true }, activate: { calls += 1 })()
            #expect(calls == 0)
            AppActivation.live(inert: { false }, activate: { calls += 1 })()
            #expect(calls == 1)
        }

        /// The real Settings opener does nothing in this host.
        @Test func openSettingsIsInert() async {
            let before = NSApp.windows.filter(\.isVisible).count
            PanelController.openSettings()
            try? await Task.sleep(for: .milliseconds(100))
            #expect(NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 && !Self.isStatusItem($0) }.isEmpty)
            #expect(NSApp.windows.filter(\.isVisible).count == before)
        }
    }
}

extension AppTests {
    /// Launch paths that must stay quiet under test: no Sparkle, no global
    /// hotkey, no menu-bar item in the unit-test host, no restored windows,
    /// no writes to the user's clipboard or logs.
    @Suite @MainActor
    struct LaunchSafetyTests {
        private func options(testMode: Bool, unitTestHost: Bool) -> LaunchOptions {
            LaunchOptions(socketPath: "/tmp/x.sock", testMode: testMode, unitTestHost: unitTestHost, showPanel: false)
        }

        /// UI-test launches would otherwise check for updates against the real
        /// feed and write SULastCheckTime once a real key ships.
        @Test func sparkleNeverStartsInTestMode() {
            #expect(Updater.shouldStart(configured: true, testMode: false))
            #expect(!Updater.shouldStart(configured: true, testMode: true))
            #expect(!Updater.shouldStart(configured: false, testMode: false))
            Updater.start()
            #expect(Updater.controller == nil)
        }

        /// A UI-test app must not grab the user's own ⌥Space.
        @Test func globalHotkeyOnlyOutsideTestMode() {
            #expect(PanelController.registersGlobalHotkey(options(testMode: false, unitTestHost: false)))
            #expect(!PanelController.registersGlobalHotkey(options(testMode: true, unitTestHost: false)))
            #expect(!PanelController.registersGlobalHotkey(options(testMode: true, unitTestHost: true)))
        }

        /// The UI tests click the menu-bar item, so it stays in UI-test mode.
        @Test func menuBarItemIsLeftOutOfTheUnitTestHostOnly() {
            #expect(FSearchApp.showsMenuBarItem(options(testMode: false, unitTestHost: false)))
            #expect(FSearchApp.showsMenuBarItem(options(testMode: true, unitTestHost: false)))
            #expect(!FSearchApp.showsMenuBarItem(options(testMode: true, unitTestHost: true)))
        }

        /// A removed MenuBarExtra leaves its window parked off every screen.
        @Test func noStatusItemOnScreenInThisHost() async {
            try? await Task.sleep(for: .milliseconds(100))
            let onScreen = NSApp.windows.filter { w in
                NSStringFromClass(type(of: w)).contains("StatusBar") && w.isVisible
                    && NSScreen.screens.contains { $0.frame.intersects(w.frame) }
            }
            #expect(onScreen.isEmpty, "\(onScreen.map { "\(NSStringFromClass(type(of: $0))) \($0.frame)" })")
        }

        /// The host never reopens windows AppKit saved from an earlier run.
        @Test func hostIgnoresPersistedWindowState() {
            #expect(UserDefaults.standard.bool(forKey: "ApplePersistenceIgnoreState"))
        }

        /// Copies in this host never reach the user's clipboard, even before a TestEnv swaps it.
        @Test func defaultPasteboardIsPrivateInTheUnitTestHost() {
            #expect(FileActions.defaultPasteboard(for: options(testMode: false, unitTestHost: false)) === NSPasteboard.general)
            let host = FileActions.defaultPasteboard(for: options(testMode: true, unitTestHost: true))
            #expect(host !== NSPasteboard.general)
            #expect(host.name != NSPasteboard.general.name)
        }

        @Test func searchLogOverride() {
            let url = URL(fileURLWithPath: "/tmp/fsa/searches.jsonl")
            var o = options(testMode: false, unitTestHost: false)
            o.searchLogOverride = url
            #expect(o.searchLogFile == url)
        }

        /// A TestEnv with a helper is not test mode, yet its search log stays in its temp folder.
        @Test func testEnvLogStaysInItsFolder() {
            let env = TestEnv(helper: FakeHelper())
            defer { env.tearDown() }
            #expect(env.app.log.file.path.hasPrefix(env.dir.path))
            #expect(!env.app.options.testMode)
        }

        /// Every TestEnv shares one defaults suite, emptied for each.
        @Test func testEnvsShareOneEmptiedSuite() {
            let a = TestEnv()
            a.defaults.set("x", forKey: "editor")
            let name = a.suite
            a.tearDown()
            let b = TestEnv()
            defer { b.tearDown() }
            #expect(b.suite == name)
            #expect(b.defaults.object(forKey: "editor") == nil)
        }
    }
}
