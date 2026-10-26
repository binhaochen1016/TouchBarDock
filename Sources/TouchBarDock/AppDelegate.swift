import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let controller = DockTouchBarController.shared
    private var statusItem: NSStatusItem?
    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private let model = AppModel()
    private let autoLaunchConfiguredKey = "TouchBarDock.autoLaunchConfigured"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startObserving()
        enableAutoLaunchOnFirstRun()
        controller.present()

        // 兜底：部分系统转场（锁屏/全屏切换）会收走模态栏，定时重挂（幂等，不重建不闪）
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.controller.rePresent()
        }
    }

    // MARK: - 登录自启动

    private func enableAutoLaunchOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: autoLaunchConfiguredKey) else { return }
        UserDefaults.standard.set(true, forKey: autoLaunchConfiguredKey)
        setAutoLaunch(true)
    }

    private func setAutoLaunch(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 记录到诊断日志，不打断运行
            let path = NSHomeDirectory() + "/Library/Logs/TouchBarDock.log"
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            if let handle = FileHandle(forWritingAtPath: path) {
                let line = "[\(Date())] SMAppService \(enabled ? "register" : "unregister") 失败: \(error)\n"
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出时恢复系统 Control Strip，不留烂摊子
        controller.dismiss()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "TouchBarDock")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    /// 每次点开菜单时重建（保证固定状态最新）。
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let pinItem = NSMenuItem(
            title: "📌 固定当前前台 App",
            action: #selector(pinFrontmost), keyEquivalent: ""
        )
        pinItem.target = self
        menu.addItem(pinItem)

        // 收起/展开模式切换
        let collapseItem = NSMenuItem(
            title: controller.isCollapsed ? "展开为程序坞" : "收起为一个图标",
            action: #selector(toggleCollapseMode), keyEquivalent: ""
        )
        collapseItem.target = self
        menu.addItem(collapseItem)

        // 登录自启动开关
        let launchItem = NSMenuItem(
            title: "开机自启动",
            action: #selector(toggleAutoLaunch), keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        // 自定义 Dock 应用：列出本机已安装 App，勾选即固定
        let custom = NSMenuItem(title: "自定义 Dock 应用…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for app in model.installedApps() {
            let item = NSMenuItem(
                title: app.name,
                action: #selector(togglePinApp(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = app.bundleID
            item.image = app.icon
            item.image?.size = NSSize(width: 16, height: 16)
            item.state = model.isPinned(app.bundleID) ? .on : .off
            submenu.addItem(item)
        }
        custom.submenu = submenu
        menu.addItem(custom)

        let pinned = model.pinnedBundleIDs
        if !pinned.isEmpty {
            menu.addItem(.separator())
            for id in pinned {
                let title = model.dockApps().first(where: { $0.bundleID == id })?.name ?? id
                let unpin = NSMenuItem(
                    title: "取消固定 \(title)",
                    action: #selector(unpinPinned(_:)), keyEquivalent: ""
                )
                unpin.target = self
                unpin.representedObject = id
                menu.addItem(unpin)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 TouchBarDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func pinFrontmost() {
        guard let id = model.frontmostRegularBundleID else { return }
        model.togglePin(id)
        controller.refresh()
    }

    @objc private func unpinPinned(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model.togglePin(id)
        controller.refresh()
    }

    @objc private func togglePinApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model.togglePin(id)
        controller.refresh()
    }

    @objc private func toggleAutoLaunch() {
        setAutoLaunch(SMAppService.mainApp.status != .enabled)
    }

    @objc private func toggleCollapseMode() {
        controller.setCollapsed(!controller.isCollapsed)
    }

    // MARK: - 事件监听

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        // 启动/退出 → 内容可能变化 → 签名比对后按需重建
        let contentNames: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in contentNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.controller.refresh()
            })
        }
        // 切换前台 App → 内容不变，只做幂等重挂（不闪）
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.controller.rePresent()
        })
        // 解锁屏幕后恢复常驻
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.controller.present()
        }
    }
}
