import AppKit

/// Touch Bar 控制器：单条 bar + 单容器 item。
/// 收起/展开、应用增减都只是原地切换容器内容，bar 实例全程唯一、
/// 只在启动/解锁/兜底时幂等重挂——杜绝「换 bar / 叠加 present」把系统控制条顶掉的问题。
final class DockTouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = DockTouchBarController()

    private let model = AppModel()
    private var touchBar: NSTouchBar!
    private var isPresented = false
    /// 上次渲染的 App 列表签名；列表没变就不动内容，避免触控栏闪烁
    private var lastSignature: [String] = []
    private static let collapsedKey = "TouchBarDock.collapsed"

    private static let rowItemID = NSTouchBarItem.Identifier("com.touchbardash.dock.row")
    private let rowItem = NSCustomTouchBarItem(
        identifier: NSTouchBarItem.Identifier("com.touchbardash.dock.row")
    )
    private let rowStack = NSStackView()

    /// 是否处于「收起为图标」模式（菜单栏可切换，重启后保持）。
    private(set) var isCollapsed: Bool

    private override init() {
        isCollapsed = UserDefaults.standard.bool(forKey: Self.collapsedKey)
        super.init()
        rowStack.orientation = .horizontal
        rowStack.spacing = 4
        rowStack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 4)
        rowItem.view = rowStack

        touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.rowItemID]
        applyMode()
    }

    /// 显示 Dock。placement 0 与系统控制条（音量/亮度）共享触控条；同一实例幂等重挂。
    func present() {
        guard TouchBarPrivateAPI.hasTouchBarSupport() else { return }
        TouchBarPrivateAPI.hideCloseBoxWhenFrontMost()
        TouchBarPrivateAPI.presentSystemModal(touchBar, placement: 0)
        isPresented = true
    }

    /// 恢复系统默认 Touch Bar（退出时调用）。
    func dismiss() {
        guard isPresented else { return }
        TouchBarPrivateAPI.dismissSystemModal(touchBar)
        TouchBarPrivateAPI.restoreControlStrip()
        isPresented = false
    }

    func toggle() {
        isPresented ? dismiss() : present()
    }

    /// 切换「收起为图标 / 展开为程序坞」：只原地换容器内容，bar 与控制条都不动。
    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: Self.collapsedKey)
        applyMode()
    }

    /// 应用启动/退出/固定变化后调用：列表真的变了才原地重建内容（不换 bar、不重挂）。
    func refresh() {
        guard isPresented else { return }
        let signature = model.dockApps().map(\.bundleID)
        guard signature != lastSignature else { return }
        lastSignature = signature
        applyMode()
    }

    /// 应用切换/兜底重挂：同一条 bar 幂等重挂，不闪、不动控制条。
    func rePresent() {
        guard isPresented else { return }
        present()
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        rowItem
    }

    // MARK: - 内容构建（原地替换，不换 bar）

    private func applyMode() {
        for view in rowStack.arrangedSubviews {
            view.removeFromSuperview()
        }
        if isCollapsed {
            let icon = SimpleIconButton(
                symbol: "square.grid.2x2.fill",
                target: self, action: #selector(toggleButtonTapped), width: 44
            )
            icon.toolTip = "展开 TouchBarDock"
            rowStack.addView(icon, in: .leading)
        } else {
            rowStack.addView(EscButton(), in: .leading)
            for app in model.dockApps() {
                let button = AppIconButton(app: app, target: self, action: #selector(appTapped(_:)))
                button.isEnabled = true
                rowStack.addView(button, in: .leading)
            }
            let chevron = SimpleIconButton(
                symbol: "chevron.compact.right",
                target: self, action: #selector(toggleButtonTapped), width: 24
            )
            chevron.toolTip = "收起为一个图标"
            rowStack.addView(chevron, in: .leading)
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
