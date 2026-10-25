import AppKit
import ApplicationServices

/// 通过辅助功能 API 操作窗口：
/// - 设置 AXMinimized 走系统原生最小化路径 → 触发 Dock 的神奇/缩放动画
/// - 恢复窗口时把已最小化的窗口逐个还原，再激活 App
/// 未授权辅助功能时返回 false，调用方退回 ⌘H（hide/unhide）兜底。
enum AXWindowHelper {

    private static var hasPromptedForTrust = false
    private static let logPath = NSHomeDirectory() + "/Library/Logs/TouchBarDock.log"

    /// 诊断日志：真机上排障用。
    private static func log(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(stamp)] \(message)\n"
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        }
    }

    // MARK: - 对外能力

    /// 最小化 App 的所有可见窗口（走系统原生动画路径）。返回是否有窗口被成功最小化。
    static func minimizeAll(_ app: NSRunningApplication) -> Bool {
        guard isTrusted(promptIfNeeded: true) else {
            log("minimizeAll \(app.localizedName ?? "?"): 未授权辅助功能")
            return false
        }
        var changed = false
        forEachWindow(of: app) { window in
            if !isMinimized(window), minimizeWindow(window, app: app) {
                changed = true
            }
        }
        if !changed { log("minimizeAll \(app.localizedName ?? "?"): 无窗口成功最小化") }
        return changed
    }

    /// 还原 App 所有已最小化的窗口（逐个触发恢复）。
    static func restoreAll(_ app: NSRunningApplication) {
        guard isTrusted(promptIfNeeded: false) else {
            log("restoreAll \(app.localizedName ?? "?"): 未授权辅助功能")
            return
        }
        forEachWindow(of: app) { window in
            if isMinimized(window) {
                let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse as CFTypeRef)
                if result != .success {
                    log("restore \(app.localizedName ?? "?"): set AXMinimized=false 失败 code=\(result.rawValue)")
                }
            }
        }
    }

    /// App 是否存在已最小化的窗口（决定点击是"最小化"还是"恢复"）。
    static func hasAnyMinimizedWindow(_ app: NSRunningApplication) -> Bool {
        guard isTrusted(promptIfNeeded: false) else { return false }
        var found = false
        forEachWindow(of: app) { window in
            if isMinimized(window) { found = true }
        }
        return found
    }

    // MARK: - Private

    /// 按下窗口的最小化按钮 —— 与真实鼠标点击同路径，触发系统神奇/缩放动画。
    /// 按钮缺失（如部分自绘窗口）时退回直接设置 AXMinimized 属性（无动画但有效）。
    private static func minimizeWindow(_ window: AXUIElement, app: NSRunningApplication) -> Bool {
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizeButtonAttribute as CFString, &button) == .success,
           let button = button {
            let axButton = button as! AXUIElement
            if AXUIElementPerformAction(axButton, kAXPressAction as CFString) == .success {
                return true
            }
            log("minimize \(app.localizedName ?? "?"): AXPress 失败，退回属性设置")
        } else {
            log("minimize \(app.localizedName ?? "?"): 无最小化按钮，退回属性设置")
        }
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue as CFTypeRef) == .success
    }

    private static func isTrusted(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if promptIfNeeded && !hasPromptedForTrust {
            hasPromptedForTrust = true
            log("辅助功能未授权，弹出系统引导")
            // 弹出系统引导：设置 → 隐私与安全性 → 辅助功能
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    private static func forEachWindow(of app: NSRunningApplication, _ body: (AXUIElement) -> Void) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? NSArray else { return }
        for case let window as AXUIElement in list {
            body(window)
        }
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
