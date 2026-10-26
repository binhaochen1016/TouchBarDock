import AppKit

/// Touch Bar 控制器：构建 Dock 栏并以系统模态方式常驻显示。
/// 支持两种模式：
/// - 展开（默认）：Esc 补偿 + 应用图标行 + 收起按钮，与系统控制条（音量/亮度）共存
/// - 收起：触控栏只留一个图标，点它即展开完整 Dock
final class DockTouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = DockTouchBarController()

    private let model = AppModel()
    private var touchBar: NSTouchBar!
    private var isPresented = false
    /// 上次渲染的 App 列表签名；列表没变就不重建，避免触控栏闪烁
    private var lastSignature: [String] = []
    private static let collapsedKey = "TouchBarDock.collapsed"

    private let escItemID = NSTouchBarItem.Identifier("com.touchbardash.dock.esc")
    private let dockItemID = NSTouchBarItem.Identifier("com.touchbardash.dock.apps")
    private let toggleItemID = NSTouchBarItem.Identifier("com.touchbardash.dock.toggle")

    /// 是否处于「收起为图标」模式（菜单栏可切换，重启后保持）。
    private(set) var isCollapsed: Bool

    private override init() {
        isCollapsed = UserDefaults.standard.bool(forKey: Self.collapsedKey)
        super.init()
        touchBar = makeTouchBar()
    }

    /// NSTouchBar 会缓存已创建的条目；要动态增删图标必须整条重建。
    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = isCollapsed ? [toggleItemID] : [escItemID, dockItemID, toggleItemID]
        return bar
    }

    /// 显示 Dock（按当前模式）。placement 0 与系统控制条共存，且显式恢复控制条可见（修复历史残留）。
    func present() {
        guard TouchBarPrivateAPI.hasTouchBarSupport() else { return }
        TouchBarPrivateAPI.hideCloseBoxWhenFrontMost()
        let before = TouchBarPrivateAPI.controlStripPresence(forIdentifier: "com.apple.controlstrip:mini")
        TouchBarPrivateAPI.presentSystemModal(touchBar, placement: 0)
        TouchBarPrivateAPI.restoreControlStrip()
        let after = TouchBarPrivateAPI.controlStripPresence(forIdentifier: "com.apple.controlstrip:mini")
        isPresented = true
        // 只在前几次记录诊断，避免日志刷屏
        if presentLogCount < 5 {
            presentLogCount += 1
            AXWindowHelper.log("present: placement=0, strip presence before=\(before.map(String.init) ?? "符号缺失") after=\(after.map(String.init) ?? "符号缺失")")
        }
    }

    private var presentLogCount = 0

    /// 恢复系统默认 Touch Bar。
    func dismiss() {
        guard isPresented else { return }
        TouchBarPrivateAPI.dismissSystemModal(touchBar)
        TouchBarPrivateAPI.restoreControlStrip()
        isPresented = false
    }

    func toggle() {
        isPresented ? dismiss() : present()
    }

    /// 切换「收起为图标 / 展开为程序坞」模式。
    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: Self.collapsedKey)
        touchBar = makeTouchBar()
        if isPresented { present() }
    }

    /// 应用启动/退出/固定变化后调用：列表真的变了才重建（防闪烁），否则只重挂。
    func refresh() {
        guard isPresented else { return }
        let signature = model.dockApps().map(\.bundleID)
        guard signature != lastSignature else { return }
        lastSignature = signature
        touchBar = makeTouchBar()
        present()
    }

    /// 应用切换/兜底重挂：不重建，同一条 bar 幂等重挂不会闪。
    func rePresent() {
        guard isPresented else { return }
        present()
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case escItemID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = EscButton()
            return item
        case dockItemID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = makeAppsView()
            return item
        case toggleItemID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = makeToggleView()
            return item
        default:
            return nil
        }
    }

    // MARK: - Private

    private func makeAppsView() -> NSView {
        let apps = model.dockApps()
        let buttons = apps.map { app -> AppIconButton in
            let button = AppIconButton(app: app, target: self, action: #selector(appTapped(_:)))
            button.isEnabled = true
            return button
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 2)
        return stack
    }

    /// 展开态：右侧收起按钮（挤进图标区尾部）；收起态：单独一个 Dock 图标。
    private func makeToggleView() -> NSView {
        if isCollapsed {
            let icon = SimpleIconButton(
                symbol: "square.grid.2x2.fill",
                target: self, action: #selector(toggleButtonTapped), width: 44
            )
            icon.toolTip = "展开 TouchBarDock"
            let stack = NSStackView(views: [icon])
            stack.orientation = .horizontal
            stack.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
            return stack
        } else {
            let chevron = SimpleIconButton(
                symbol: "chevron.compact.right",
                target: self, action: #selector(toggleButtonTapped), width: 24
            )
            chevron.toolTip = "收起为一个图标"
            return chevron
        }
    }

    @objc private func appTapped(_ sender: AppIconButton) {
        model.handleTap(sender.bundleID)
    }

    @objc private func toggleButtonTapped() {
        setCollapsed(!isCollapsed)
    }
}

extension TouchBarPrivateAPI {
    /// NSTouchBar 私有类方法是否仍然存在（缺失则静默不启用）。
    static func hasTouchBarSupport() -> Bool {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        return class_getClassMethod(NSTouchBar.self, sel) != nil
    }
}
