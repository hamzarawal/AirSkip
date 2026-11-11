import AppKit
import Combine
import SwiftUI

final class AirSkipAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem?
    private var controlsWindow: NSWindow?
    private let controlsMenu = NSMenu()
    private var menuPanelController: NSHostingController<ControlPanel>?
    private var enabledSubscription: AnyCancellable?
    private var panelSizeSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit AirSkip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        NSApp.mainMenu = menu

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Use our own stable identifier instead of SwiftUI's saved CC Item-0 visibility.
        item.autosaveName = "AirSkipStatusItem"
        item.isVisible = true
        statusItem = item
        item.button?.toolTip = "AirSkip — open case controls"
        item.button?.setAccessibilityLabel("AirSkip")
        enabledSubscription = model.$enabled.sink { [weak self] enabled in
            self?.updateIcon(enabled: enabled)
        }

        // A real status-item menu keeps an auto-hidden menu bar revealed for
        // the entire interaction. A standalone popover does not own menu
        // tracking, so its anchor can disappear when the pointer leaves the bar.
        controlsMenu.autoenablesItems = false
        controlsMenu.delegate = self
        let controller = makeControlPanelController()
        menuPanelController = controller
        let panelItem = NSMenuItem()
        panelItem.view = controller.view
        controlsMenu.addItem(panelItem)
        item.menu = controlsMenu
        showControlsWindow()
        panelSizeSubscription = model.$verified.combineLatest(model.$accessibilityReady)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeControlsWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model == nil {
            controlsWindow?.makeKeyAndOrderFront(nil)
            return true
        }
        statusItem?.isVisible = true
        showControlsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        model == nil
    }

    private func updateIcon(enabled: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = BrandIcon.menuBarImage()
        button.toolTip = "AirSkip — \(enabled ? "enabled" : "disabled") · open case controls"
        button.title = ""
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === controlsMenu else { return }
        // Keep one visible set of controls, backed by the same model.
        controlsWindow?.orderOut(nil)
        menuPanelController?.view.setFrameSize(controlPanelSize(on: statusItem?.button?.window?.screen))
    }

    private func showControlsWindow() {
        controlsMenu.cancelTracking()
        if controlsWindow == nil {
            let window = NSWindow(contentViewController: makeControlPanelController())
            window.title = "AirSkip"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(controlPanelSize(on: window.screen))
            window.center()
            controlsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        controlsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeControlPanelController() -> NSHostingController<ControlPanel> {
        let controller = NSHostingController(rootView: ControlPanel(model: model))
        // AppKit owns the viewport size; setup and diagnostics only change the
        // scrollable content, without imposing a taller SwiftUI root view.
        controller.sizingOptions = []
        controller.view.setFrameSize(controlPanelSize(on: nil))
        return controller
    }

    private func resizeControlsWindow() {
        guard let window = controlsWindow else { return }
        let contentSize = controlPanelSize(on: window.screen)
        let contentFrame = NSRect(origin: .zero, size: contentSize)
        var frame = window.frame
        let height = window.frameRect(forContentRect: contentFrame).height
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }

    private func controlPanelSize(on screen: NSScreen?) -> NSSize {
        var preferredHeight: CGFloat = 405
        if !model.verified { preferredHeight += 155 }
        if !model.accessibilityReady { preferredHeight += 60 }
        let visibleHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? preferredHeight + 40
        // Leave room for the menu border and screen edges.
        return NSSize(width: 390, height: min(preferredHeight, max(1, visibleHeight - 40)))
    }
}
