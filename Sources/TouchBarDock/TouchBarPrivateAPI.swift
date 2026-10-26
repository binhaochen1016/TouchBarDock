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

    /// 以系统模态方式常驻显示 Touch Bar。
    /// placement 1 = 系统控制条（音量/亮度）左侧的位置，与控制条共存（Pock/MTMR 标准值）；
    /// placement 0 会顶掉控制条区域，导致音量/亮度消失。
    static func presentSystemModal(_ bar: NSTouchBar, placement: Int = 1) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString?) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(NSTouchBar.self, sel, bar, placement, nil)
    }

    static func dismissSystemModal(_ bar: NSTouchBar) {
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
}
