import AppKit

/// App 图标按钮：运行中的 App 底部显示小圆点指示（同 Dock 行为）。
final class AppIconButton: NSButton {
    let bundleID: String

    init(app: DockApp, target: AnyObject?, action: Selector) {
        self.bundleID = app.bundleID
        super.init(frame: .zero)
        self.image = app.icon
        self.imagePosition = .imageOnly
        self.imageScaling = .scaleProportionallyDown
        self.image?.size = NSSize(width: 22, height: 22)
        self.target = target
        self.action = action
        self.isBordered = true
        self.toolTip = app.name
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 40).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isEnabled else { return }
        // 运行状态小圆点
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 2, y: 1, width: 4, height: 4)).fill()
    }
}

/// Esc 按钮：系统模态栏会盖住虚拟 Esc 键，这里补一个（发送真实 Esc 键事件）。
final class EscButton: NSButton {
    init() {
        super.init(frame: .zero)
        title = "esc"
        font = NSFont.systemFont(ofSize: 14, weight: .medium)
        bezelColor = NSColor(white: 0.12, alpha: 1)
        target = self
        action = #selector(sendEscape)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 52).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func sendEscape() {
        for keyDown in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: keyDown)?
                .post(tap: .cghidEventTap)
        }
    }
}
