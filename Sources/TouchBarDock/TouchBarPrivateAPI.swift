import AppKit

/// Touch Bar 私有 API 封装（Pock / MTMR 同款路线）。
/// 所有符号运行时动态解析：缺失时能力静默降级，绝不崩溃。
/// 代价：无法上架 App Store，系统大版本更新可能失效。
enum TouchBarPrivateAPI {

    private static var dfrHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)
    }()

    private static func dfrFunction(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dfrHandle else { return nil }
        return dlsym(handle, name)
    }

    /// 以系统模态方式常驻显示 Touch Bar（MTMR 同款用法）。
    /// - placement 0：与系统 mini 控制条共享触控条（控制条保留在右侧）
    /// - trayItemIdentifier：模态栏锚定的托盘图标 id（关键！系统靠它管理
    ///   用户展开控制条时的层级切换，传 nil 会导致系统状态错乱）
    static func presentSystemModal(_ bar: NSTouchBar, placement: Int = 0, trayItemIdentifier: String? = nil) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString?) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(NSTouchBar.self, sel, bar, placement, trayItemIdentifier as NSString?)
    }

    /// 最小化模态栏（收回到托盘图标，保持系统会话）——收起的正确姿势。
    /// 不要用 dismissSystemModal 拆除：那会搅乱控制条状态（MTMR 用 minimize）。
    static func minimizeSystemModal(_ bar: NSTouchBar) {
        let sel = NSSelectorFromString("minimizeSystemModalTouchBar:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(NSTouchBar.self, sel, bar)
    }

    static func dismissSystemModal(_ bar: NSTouchBar?) {
        guard let bar else { return }
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(NSTouchBar.self, sel, bar)
    }

    /// 前台时不显示系统的 "×" 关闭框，避免 Dock 被意外关掉。
    static func hideCloseBoxWhenFrontMost() {
        guard let p = dfrFunction("DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        typealias Fn = @convention(c) (Bool) -> Void
        unsafeBitCast(p, to: Fn.self)(false)
    }

    /// 把条目加入系统托盘区（控制条成员，与音量/亮度同区）。私有类方法，缺失返回 false。
    static func addSystemTrayItem(_ item: NSTouchBarItem) -> Bool {
        let sel = NSSelectorFromString("addSystemTrayItem:")
        guard let method = class_getClassMethod(NSTouchBarItem.self, sel) else { return false }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
        unsafeBitCast(method_getImplementation(method), to: Fn.self)(NSTouchBarItem.self, sel, item)
        return true
    }

    /// 隐藏/恢复系统 Control Strip（触控栏右侧的亮度音量区）。
    static func setControlStripPresence(forIdentifier identifier: String, visible: Bool) {
        guard let p = dfrFunction("DFRElementSetControlStripPresenceForIdentifier") else { return }
        typealias Fn = @convention(c) (NSString, Bool) -> Void
        unsafeBitCast(p, to: Fn.self)(identifier as NSString, visible)
    }

    /// 显式恢复系统 Control Strip（修复旧版本隐藏后的状态残留）。
    static func restoreControlStrip() {
        setControlStripPresence(forIdentifier: "com.apple.controlstrip:mini", visible: true)
    }

    /// 读取系统控制条当前可见性（诊断用）。nil = 符号缺失。
    static func controlStripPresence(forIdentifier identifier: String) -> Bool? {
        guard let p = dfrFunction("DFRElementGetControlStripPresenceForIdentifier") else { return nil }
        typealias Fn = @convention(c) (NSString) -> Bool
        return unsafeBitCast(p, to: Fn.self)(identifier as NSString)
    }
}
