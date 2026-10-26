import AppKit

/// Touch Bar 控制器（v1.8 系统优先架构）：
/// - 系统触控栏（App Controls + 控制条）永远是最高层，本应用绝不常驻占用
/// - Dock 常驻为控制条里的一个图标（系统托盘成员，与音量/亮度同区）
/// - 点击图标 → 模态展开 Dock 行（placement 0，与控制条共存）；点 › 或再点图标 → 收起还给系统
final class DockTouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = DockTouchBarController()

    private let model = AppModel()
    private var touchBar: NSTouchBar!
    /// 上次渲染的 App 列表签名；列表没变就不动内容，避免触控栏闪烁
    private var lastSignature: [String] = []

    private static let rowItemID = NSTouchBarItem.Identifier("com.touchbardash.dock.row")
    private static let trayItemID = "com.touchbardash.dock.tray"

    private let rowItem = NSCustomTouchBarItem(
        identifier: NSTouchBarItem.Identifier("com.touchbardash.dock.row")
    )
    private let rowStack = NSStackView()
    private let trayItem = NSCustomTouchBarItem(
        identifier: NSTouchBarItem.Identifier("com.touchbardash.dock.tray")
    )

    /// 模态 Dock 行是否已展开（收起态 = 触控栏只有托盘图标，系统内容全量可见）。
    private(set) var isPresented = false

    private override init() {
        super.init()
        rowStack.orientation = .horizontal
        rowStack.spacing = 4
        rowStack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 4)
        rowItem.view = rowStack

        touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.rowItemID]

        // 托盘图标：Dock 的常驻入口（控制条成员）
        trayItem.view = makeTrayIcon()
        guard TouchBarPrivateAPI.addSystemTrayItem(trayItem) else { return }
        TouchBarPrivateAPI.setControlStripPresence(
            forIdentifier: Self.trayItemID, visible: true
        )
    }

    /// 模态展开 Dock 行。
    func present() {
        guard TouchBarPrivateAPI.hasTouchBarSupport() else { return }
        buildRow()
        TouchBarPrivateAPI.hideCloseBoxWhenFrontMost()
        TouchBarPrivateAPI.presentSystemModal(touchBar, placement: 0)
        isPresented = true
    }

    /// 收起 Dock，触控栏完全还给系统。
    func dismiss() {
        guard isPresented else { return }
        TouchBarPrivateAPI.dismissSystemModal(touchBar)
        isPresented = false
    }

    func toggle() {
        isPresented ? dismiss() : present()
    }

    /// 应用启动/退出/固定变化后调用：列表变了且 Dock 展开时才原地重建行内容。
    func refresh() {
        guard isPresented else { return }
        let signature = model.dockApps().map(\.bundleID)
        guard signature != lastSignature else { return }
        lastSignature = signature
        buildRow()
    }

    /// 应用切换时幂等重挂（Dock 展开中才需要；同实例重挂不闪、不动控制条）。
    func rePresent() {
        guard isPresented else { return }
        present()
    }

    /// 托盘图标 presence 守护：系统偶尔会重置控制条，定时把我们的图标拉回来。
    func ensureTrayPresence() {
        TouchBarPrivateAPI.setControlStripPresence(
            forIdentifier: Self.trayItemID, visible: true
        )
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        rowItem
    }

    // MARK: - 内容构建

    private func makeTrayIcon() -> NSView {
        let icon = SimpleIconButton(
            symbol: "square.grid.2x2.fill",
            target: self, action: #selector(trayTapped), width: 30
        )
        icon.toolTip = "TouchBarDock"
        let stack = NSStackView(views: [icon])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        return stack
    }

    /// 模态 Dock 行：[esc][应用图标…][›收起]，原地重建不换 bar。
    private func buildRow() {
        for view in rowStack.arrangedSubviews {
            view.removeFromSuperview()
        }
        rowStack.addView(EscButton(), in: .leading)
        for app in model.dockApps() {
            let button = AppIconButton(app: app, target: self, action: #selector(appTapped(_:)))
            button.isEnabled = true
            rowStack.addView(button, in: .leading)
        }
        let chevron = SimpleIconButton(
            symbol: "chevron.compact.left",
            target: self, action: #selector(chevronTapped), width: 24
        )
        chevron.toolTip = "收起 Dock"
        rowStack.addView(chevron, in: .leading)
    }

    @objc private func appTapped(_ sender: AppIconButton) {
        model.handleTap(sender.bundleID)
    }

    @objc private func chevronTapped() {
        dismiss()
    }

    @objc private func trayTapped() {
        toggle()
    }
}

extension TouchBarPrivateAPI {
    /// NSTouchBar 私有类方法是否仍然存在（缺失则静默不启用）。
    static func hasTouchBarSupport() -> Bool {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        return class_getClassMethod(NSTouchBar.self, sel) != nil
    }
}
