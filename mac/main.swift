import Cocoa
import WebKit

// MARK: - Views

/// Transparent strip over the top of the main window so it can be dragged by its "title bar".
final class DragStrip: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// Covers the desktop widget: drag to move it, click to open Calmii, right-click for options.
final class WidgetHandle: NSView {
    var onClick: () -> Void = {}
    var onMenu: (NSEvent) -> Void = { _ in }
    var onMoved: () -> Void = {}
    private var start = NSPoint.zero
    private var origin = NSPoint.zero
    private var moved = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - start.x, dy = p.y - start.y
        if abs(dx) + abs(dy) > 3 { moved = true }
        window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        if moved { onMoved() } else { onClick() }
    }
    override func rightMouseDown(with event: NSEvent) { onMenu(event) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var mainWindow: NSWindow!
    var mainWeb: WKWebView!
    var widgetWindow: NSWindow?
    var statusItem: NSStatusItem!
    let defaults = UserDefaults.standard
    lazy var webRoot = Bundle.main.resourceURL!.appendingPathComponent("web")

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        makeMainWindow()
        makeStatusItem()
        if defaults.object(forKey: "widgetOn") as? Bool ?? true { showWidget() }
        openMain()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMain(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: web views

    func makeWebView(query: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(self, name: "calmii")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        let index = webRoot.appendingPathComponent("index.html")
        let url = URL(string: index.absoluteString + "?" + query)!
        web.loadFileURL(url, allowingReadAccessTo: webRoot)
        return web
    }

    func makeMainWindow() {
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.titleVisibility = .hidden
        mainWindow.title = "Calmii"
        mainWindow.isReleasedWhenClosed = false
        mainWindow.minSize = NSSize(width: 360, height: 600)
        mainWindow.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.08, green: 0.106, blue: 0.21, alpha: 1)
                : NSColor(srgbRed: 0.435, green: 0.682, blue: 0.86, alpha: 1)
        }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 780))
        mainWeb = makeWebView(query: "app=1")
        mainWeb.frame = content.bounds
        mainWeb.autoresizingMask = [.width, .height]
        content.addSubview(mainWeb)

        let strip = DragStrip(frame: NSRect(x: 76, y: 0, width: 1000, height: 28))
        strip.autoresizingMask = [.width, .minYMargin]
        content.addSubview(strip)
        mainWindow.contentView = content
        // place strip at the top once sized
        strip.frame = NSRect(x: 76, y: content.bounds.height - 28, width: content.bounds.width - 76, height: 28)

        mainWindow.center()
        mainWindow.setFrameAutosaveName("CalmiiMain")
    }

    func openMain(tab: String? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
        if let tab { mainWeb.evaluateJavaScript("window.calmiiGo && window.calmiiGo('\(tab)')") }
    }

    // MARK: desktop widget

    func showWidget() {
        if widgetWindow == nil {
            let size: CGFloat = 200
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            var origin = NSPoint(x: screen.maxX - size - 24, y: screen.maxY - size - 24)
            if let s = defaults.string(forKey: "widgetOrigin") { origin = NSPointFromString(s) }

            let w = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

            let content = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
            let web = makeWebView(query: "widget=1")
            web.frame = content.bounds
            web.autoresizingMask = [.width, .height]
            content.addSubview(web)

            let handle = WidgetHandle(frame: content.bounds)
            handle.autoresizingMask = [.width, .height]
            handle.onClick = { [weak self] in self?.openMain(tab: "breathe") }
            handle.onMoved = { [weak self, weak w] in
                guard let w else { return }
                self?.defaults.set(NSStringFromPoint(w.frame.origin), forKey: "widgetOrigin")
            }
            handle.onMenu = { [weak self] event in
                guard let self else { return }
                let m = NSMenu()
                m.addItem(withTitle: "Breathe", action: #selector(self.menuBreathe), keyEquivalent: "").target = self
                m.addItem(withTitle: "Open Calmii", action: #selector(self.menuOpen), keyEquivalent: "").target = self
                m.addItem(.separator())
                m.addItem(withTitle: "Hide Desktop Widget", action: #selector(self.toggleWidget), keyEquivalent: "").target = self
                NSMenu.popUpContextMenu(m, with: event, for: handle)
            }
            content.addSubview(handle)
            w.contentView = content
            widgetWindow = w
        }
        widgetWindow?.orderFront(nil)
        defaults.set(true, forKey: "widgetOn")
        refreshStatusMenu()
    }

    func hideWidget() {
        widgetWindow?.orderOut(nil)
        defaults.set(false, forKey: "widgetOn")
        refreshStatusMenu()
    }

    @objc func toggleWidget() {
        if widgetWindow?.isVisible == true { hideWidget() } else { showWidget() }
    }

    // MARK: menu bar

    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Calmii") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "◎"
        }
        refreshStatusMenu()
    }

    func refreshStatusMenu() {
        guard statusItem != nil else { return }
        let m = NSMenu()
        m.addItem(withTitle: "Breathe", action: #selector(menuBreathe), keyEquivalent: "").target = self
        m.addItem(withTitle: "Calm Toolkit", action: #selector(menuCalm), keyEquivalent: "").target = self
        m.addItem(withTitle: "Play", action: #selector(menuPlay), keyEquivalent: "").target = self
        m.addItem(withTitle: "Escape", action: #selector(menuEscape), keyEquivalent: "").target = self
        m.addItem(.separator())
        let w = m.addItem(withTitle: "Desktop Widget", action: #selector(toggleWidget), keyEquivalent: "")
        w.target = self
        w.state = widgetWindow?.isVisible == true ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Calmii", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }

    @objc func menuOpen() { openMain() }
    @objc func menuBreathe() { openMain(tab: "breathe") }
    @objc func menuCalm() { openMain(tab: "calm") }
    @objc func menuPlay() { openMain(tab: "play") }
    @objc func menuEscape() { openMain(tab: "escape") }

    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Calmii", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Toggle Desktop Widget", action: #selector(toggleWidget), keyEquivalent: "d").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Calmii", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Calmii", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }

    // MARK: web bridge

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "openURL":
            if let s = body["url"] as? String, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case "open":
            openMain()
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, ["http", "https", "mailto", "tel", "sms"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
