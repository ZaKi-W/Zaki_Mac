# 片刻 / Moment

一款使用 SwiftUI、AppKit 和 WebKit 构建的原生 macOS 提醒与轻量浏览应用。

## 功能

- 单次与循环提醒，支持时、分、秒组合
- 原生系统通知与睡眠恢复协调
- 1–59 秒应用内循环提醒；60 秒以上系统级循环通知
- 基于 `WKWebView` 的多标签浏览器
- 地址搜索、快捷站点、书签、下载和共享网页会话
- 知乎阅读清理与网页暗色适配
- 跟随系统、浅色和深色三种外观
- 中文与英文界面
- 可配置的全局显示/隐藏快捷键
- 首次启动自动迁移旧 Electron 版提醒、书签和设置

## 技术栈

- Swift 6
- SwiftUI
- AppKit
- WebKit / WKWebView
- UserNotifications
- Carbon Hot Key API
- XCTest

最低支持 macOS 14。应用仅面向 macOS，不包含 Electron、Chromium、Node.js
或 Windows 运行时。

## 开发

使用 Xcode 26 或更高版本打开：

```text
Moment.xcodeproj
```

命令行构建：

```bash
xcodebuild \
  -project Moment.xcodeproj \
  -scheme Moment \
  -configuration Debug \
  -destination 'platform=macOS'
```

运行轻量测试：

```bash
xcodebuild test \
  -project Moment.xcodeproj \
  -scheme Moment \
  -configuration Debug \
  -destination 'platform=macOS'
```

首次使用命令行工具时，如果 Xcode 提示缺少组件，可运行：

```bash
xcodebuild -runFirstLaunch
```

## 数据

原生数据写入：

```text
~/Library/Application Support/Moment/app-state.json
```

首次启动且原生数据为空时，应用会读取：

```text
~/Library/Application Support/personal-assistant/assistant-v2/state.json
```

迁移包括提醒、书签、语言、外观、浏览器暗色设置和全局快捷键。旧文件不会被
修改或删除；Chromium Cookie、缓存和网页登录状态不会迁移。

## 签名与发布

工程默认 Bundle ID 为 `com.personal-assistant.moment`，并启用 Hardened Runtime。
在 Xcode 的 Signing & Capabilities 中选择自己的 Developer Team 后即可 Archive。
