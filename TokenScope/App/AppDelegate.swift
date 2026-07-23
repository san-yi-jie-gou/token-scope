import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = UsageStore()
    private var panel: DesktopPanel?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var refreshTimer: Timer?
    private weak var includesCacheItem: NSMenuItem?
    private weak var floatingItem: NSMenuItem?
    private weak var loginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NSApp.setActivationPolicy(.accessory)
        WidgetSnapshotServer.shared.start()
        let desktopPanel = DesktopPanel(store: store)
        panel = desktopPanel
        store.onRequestDataDirectoryAccess = { [weak self] in
            self?.chooseDataDirectory()
        }
        store.onLayoutChange = { [weak desktopPanel] count, range in
            desktopPanel?.updateLayout(activeAgentCount: count, range: range)
        }
        configureStatusItem()
        panel?.show()
        if store.hasDataDirectoryAccess {
            store.refresh()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.chooseDataDirectory()
            }
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
        refreshTimer?.tolerance = 20
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        includesCacheItem?.state = store.includesCache ? .on : .off
        floatingItem?.state = panel?.floatsAboveWindows == true ? .on : .off
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleVisibility() {
        guard let panel else { return }
        panel.isVisible ? panel.orderOut(nil) : panel.show()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isContextClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true

        if isContextClick {
            showStatusMenu(using: sender)
        } else {
            toggleVisibility()
        }
    }

    @objc private func toggleFloating() {
        panel?.floatsAboveWindows.toggle()
        panel?.show()
    }

    @objc private func toggleIncludesCache() {
        store.includesCache.toggle()
    }

    @objc private func chooseDataDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.title = "授权 TokenScope 读取用量数据"
        openPanel.message = "请选择你的个人主目录。TokenScope 只会读取其中 Coding Agent 的本地用量记录。"
        openPanel.prompt = "授权"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Users", isDirectory: true)

        NSApp.activate(ignoringOtherApps: true)
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        do {
            try store.authorizeDataDirectory(url)
            panel?.show()
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法授权数据目录"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录启动设置"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "TokenScope")
        item.button?.toolTip = "TokenScope"
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.delegate = self

        let includesCache = NSMenuItem(
            title: "包含缓存",
            action: #selector(toggleIncludesCache),
            keyEquivalent: ""
        )
        includesCache.target = self
        menu.addItem(includesCache)
        includesCacheItem = includesCache

        menu.addItem(.separator())

        let dataDirectory = NSMenuItem(
            title: "数据目录…",
            action: #selector(chooseDataDirectory),
            keyEquivalent: ""
        )
        dataDirectory.target = self
        menu.addItem(dataDirectory)

        let floating = NSMenuItem(title: "浮在窗口上方", action: #selector(toggleFloating), keyEquivalent: "")
        floating.target = self
        menu.addItem(floating)
        floatingItem = floating

        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginItem = login

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 TokenScope", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusMenu = menu
        statusItem = item
    }

    private func showStatusMenu(using button: NSStatusBarButton) {
        guard let statusItem, let statusMenu else { return }
        statusItem.menu = statusMenu
        button.performClick(nil)
        statusItem.menu = nil
    }
}
