import AppKit
import ScreenSaver

final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindowController: PreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PreviewWindowController()
        previewWindowController = controller
        installMainMenu(for: controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMainMenu(for controller: PreviewWindowController) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Are.na Preview", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Are.na Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Edit"
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSStandardKeyBindingResponding.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenuItem.submenu = editMenu

        let previewMenuItem = NSMenuItem()
        previewMenuItem.title = "Preview"
        mainMenu.addItem(previewMenuItem)
        let previewMenu = NSMenu(title: "Preview")
        let restartItem = previewMenu.addItem(withTitle: "Restart Preview", action: #selector(PreviewWindowController.restartPreview), keyEquivalent: "r")
        restartItem.target = controller
        let settingsItem = previewMenu.addItem(withTitle: "Settings…", action: #selector(PreviewWindowController.showSettings), keyEquivalent: ",")
        settingsItem.target = controller
        previewMenuItem.submenu = previewMenu

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "View"
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let fullScreenItem = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(PreviewWindowController.toggleFullScreen), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        fullScreenItem.target = controller
        viewMenuItem.submenu = viewMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}

final class PreviewWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private enum ToolbarItem {
        static let restart = NSToolbarItem.Identifier("com.arena.preview.restart")
        static let settings = NSToolbarItem.Identifier("com.arena.preview.settings")
        static let fullScreen = NSToolbarItem.Identifier("com.arena.preview.fullScreen")
    }

    private let previewContainer = NSView()
    private var screenSaverView: ArenaScreenSaverView?
    private var chromeEventMonitor: Any?
    private var hideChromeWorkItem: DispatchWorkItem?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Are.na Screen Saver Preview"
        window.minSize = NSSize(width: 640, height: 400)
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.center()

        super.init(window: window)
        window.delegate = self
        installContentView()
        installToolbar()
        installChromeTracking()
        restartPreview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        hideChromeWorkItem?.cancel()
        if let chromeEventMonitor {
            NSEvent.removeMonitor(chromeEventMonitor)
        }
    }

    private func installContentView() {
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.black.cgColor
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = window?.contentView else { return }
        contentView.addSubview(previewContainer)
        NSLayoutConstraint.activate([
            previewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func installToolbar() {
        let toolbar = NSToolbar(identifier: "ArenaPreviewToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window?.toolbarStyle = .unified
        window?.toolbar = toolbar
        setChromeVisible(false)
    }

    private func installChromeTracking() {
        chromeEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            self?.handlePointer(event)
            return event
        }
    }

    private func handlePointer(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        let isNearTopEdge = event.locationInWindow.y >= window.frame.height - 96
        if isNearTopEdge {
            hideChromeWorkItem?.cancel()
            setChromeVisible(true)
        } else {
            scheduleChromeHide()
        }
    }

    private func scheduleChromeHide() {
        hideChromeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.window?.attachedSheet == nil else { return }
            self.setChromeVisible(false)
        }
        hideChromeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func setChromeVisible(_ isVisible: Bool) {
        window?.toolbar?.isVisible = isVisible
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(buttonType)?.isHidden = !isVisible
        }
    }

    @objc func restartPreview() {
        screenSaverView?.stopAnimation()
        screenSaverView?.removeFromSuperview()

        guard let view = ArenaScreenSaverView(frame: previewContainer.bounds, isPreview: false) else {
            showError("The screen-saver view did not start.")
            return
        }
        view.autoresizingMask = [.width, .height]
        previewContainer.addSubview(view)
        screenSaverView = view
        view.startAnimation()
    }

    @objc func showSettings() {
        guard let window,
              window.attachedSheet == nil,
              let settingsWindow = screenSaverView?.configureSheet else { return }
        hideChromeWorkItem?.cancel()
        setChromeVisible(true)
        window.beginSheet(settingsWindow)
    }

    @objc func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func windowWillClose(_ notification: Notification) {
        screenSaverView?.stopAnimation()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard window?.attachedSheet == nil else { return }
        setChromeVisible(false)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItem.restart, ToolbarItem.settings, .flexibleSpace, ToolbarItem.fullScreen]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItem.restart, ToolbarItem.settings, .flexibleSpace, ToolbarItem.fullScreen]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self

        switch itemIdentifier {
        case ToolbarItem.restart:
            item.label = "Restart"
            item.paletteLabel = "Restart Preview"
            item.toolTip = "Restart the screen-saver view."
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Restart")
            item.action = #selector(restartPreview)
        case ToolbarItem.settings:
            item.label = "Settings"
            item.paletteLabel = "Screen Saver Settings"
            item.toolTip = "Change the screen-saver settings."
            item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Settings")
            item.action = #selector(showSettings)
        case ToolbarItem.fullScreen:
            item.label = "Full Screen"
            item.paletteLabel = "Full Screen"
            item.toolTip = "Show the preview in full screen."
            item.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Full Screen")
            item.action = #selector(toggleFullScreen)
        default:
            return nil
        }
        return item
    }

    private func showError(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

}
