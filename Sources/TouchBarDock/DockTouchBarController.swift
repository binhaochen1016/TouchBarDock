import AppKit

/// Touch Bar 控制器：构建 Dock 栏并以系统模态方式常驻显示。
final class DockTouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = DockTouchBarController()

    private let model = AppModel()
    private var touchBar: NSTouchBar!
    private var isPresented = false
    /// 上次渲染的 App 列表签名；列表没变就不重建，避免触控栏闪烁
    private var lastSignature: [String] = []

    private let escItemID = NSTouchBarItem.Identifier("com.touchbardash.dock.esc")
    private let dockItemID = NSTouchBarItem.Identifier("com.touchbardash.dock.apps")

    private override init() {
        super.init()
        touchBar = makeTouchBar()
    }

    /// NSTouchBar 会缓存已创建的条目；要动态增删图标必须整条重建。
    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [escItemID, dockItemID]
        return bar
    }

    /// 显示 Dock。保留系统 Control Strip（音量/亮度等），Dock 占用其余区域，两者共存。
    func present() {
        guard TouchBarPrivateAPI.hasTouchBarSupport() else { return }
        TouchBarPrivateAPI.hideCloseBoxWhenFrontMost()
        TouchBarPrivateAPI.presentSystemModal(touchBar)
        isPresented = true
    }

    /// 恢复系统默认 Touch Bar。
    func dismiss() {
        guard isPresented else { return }
        TouchBarPrivateAPI.dismissSystemModal(touchBar)
        TouchBarPrivateAPI.setControlStripPresence(
            forIdentifier: "com.apple.controlstrip:mini", visible: true
        )
        isPresented = false
    }

    func toggle() {
        isPresented ? dismiss() : present()
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
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 10)
        return stack
    }

    @objc private func appTapped(_ sender: AppIconButton) {
        model.handleTap(sender.bundleID)
    }
}

extension TouchBarPrivateAPI {
    /// NSTouchBar 私有类方法是否仍然存在（缺失则静默不启用）。
    static func hasTouchBarSupport() -> Bool {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        return class_getClassMethod(NSTouchBar.self, sel) != nil
    }
}
