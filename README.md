# TouchBarDock

把 macOS Touch Bar 变成一条「程序坞」：常驻显示运行中/固定的 App 图标，点击切换前台，再点一下最小化（支持系统神奇动画）。

Make your MacBook's Touch Bar work like a Dock: always-on app icons, tap to activate, tap again to minimize (with the native genie animation).

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## ✨ 功能

- **常驻 Dock** — 使用系统模态 Touch Bar API，跨 App 切换、跨 Space 始终显示
- **与系统共存** — 保留系统 Control Strip（音量/亮度/焦距等），Dock 占用其余区域
- **登录自启动** — 首次运行自动注册登录项（SMAppService），菜单栏可开关
- **运行中 App 实时上下栏** — 启动立即出现、退出立即消失（含运行状态小圆点）
- **固定常用 App** — 菜单栏「自定义 Dock 应用…」勾选固定，未运行也可点击启动
- **Dock 式点击行为** — 前台 → 神奇动画最小化；后台/隐藏 → 还原窗口并激活；未运行 → 启动
- **Esc 补偿按钮** — 系统模态栏会盖住虚拟 Esc 键，左侧提供真实的 Esc
- **优雅降级** — 私有 API 缺失或辅助功能未授权时自动退回 ⌘H 语义，不会崩溃

## 🚀 安装

### 方式一：使用构建产物

```bash
git clone https://github.com/binhaochen1016/TouchBarDock.git
cd TouchBarDock
./Scripts/make_app.sh
```

### 方式二：手动构建

```bash
swift build -c release --disable-sandbox
mkdir -p build/TouchBarDock.app/Contents/MacOS
cp .build/release/TouchBarDock build/TouchBarDock.app/Contents/MacOS/
cp Scripts/Info.plist build/TouchBarDock.app/Contents/Info.plist
codesign --force --sign - build/TouchBarDock.app
cp -R build/TouchBarDock.app /Applications/
xattr -dr com.apple.quarantine /Applications/TouchBarDock.app
```

> ⚠️ **务必安装到 /Applications 并去掉隔离标记后运行**。直接从下载目录双击运行会触发 App Translocation（临时转义），导致辅助功能授权始终不生效。

### 首次授权（必需）

1. 打开「系统设置 → 隐私与安全性 → 辅助功能」
2. 勾选 TouchBarDock
3. （可选）勾选后可使用带动画的最小化；未授权时点击退回 ⌘H 行为

> ad-hoc 签名下**每次重新编译都需要重新授权**。想一劳永逸：钥匙串访问 → 证书助理 → 创建自签名证书，然后 `SIGN_IDENTITY="证书名" ./Scripts/make_app.sh`

## 🖱️ 使用

| 操作 | 效果 |
|---|---|
| 点击图标 | 前台 App → 神奇动画最小化；后台 App → 还原并激活；未运行 → 启动 |
| 菜单栏图标 → 自定义 Dock 应用… | 勾选固定 / 取消固定任意已安装 App |
| 菜单栏图标 → 📌 固定当前前台 App | 快速固定正在使用的 App |

## 🛠️ 技术实现

- Swift + AppKit，SwiftPM 构建，无第三方依赖
- **常驻显示**：私有 API `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]`（Pock / MTMR 同款路线），`DFRFoundation` 隐藏系统 Control Strip
- **动态刷新**：`NSTouchBar` 会缓存条目，应用列表变化时整条重建；切换前台只做幂等重挂（不闪烁）
- **神奇动画最小化**：辅助功能 API `AXPress` 按下窗口最小化按钮（与真实点击同路径），按钮缺失时退回直接设置 `AXMinimized`，最后退回 `hide()`
- **诊断日志**：`~/Library/Logs/TouchBarDock.log`

## ⚠️ 已知限制

- 使用私有 API，**无法上架 Mac App Store**，macOS 大版本更新后可能需要适配
- 触控栏条目过多时（约 20+）会截断，暂无横向滚动
- 微信等自绘窗口 App 若无标准最小化按钮，动画退化为无动画最小化（详见日志）

## 📄 License

MIT
