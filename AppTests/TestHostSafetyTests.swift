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
