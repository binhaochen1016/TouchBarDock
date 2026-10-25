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
    /// placement 0 = 常驻功能行，跨 App 切换、跨 Space 保持显示。
    static func presentSystemModal(_ bar: NSTouchBar) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString?) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(NSTouchBar.self, sel, bar, 0, nil)
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
}
