import AppKit

/// 一个 Dock 条目：可来自运行中的应用，也可以是已固定但未运行的 App。
struct DockApp {
    let bundleID: String
    let name: String
    let icon: NSImage
    let isRunning: Bool
}

/// 本机已安装 App（用于自定义 Dock 的选择列表）。
struct InstalledApp {
    let bundleID: String
    let name: String
    let icon: NSImage
}

/// Dock 数据源：固定 App（置前）+ 运行中的常规 App。
final class AppModel {

    private let pinnedKey = "TouchBarDock.pinnedBundleIDs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pinnedBundleIDs: [String] {
        get { defaults.stringArray(forKey: pinnedKey) ?? [] }
        set { defaults.set(newValue, forKey: pinnedKey) }
    }

    var frontmostRegularBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func togglePin(_ bundleID: String) {
        var ids = pinnedBundleIDs
        if let index = ids.firstIndex(of: bundleID) {
            ids.remove(at: index)
        } else {
            ids.append(bundleID)
        }
        pinnedBundleIDs = ids
    }

    func isPinned(_ bundleID: String) -> Bool {
        pinnedBundleIDs.contains(bundleID)
    }

    /// 当前 Dock 内容：固定 App 在前（无论是否运行），其余运行中 App 按名称排序在后。
    func dockApps() -> [DockApp] {
        let running = runningAppsByBundleID()
        var result: [DockApp] = []
        var seen = Set<String>()

        for id in pinnedBundleIDs {
            seen.insert(id)
            if let app = running[id] {
                result.append(dockApp(from: app))
            } else if let url = appURL(forBundleID: id) {
                result.append(DockApp(
                    bundleID: id,
                    name: displayName(url: url),
                    icon: NSWorkspace.shared.icon(forFile: url.path),
                    isRunning: false
                ))
            }
        }

        let others = running.values
            .filter { !seen.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        result.append(contentsOf: others.map(dockApp(from:)))
        return result
    }

    /// 点击图标的状态机：
    /// 未运行 → 启动
    /// 前台且无已最小化窗口 → 带系统动画最小化全部窗口（神奇效果），AX 不可用退回 ⌘H
    /// 否则（后台/隐藏/有最小化窗口）→ 还原最小化窗口 + 取消隐藏 + 激活
    /// （修复 macOS 14+ activate() 不唤回隐藏 App 的问题，如微信）
    func handleTap(_ bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
        }) else {
            launch(bundleID)
            return
        }

        let isFrontmost = app.isActive && !app.isHidden
        if isFrontmost && !AXWindowHelper.hasAnyMinimizedWindow(app) {
            if !AXWindowHelper.minimizeAll(app) {
                app.hide()
            }
        } else {
            if app.isHidden { app.unhide() }
            AXWindowHelper.restoreAll(app)
            activate(bundleID)
        }
    }

    /// 激活运行中的 App；未运行则启动。
    func activate(_ bundleID: String) {
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular
        }) {
            if #available(macOS 14.0, *) {
                NSWorkspace.shared.runningApplications
                    .first { $0.bundleIdentifier == bundleID }?
                    .activate()
            } else {
                NSWorkspace.shared.runningApplications
                    .first { $0.bundleIdentifier == bundleID }?
                    .activate(options: [.activateAllWindows])
            }
        } else {
            launch(bundleID)
        }
    }

    /// 本机已安装 App 列表（/Applications 与 /System/Applications）。
    func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications"]
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                guard let bundle = Bundle(url: url),
                      let id = bundle.bundleIdentifier,
                      !seen.contains(id)
                else { continue }
                seen.insert(id)
                result.append(InstalledApp(
                    bundleID: id,
                    name: displayName(url: url),
                    icon: NSWorkspace.shared.icon(forFile: url.path)
                ))
            }
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Private

    /// 按 bundleID 去重后的运行中常规 App（排除自身等辅助进程）。
    private func runningAppsByBundleID() -> [String: NSRunningApplication] {
        var map: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let id = app.bundleIdentifier
            else { continue }
            map[id] = app
        }
        return map
    }

    private func dockApp(from app: NSRunningApplication) -> DockApp {
        let id = app.bundleIdentifier ?? UUID().uuidString
        return DockApp(
            bundleID: id,
            name: app.localizedName ?? id,
            icon: app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle),
            isRunning: true
        )
    }

    private func launch(_ bundleID: String) {
        guard let url = appURL(forBundleID: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func appURL(forBundleID id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    private func displayName(url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
