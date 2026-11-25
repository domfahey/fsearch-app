import AppKit
import FSearchKit
import Foundation
import Quartz
import Testing

@testable import FSearch

extension AppTests {
    /// The launcher window's own AppKit overrides: losing key, handing Quick
    /// Look over and back, and opening Settings outside the inert host.
    @Suite @MainActor
    struct PanelWindowTests {
        /// The shared controller, shown for `env`; the overrides below talk to it.
        func showShared(_ env: TestEnv) throws -> PanelController.Panel {
            PanelController.shared.show(app: env.app)
            return try #require(PanelController.shared.panel)
        }

        /// Clicking another app takes key from the launcher: it hides.
        @Test func losingKeyHidesTheLauncher() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let p = try showShared(env)
            #expect(PanelController.shared.isVisible)
            #expect(!QuickLookSource.shared.isPreviewing)
            p.resignKey()
            #expect(!PanelController.shared.isVisible)
        }

        /// Switching to another app hides the launcher even if resignKey did not (e.g. while Quick Look was up).
        @Test func resigningAppActiveHidesTheLauncher() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            _ = try showShared(env)
            #expect(PanelController.shared.isVisible)
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            #expect(!PanelController.shared.isVisible)
        }

        /// The launcher hands the preview its data source and takes it back when the preview closes.
        @Test func quickLookControlIsHandedOverAndBack() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let p = try showShared(env)
            let ql = try #require(QLPreviewPanel.shared())
            defer { QuickLookSource.shared.detach(ql) }
            #expect(p.acceptsPreviewPanelControl(ql))
            p.beginPreviewPanelControl(ql)
            #expect(ql.dataSource === QuickLookSource.shared)
            // Taking control twice keeps one data source (and one key monitor).
            p.beginPreviewPanelControl(ql)
            #expect(ql.dataSource === QuickLookSource.shared)
            #expect(!ql.isVisible, "the inert host never shows the preview")
            p.endPreviewPanelControl(ql)
            #expect(ql.dataSource == nil)
            // Hide before draining the async focus hand-back queued by endPreviewPanelControl, so it cannot race the next test.
            PanelController.shared.hide(returnFocus: false)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            #expect(!PanelController.shared.isVisible)
        }

        /// The preview closing while FSearch isn't the active app puts the launcher away
        /// (it would otherwise float without the keyboard). Runs only while the test
        /// host is inactive, which is the usual case; the active branch needs a key panel.
        @Test(.enabled("needs the test host inactive") { await MainActor.run { !NSApp.isActive } })
        func previewClosingWhileInactiveHidesTheLauncher() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let p = try showShared(env)
            let ql = try #require(QLPreviewPanel.shared())
            p.beginPreviewPanelControl(ql)
            p.endPreviewPanelControl(ql)
            #expect(await eventually { !PanelController.shared.isVisible })
        }

        /// The data source shows the chosen file, and nothing before one is chosen.
        @Test func theDataSourceServesTheChosenFile() throws {
            let source = QuickLookSource()
            let ql = try #require(QLPreviewPanel.shared())
            #expect(source.numberOfPreviewItems(in: ql) == 0)
            let url = URL(fileURLWithPath: "/p/heron.txt")
            source.toggle(url, inert: true)
            #expect(source.numberOfPreviewItems(in: ql) == 1)
            #expect((source.previewPanel(ql, previewItemAt: 0) as? URL) == url)
            #expect(!ql.isVisible)
            #expect(QuickLookSource.shouldHandle(.close, isRepeat: false))
            #expect(!QuickLookSource.shouldHandle(.close, isRepeat: true))
            #expect(QuickLookSource.shouldHandle(.up, isRepeat: true))
            #expect(QuickLookSource.shouldHandle(.down, isRepeat: true))
        }

        /// Outside the inert host, Settings is opened by performing the app menu's ⌘, item.
        @Test func settingsOpensThroughTheMenuOutsideTheInertHost() {
            let target = SettingsTarget()
            let menu = NSMenu()
            let item = NSMenuItem(title: "Settings…", action: #selector(SettingsTarget.settings), keyEquivalent: ",")
            item.target = target
            menu.addItem(item)
            var activations = 0
            let saved = AppActivation.activate
            AppActivation.activate = { activations += 1 }
            defer { AppActivation.activate = saved }

            #expect(PanelController.openSettingsWindow(inert: false, menu: menu))
            #expect(target.hits == 1)
            #expect(activations == 1, "brought forward first, or Settings opens behind the front app")
            // No ⌘, item: reported, nothing performed.
            #expect(!PanelController.openSettingsWindow(inert: false, menu: NSMenu()))
            #expect(target.hits == 1)
        }

        /// Installing connects the panel to the app; in test mode it neither registers
        /// the hotkey nor shows the panel.
        @Test func installConnectsTheAppWithoutShowing() {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            let items: [ResultItem] = [.file(Wire.hit("/p/a b.txt"))]
            pc.perform(.copyPath(0), items)
            #expect(env.pasteboard.string(forType: .string) == nil, "not connected yet")
            pc.install(app: env.app)
            #expect(!pc.isVisible)
            pc.perform(.copyPath(0), items)
            #expect(env.pasteboard.string(forType: .string) == "/p/a b.txt")
        }

        /// Focus is requested only after activation and presentation, on both first open and reused-view reopens.
        @Test func focusIsRequestedAfterActivationAndOnReopen() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }
            var triggerDuringActivate: [Int] = []
            let saved = AppActivation.activate
            AppActivation.activate = { triggerDuringActivate.append(pc.viewState.focusTrigger) }
            defer { AppActivation.activate = saved }

            pc.show(app: env.app)
            #expect(triggerDuringActivate == [0], "focusTrigger must not bump before activation")
            #expect(pc.viewState.focusTrigger == 1)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }

            pc.hide(returnFocus: false)
            pc.show(app: env.app)
            #expect(triggerDuringActivate == [0, 1], "reopen must also wait until after activation")
            #expect(pc.viewState.focusTrigger == 2)
            // Hiding before the deferred focus turn runs must not crash or disturb state.
            pc.hide(returnFocus: false)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            #expect(!pc.isVisible)
        }

        /// Reusing the hosting view keeps cached row frames so ⌘K still anchors to unchanged rows; rebuilding clears them.
        @Test func reopeningWithSameAppPreservesRowGeometryAndSwitchingAppClearsIt() {
            let env1 = TestEnv()
            defer { env1.tearDown() }
            let env2 = TestEnv()
            defer { env2.tearDown() }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }

            let rowRect = CGRect(x: 0, y: 100, width: 680, height: 40)
            pc.show(app: env1.app)
            pc.geometry.rows["file:/p/a.txt"] = rowRect
            pc.hide(returnFocus: false)

            pc.show(app: env1.app)
            #expect(pc.geometry.rows["file:/p/a.txt"] == rowRect, "reused hosting view must keep row frames for ⌘K")

            pc.hide(returnFocus: false)
            pc.show(app: env2.app)
            #expect(pc.geometry.rows["file:/p/a.txt"] == nil, "rebuilding contentView clears stale row frames")
        }

        @Test func restoreFocusAfterPreviewMakesKeyWhenActiveAndHidesOtherwise() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let p = try showShared(env)
            var madeKey = 0, hid = 0
            p.restoreFocusAfterPreview(isActive: true, keyWindow: nil, makeKey: { madeKey += 1 }, hide: { hid += 1 })
            p.restoreFocusAfterPreview(isActive: true, keyWindow: p, makeKey: { madeKey += 1 }, hide: { hid += 1 })
            #expect(madeKey == 2 && hid == 0)

            let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
            p.restoreFocusAfterPreview(isActive: true, keyWindow: other, makeKey: { madeKey += 1 }, hide: { hid += 1 })
            p.restoreFocusAfterPreview(isActive: false, keyWindow: nil, makeKey: { madeKey += 1 }, hide: { hid += 1 })
            #expect(madeKey == 2 && hid == 2)

            PanelController.shared.hide(returnFocus: false)
            p.restoreFocusAfterPreview(isActive: true, keyWindow: nil, makeKey: { madeKey += 1 }, hide: { hid += 1 })
            #expect(madeKey == 2 && hid == 2, "hidden panel does nothing")
        }

        @Test func installOutsideTestModeRegistersHotkeyAndHonorsShowPanel() {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            let opts = LaunchOptions(
                socketPath: env.app.options.socketPath, testMode: false, unitTestHost: false, showPanel: true,
                searchLogOverride: env.app.options.searchLogOverride)
            let app = AppState(
                options: opts, defaults: env.defaults, helper: env.helper,
                names: env.daemon, content: env.daemon, control: env.daemon, clock: env.clock.clock,
                cliAgentInstalled: { false })
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }
            var hotkey: (@MainActor () -> Void)?
            pc.install(app: app) { hotkey = $0 }
            #expect(pc.isVisible, "showPanel opens the panel during install")
            #expect(hotkey != nil)
            hotkey?()
            #expect(!pc.isVisible)
            hotkey?()
            #expect(pc.isVisible)
        }

        @Test func hostedSearchViewCallbacksDrivePanelController() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let savedSettings = PanelController.openSettings
            var settingsOpened = 0
            PanelController.openSettings = { settingsOpened += 1 }
            defer { PanelController.openSettings = savedSettings }

            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }
            pc.show(app: env.app)
            let panel = try #require(pc.panel)

            // Command row triggers onCommand -> pc.run(.settings).
            env.app.search.query = "settings"
            try #require(await axWait(id: "command-\(AppCommand.settings.id)", in: panel)).press()
            #expect(settingsOpened == 1 && !pc.isVisible)

            // Result row selection + press triggers onSelect and onEffect -> pc.perform(.open).
            let a = env.file("a.txt"), b = env.file("b.txt")
            env.daemon.onSearch = { _ in SearchReply(tookUs: 1, hits: [Wire.hit(a), Wire.hit(b)]) }
            pc.show(app: env.app)
            env.app.search.query = "txt"
            #expect(await axWait(id: "result-\(b)", in: panel) != nil)
            pc.keys.send(.down)
            #expect(await eventually { pc.selection == 1 })
            try #require(axNode(id: "result-\(b)", in: panel)).press()
            #expect(await eventually { env.workspace.opened.contains(URL(fileURLWithPath: b)) })
        }

        @Test func updatePreviousAppAndRestoreFocusOnHide() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            let panel = try #require(pc.panel)

            let current = NSRunningApplication.current
            let other = NSWorkspace.shared.runningApplications.first { $0 != current && !$0.isTerminated }

            let titledVisible = HostSafeWindow(
                contentRect: NSRect(origin: offscreenOrigin, size: NSSize(width: 100, height: 100)),
                styleMask: [.titled], backing: .buffered, defer: false)
            titledVisible.isReleasedWhenClosed = false
            Presentation.present(titledVisible, inert: true)
            defer { titledVisible.close() }
            let titledHidden = HostSafeWindow(
                contentRect: NSRect(origin: offscreenOrigin, size: NSSize(width: 100, height: 100)),
                styleMask: [.titled], backing: .buffered, defer: true)
            let borderless = HostSafeWindow(
                contentRect: NSRect(origin: offscreenOrigin, size: NSSize(width: 100, height: 100)),
                styleMask: [.borderless], backing: .buffered, defer: false)
            borderless.isReleasedWhenClosed = false
            Presentation.present(borderless, inert: true)
            defer { borderless.close() }

            #expect(!PanelController.otherWindowsVisible(except: panel, in: [panel, titledHidden, borderless]))
            #expect(PanelController.otherWindowsVisible(except: panel, in: [panel, titledVisible]))

            // Guard branches: no-op when returnFocus is false, inert is true, or app isn't active.
            var activated: [NSRunningApplication] = [], hid = 0
            pc.restoreFocusOnHide(
                except: panel, returnFocus: false, inert: false, appIsActive: true, windows: [panel],
                activate: { activated.append($0) }, hideApp: { hid += 1 })
            pc.restoreFocusOnHide(
                except: panel, returnFocus: true, inert: true, appIsActive: true, windows: [panel],
                activate: { activated.append($0) }, hideApp: { hid += 1 })
            pc.restoreFocusOnHide(
                except: panel, returnFocus: true, inert: false, appIsActive: false, windows: [panel],
                activate: { activated.append($0) }, hideApp: { hid += 1 })
            #expect(activated.isEmpty && hid == 0)

            // No other titled windows visible -> hides the app.
            pc.restoreFocusOnHide(
                except: panel, returnFocus: true, inert: false, appIsActive: true, windows: [panel],
                activate: { activated.append($0) }, hideApp: { hid += 1 })
            #expect(hid == 1 && activated.isEmpty)

            // Another titled window visible + previousApp stored -> activates previousApp, keeps our windows up.
            if let other {
                pc.updatePreviousApp(front: other, current: current, wasVisible: false)
                // Re-showing while already visible preserves previousApp.
                pc.updatePreviousApp(front: current, current: current, wasVisible: true)
                pc.restoreFocusOnHide(
                    except: panel, returnFocus: true, inert: false, appIsActive: true, windows: [panel, titledVisible],
                    activate: { activated.append($0) }, hideApp: { hid += 1 })
                #expect(activated == [other] && hid == 1)
            }

            // Fresh open when FSearch is already frontmost clears previousApp.
            pc.updatePreviousApp(front: current, current: current, wasVisible: false)
            pc.restoreFocusOnHide(
                except: panel, returnFocus: true, inert: false, appIsActive: true, windows: [panel, titledVisible],
                activate: { activated.append($0) }, hideApp: { hid += 1 })
            #expect(hid == 1)
        }
    }
}

private final class SettingsTarget: NSObject {
    var hits = 0
    @objc func settings() { hits += 1 }
}
