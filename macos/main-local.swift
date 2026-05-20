import Cocoa
import WebKit

let UI_PORT = 18922

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var serverProcess: Process?

    // Menu bar
    var statusItem: NSStatusItem!
    var codexMenuItem: NSMenuItem!
    var claudeMenuItem: NSMenuItem!
    var statusPollTimer: Timer?
    var isMenuBarOnly = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        startServer()
        createWindow()
        setupStatusBarItem()
        pollAndLoad()
    }

    // MARK: - Node server

    func startServer() {
        let resourcesURL = Bundle.main.resourceURL!
        let nodeURL   = resourcesURL.appendingPathComponent("bin/node")
        let scriptURL = resourcesURL.appendingPathComponent("index.js")

        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
            showError("Bundled Node.js not found at \(nodeURL.path). Please rebuild the app.")
            return
        }

        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [scriptURL.path, "--no-open"]
        process.currentDirectoryURL = resourcesURL
        process.terminationHandler = { _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        do {
            try process.run()
            serverProcess = process
        } catch {
            showError("Failed to start bridge: \(error.localizedDescription)")
        }
    }

    // MARK: - Main window

    func createWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Kobashi"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(webView)

        let label = NSTextField(labelWithString: "Starting Kobashi...")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 0, y: 270, width: 440, height: 24)
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        label.tag = 999
        window.contentView!.addSubview(label)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setMenuBarOnly(_ enabled: Bool) {
        guard isMenuBarOnly != enabled else { return }
        isMenuBarOnly = enabled
        NSApp.setActivationPolicy(enabled ? .accessory : .regular)
    }

    func pollAndLoad(attempt: Int = 0) {
        let url = URL(string: "http://127.0.0.1:\(UI_PORT)/api/status")!
        URLSession.shared.dataTask(with: url) { [weak self] _, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                DispatchQueue.main.async {
                    self?.window.contentView?.viewWithTag(999)?.removeFromSuperview()
                    self?.webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(UI_PORT)")!))
                    self?.startStatusPolling()
                }
            } else if attempt < 40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.pollAndLoad(attempt: attempt + 1)
                }
            }
        }.resume()
    }

    // MARK: - Menu bar

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use same icon as the app, scaled to menu bar size
            if let icon = (NSApp.applicationIconImage?.copy() as? NSImage) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
            button.toolTip = "Kobashi"
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开主界面", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Codex
        codexMenuItem = NSMenuItem(title: "- Codex", action: #selector(toggleCodex), keyEquivalent: "")
        codexMenuItem.target = self
        menu.addItem(codexMenuItem)

        // Claude Code
        claudeMenuItem = NSMenuItem(title: "- Claude Code", action: #selector(toggleClaude), keyEquivalent: "")
        claudeMenuItem.target = self
        menu.addItem(claudeMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Kobashi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func startStatusPolling() {
        statusPollTimer?.invalidate()
        refreshMenuStatus()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshMenuStatus()
        }
    }

    func refreshMenuStatus() {
        guard let url = URL(string: "http://127.0.0.1:\(UI_PORT)/api/status") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async { self?.updateMenuItems(from: json) }
        }.resume()
    }

    func updateMenuItems(from status: [String: Any]) {
        let connected = status["connected"] as? Bool ?? false
        let codexOn   = status["codexEnabled"] as? Bool ?? false
        let claudeOn  = status["claudeEnabled"] as? Bool ?? false

        if connected {
            codexMenuItem.title  = "- Codex  \(codexOn  ? "✅" : "⚪")"
            claudeMenuItem.title = "- Claude Code  \(claudeOn ? "✅" : "⚪")"
            codexMenuItem.isEnabled  = true
            claudeMenuItem.isEnabled = true
        } else {
            codexMenuItem.title  = "- Codex  —"
            claudeMenuItem.title = "- Claude Code  —"
            codexMenuItem.isEnabled  = false
            claudeMenuItem.isEnabled = false
        }
    }

    @objc func openMainWindow() {
        setMenuBarOnly(false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleCodex() {
        postToggle(path: "/api/toggle-codex") { [weak self] in self?.refreshMenuStatus() }
    }

    @objc func toggleClaude() {
        postToggle(path: "/api/toggle-claude") { [weak self] in self?.refreshMenuStatus() }
    }

    func postToggle(path: String, completion: @escaping () -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(UI_PORT)\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { completion() }
        }.resume()
    }

    // MARK: - Helpers

    func showError(_ msg: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Kobashi"
            alert.informativeText = msg
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    // Closing the window hides it; app keeps running in menu bar
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        statusPollTimer?.invalidate()
        serverProcess?.terminate()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        setMenuBarOnly(true)
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
