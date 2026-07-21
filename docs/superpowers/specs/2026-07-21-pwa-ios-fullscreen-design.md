# 提词器 PWA 化（iPhone 全屏 + 方便打开）设计文档

- **日期：** 2026-07-21
- **状态：** 已与用户确认，待编写实现计划
- **前置项目：** 手机提词器（见 [`2026-06-16-mobile-teleprompter-design.md`](2026-06-16-mobile-teleprompter-design.md)）

## 1. 背景

当前提词器交付物是单个 `teleprompter.html`，用户通过微信发送到 iPhone 打开。存在两个体验问题：

1. **不方便打开**：iPhone 上打开本地 `.html` 要绕一圈（"文件"App → 长按 → Safari 打开），且微信内置浏览器限制多。
2. **不能全屏**：[Teleprompter.tsx:281](../../../src/components/Teleprompter.tsx#L281) 的全屏按钮用标准 Fullscreen API（`requestFullscreen`），iPhone Safari 对普通网页禁用此 API（只允许 `<video>` 全屏），点了无反应。

## 2. 问题根因

| 问题 | 根因 |
|------|------|
| 不能全屏 | (a) iPhone Safari 禁止普通 DOM `requestFullscreen()`；(b) iOS 唯一的网页全屏路径是 PWA「添加到主屏幕」，但 [index.html](../../../index.html) 缺 `apple-mobile-web-app-capable` 等 meta 与 manifest，加主屏后仍带 Safari 外壳 |
| 不方便打开 | (a) 微信内置浏览器无「添加到主屏幕」入口、PWA 能力受限；(b) 本地 `file://` 下 manifest / Service Worker / Wake Lock 基本失效 |
| 跨来源数据隔离 | `localStorage` 按来源隔离，从老的 `file://` 版或换设备时老稿件读不到（本次不处理，靠现有「导入 .txt」兜底） |

## 3. 需求确认

| 维度 | 结论 |
|------|------|
| 大方向 | 方案 A：完整 PWA + 离线缓存 + 自动部署 |
| 托管 | GitHub Pages（仓库 `jasinghuang/Prompter`，项目站点 `https://jasinghuang.github.io/Prompter/`） |
| 全屏机制 | PWA「添加到主屏幕」+ `apple-mobile-web-app-status-bar-style=black-translucent` + manifest `display:fullscreen` |
| 离线 | 手写 Service Worker，NetworkFirst（导航）+ CacheFirst（静态） |
| 更新体验 | 静默更新（新 SW 后台装好，下次冷启动生效），不做弹窗提示 |
| 图标 | 代码生成：黑底 + 黄色「提」字 SVG 源 → sharp 转 PNG 各尺寸，视觉与现有「黑底黄字」统一 |
| `teleprompter.html` | 保留构建能力（兜底），但 README 主推用法改为「访问网址 → 添加到主屏幕」 |
| 数据迁移 | 不做（YAGNI），靠现有「导入 .txt/.md」 |
| 分发入口 | 微信发链接 → iPhone「在 Safari 中打开」→「添加到主屏幕」（首次一次性操作） |

## 4. 技术设计

### 4.1 整体架构

在现有 Vite + React + `vite-plugin-singlefile` 基础上叠加 PWA 能力。

**关键约束**：singlefile 把 entry 的 JS/CSS 内联进 `index.html`，但 manifest、Service Worker、图标**必须是独立文件**（SW 要求独立文件且 scope 正确；manifest 独立才好缓存与引用；图标天然是文件）。

**解法**：用 Vite 的 `public/` 目录。`public/` 内容被原样拷到 `dist/` 根，不经 singlefile 内联。

```
public/
├─ manifest.webmanifest
├─ sw.js
├─ icon.svg               # 矢量源
├─ icon-192.png
├─ icon-512.png
├─ icon-180.png           # apple-touch-icon
└─ icon-maskable-512.png
```

构建产物：

```
dist/
├─ index.html             # 自包含 JS/CSS（singlefile 内联）
├─ manifest.webmanifest   # public 原样拷贝
├─ sw.js                  # public 原样拷贝
└─ icon-*.{png,svg}       # public 原样拷贝
```

### 4.2 PWA 资源

**[vite.config.ts](../../../vite.config.ts)** 增加 `base: '/Prompter/'`。

**[index.html](../../../index.html) `<head>` 增补**（singlefile 基于此模板，会保留这些 meta）：

```html
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="提词器">
<meta name="theme-color" content="#000000">
<link rel="manifest" href="/Prompter/manifest.webmanifest">
<link rel="apple-touch-icon" href="/Prompter/icon-180.png">
<link rel="icon" type="image/svg+xml" href="/Prompter/icon.svg">
```

**`public/manifest.webmanifest`**：

```json
{
  "name": "提词器",
  "short_name": "提词器",
  "description": "为短视频拍摄设计的手机提词器",
  "display": "fullscreen",
  "orientation": "landscape",
  "background_color": "#000000",
  "theme_color": "#000000",
  "start_url": "/Prompter/",
  "scope": "/Prompter/",
  "icons": [
    { "src": "/Prompter/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/Prompter/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/Prompter/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" },
    { "src": "/Prompter/icon.svg", "sizes": "any", "type": "image/svg+xml" }
  ]
}
```

> - `display: fullscreen` 覆盖 Android Chrome；iOS 主要靠 `apple-mobile-web-app-*` meta。
> - `orientation: landscape` 契合主要横屏使用场景（iOS 不强制，但 Android 会尊重）。
> - 所有资源 URL 带 `/Prompter/` 前缀，匹配 GitHub Pages 项目站点子路径。

**图标**：手写 SVG 源（黑底圆角矩形 + 黄色「提」字，黄色取现有强调色 `#facc15`），用 `sharp`（devDependency）转 PNG 三尺寸 + maskable + 提交。`scripts/generate-icons.mjs` + `npm run icons`，按需运行，不进 build 流程。

### 4.3 离线（Service Worker）

**手写 `public/sw.js`**，不引入 Workbox / vite-plugin-pwa（precache 列表极短、项目偏轻量、singlefile 集成有摩擦）。

**缓存策略**：

| 请求类型 | 策略 | 说明 |
|---|---|---|
| 导航请求（HTML / `start_url`） | NetworkFirst（超时 ≈3s 回退缓存） | 在线拿最新（保证更新），离线返回缓存 HTML |
| 图标 / manifest / 同源静态 | CacheFirst | 静态不变，长期缓存 |
| `sw.js` 自身 | 浏览器自动管 | 改动触发更新流程 |
| 跨域 / 非 GET | 透传不拦截 | 避免副作用 |

**版本管理**：

- `sw.js` 顶部 `CACHE = 'prompter-v1'`，每次发布内容变了就 bump
- 新 SW `install` → `activate` 时清掉旧版本缓存 → `clients.claim()` 立即接管
- 通过 `event.respondWith` 内 NetworkFirst/CacheFirst 的极简实现，不引入运行时库

**注册**（[src/main.tsx](../../../src/main.tsx)）：

```ts
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('/Prompter/sw.js').catch(() => {});
}
```

> 仅 production 注册（dev 热更新会和 SW 缓存冲突）。

### 4.4 构建与部署

**`.github/workflows/deploy.yml`**，push 到 `main` 时：

1. checkout
2. setup-node 20
3. `npm ci`
4. `npm run build`
5. `actions/upload-pages-artifact`（path: `dist`）
6. `actions/deploy-pages`

- 权限：`pages: write`、`id-token: write`、`contents: read`
- 前置（一次性，写进 README）：仓库 **Settings → Pages → Source 选「GitHub Actions」**

### 4.5 UI 适配

**Safe-area**：`black-translucent` 让内容延伸到状态栏/刘海/灵动岛下。[index.html](../../../index.html) 已有 `viewport-fit=cover` ✓。所有「贴顶 / 贴底」固定 UI 加 `env(safe-area-inset-*)`：

- 顶部栏（[Teleprompter.tsx:291](../../../src/components/Teleprompter.tsx#L291)）：`pt-[calc(0.75rem+env(safe-area-inset-top))]`
- 底部控制条（[Controls.tsx](../../../src/components/Controls.tsx)）：叠 `pb-[env(safe-area-inset-bottom)]`
- ScriptList / ScriptEditor / SettingsPanel：顶部留 `env(safe-area-inset-top)`

> 横竖屏都用同一套 `env()`，但**必须双方向手动验证**（横屏时灵动岛在左/右上角）。

**状态栏**：现有顶部栏 `from-black/90 to-transparent` 黑底，白色状态栏文字可读 ✓。

**「添加到主屏幕」引导**：新增 [src/components/AddToHomeScreenPrompt.tsx](../../../src/components/AddToHomeScreenPrompt.tsx)。

- 触发条件：iOS Safari 且非 standalone（`navigator.standalone || matchMedia('(display-mode: standalone)').matches`）且未关闭过（`localStorage` key `prompter_aths_dismissed`）
- 内容：轻量提示「点底部「分享」→「添加到主屏幕」，以后像 App 一样全屏打开」+ 关闭按钮
- 关闭写 `localStorage`，不再弹
- Android `beforeinstallprompt` 顺带接，聚焦 iOS

## 5. 测试策略

| 类型 | 范围 |
|---|---|
| 单元测试 | `AddToHomeScreenPrompt` 的显示判定（mock `navigator` / `matchMedia`）；关闭后写 `localStorage` |
| 手动验证清单（核心） | ① iPhone Safari 访问网址 → 添加到主屏幕 → 从图标启动无地址栏 ✅<br>② 添加后断网 → 仍能打开使用（SW 离线）✅<br>③ 横屏使用顶部栏不被灵动岛遮挡 ✅<br>④ 状态栏文字可读 ✅<br>⑤ 桌面 Chrome 全屏按钮仍正常（不破坏桌面体验）✅ |
| 不测 | 手写 SW 本身（极简，靠手动验证离线 + 版本更新） |

## 6. 已知限制 / 不做

| 项 | 说明 |
|----|------|
| 数据迁移 | 不做。跨来源/跨设备的 `localStorage` 隔离靠现有「导入 .txt/.md」兜底，真遇到再加（原方案 C） |
| Wake Lock | iOS PWA standalone 下 Wake Lock 支持仍有限（沿用现有降级提示），不在本次范围 |
| 强制横屏 | iOS 不允许网页强制旋转，`orientation: landscape` 仅 Android 尊重，iOS 继续靠提示 |
| SW 更新提示 | 静默更新，不做「有新版是否刷新」弹窗 |
| `teleprompter.html` | 保留构建能力（兜底），但其 PWA 能力在 `file://` 下失效，仅作离线单文件应急；README 主推网址 |
