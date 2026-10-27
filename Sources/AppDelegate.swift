import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: DashboardController!
    private var hotKey: GlobalHotKey!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = DashboardController()
        hotKey = GlobalHotKey { [weak self] in
            self?.controller.toggle()
        }
        setUpStatusItem()
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "square.grid.2x2.fill",
                accessibilityDescription: "Dashboard"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Dashboard Reborn"
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "打开 Dashboard (F12)",
            action: #selector(openDashboard),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let rescanItem = NSMenuItem(
            title: "重新读取 App 列表",
            action: #selector(rescanApps),
            keyEquivalent: "r"
        )
        rescanItem.target = self
        menu.addItem(rescanItem)

        let restoreItem = NSMenuItem(
            title: "恢复被移除的 App",
            action: #selector(restoreHiddenApps),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        let resetItem = NSMenuItem(
            title: "重置布局…",
            action: #selector(resetLayout),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 Dashboard",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func openDashboard() {
        controller.show()
    }

    @objc private func openSettings() {
        controller.showSettings()
    }

    @objc private func rescanApps() {
        controller.show()
    }

    @objc private func restoreHiddenApps() {
        controller.model.restoreHiddenApps()
        controller.show()
    }

    @objc private func resetLayout() {
        controller.resetLayout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
