# 提醒

一个以 macOS 为优先平台的个人效率工作台，提供可靠的间隔提醒和内置多标签浏览器。

## 功能

- 单次与循环提醒，支持时、分、秒组合
- Electron 主进程调度与原生系统通知
- 系统睡眠或应用重启后的单次补发
- 基于 `WebContentsView` 的多标签浏览器
- 地址搜索、快捷站点、书签和持久化网页会话
- 知乎阅读清理与网页暗色适配
- 跟随系统、固定浅色和固定深色三种外观
- 中文与英文界面
- 可配置的全局显示/隐藏快捷键

## 技术栈

- Electron 43
- React 19
- TypeScript
- electron-vite 5 / Vite 7
- Tailwind CSS 4
- Zod
- Vitest
- electron-builder

应用采用单一 npm 工程。Electron 主进程负责窗口、提醒、浏览器标签、存储和快捷键；preload 仅暴露经过约束的类型安全接口；React renderer 不直接访问 Node 或 `ipcRenderer`。

## 环境要求

- Node.js 22.12 或更高版本
- npm 10 或更高版本
- macOS 11 或更高版本；Windows 保留构建支持

## 开发

```bash
npm install
npm run electron:install
npm run dev
```

Electron 43 起运行时不再通过 `postinstall` 自动下载。`dev` 与 `start` 也会自动
检查并安装运行时；单独执行上面的命令便于提前确认下载完成。

常用检查：

```bash
npm run typecheck
npm run lint
npm test
npm run build
```

## 打包

```bash
npm run dist:mac
npm run dist:win
```

构建产物写入 `out/`，安装包写入 `release/`。

## 目录

```text
src/
├── main/       Electron 入口、IPC 和主进程服务
├── preload/    类型安全的 contextBridge
├── renderer/   React 界面
└── shared/     IPC 契约、领域类型和纯函数
```

新版数据写入 Electron `userData/assistant-v2/state.json`，浏览器使用 `persist:browser-v2` 会话分区。旧版数据不会迁移，也不会被主动删除。
