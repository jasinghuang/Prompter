# 提词器 PWA 化（iPhone 全屏 + 离线）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把提词器改造成 PWA，部署到 GitHub Pages，iPhone 用 Safari「添加到主屏幕」后全屏启动、断网可用。

**Architecture:** 在现有 Vite + React + `vite-plugin-singlefile` 之上叠加 PWA：用 `public/` 目录放独立 manifest / SW / 图标（不被 singlefile 内联），手写 Service Worker 做离线缓存，补全 Apple meta + manifest 实现全屏，safe-area 适配刘海/灵动岛，GitHub Actions 自动部署。

**Tech Stack:** Vite 6、React 19、TypeScript 5.8、TailwindCSS 4、Vitest 2、`vite-plugin-singlefile`、`sharp`（devDep，仅生成图标）、GitHub Pages + Actions。

## Global Constraints

- 部署 URL 前缀固定 `/Prompter/`（仓库 `jasinghuang/Prompter` 的 GitHub Pages 项目站点）。所有 manifest / SW / 图标 / start_url / scope 路径均带此前缀。
- Service Worker 缓存 key：`prompter-v1`；每次发布内容变更必须 bump（如 `prompter-v2`）。
- localStorage key：`prompter_aths_dismissed`（用户已关闭「添加到主屏幕」引导）。
- 视觉一致：黑底（`#000000`/`#050505`）+ 黄强调（`#facc15`），图标为黑底 + 黄色「提」字。
- **不引入** Workbox / `vite-plugin-pwa`（手写 SW）。`sharp` 仅作 devDependency，`npm run icons` 按需运行，**不进 build 流程**。
- Service Worker 仅在 production 注册（`import.meta.env.PROD`）。
- 现有测试（`npm test`）在每个任务后必须仍全绿。
- 单文件产物 `teleprompter.html` 保留构建能力（`cp dist/index.html ./teleprompter.html` 仍可执行），但 README 主推 PWA 网址用法。

---

### Task 1: PWA 基础 — base path + manifest + Apple meta

**Files:**
- Modify: `vite.config.ts`
- Create: `public/manifest.webmanifest`
- Modify: `index.html`

**Interfaces:**
- Produces: 部署在 `/Prompter/manifest.webmanifest` 的 Web App Manifest；`index.html` 中完整的 Apple PWA meta 与 manifest 链接。供 Task 3（SW precache 列表）、Task 4（SW 注册无需 manifest，但同前缀）、Task 7（部署）依赖。

- [ ] **Step 1: 改 `vite.config.ts`，加 `base`**

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

export default defineConfig({
  base: '/Prompter/',
  plugins: [react(), tailwindcss(), viteSingleFile()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
});
```

- [ ] **Step 2: 创建 `public/manifest.webmanifest`**

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

- [ ] **Step 3: 改 `index.html`，补 PWA meta（保留现有 viewport 的 `viewport-fit=cover`）**

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="提词器">
    <meta name="theme-color" content="#000000">
    <meta name="description" content="为短视频拍摄设计的手机提词器">
    <link rel="manifest" href="/Prompter/manifest.webmanifest">
    <link rel="apple-touch-icon" href="/Prompter/icon-180.png">
    <link rel="icon" type="image/svg+xml" href="/Prompter/icon.svg">
    <title>提词器</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 4: 构建并验证产物**

Run: `npm run build`
然后校验：

```bash
test -f dist/manifest.webmanifest && echo "manifest OK"
grep -q "apple-mobile-web-app-capable" dist/index.html && echo "meta OK"
grep -q "/Prompter/manifest.webmanifest" dist/index.html && echo "manifest link OK"
```

Expected: 三行 OK 全部输出（说明 base 前缀、meta、manifest 拷贝均生效）。

- [ ] **Step 5: 确认现有测试不破坏**

Run: `npm test`
Expected: 全部通过。

- [ ] **Step 6: Commit**

```bash
git add vite.config.ts public/manifest.webmanifest index.html
git commit -m "feat(pwa): base 前缀 + manifest + Apple 全屏 meta"
```

---

### Task 2: 图标 — SVG 源 + 生成脚本 + PNG 产物

**Files:**
- Create: `public/icon.svg`
- Create: `scripts/generate-icons.mjs`
- Modify: `package.json`（加 `sharp` devDep + `icons` script）
- 生成物（提交进仓库）：`public/icon-192.png`、`public/icon-512.png`、`public/icon-180.png`、`public/icon-maskable-512.png`

**Interfaces:**
- Produces: 四个 PNG + 一个 SVG，被 Task 1 的 manifest / `index.html` 的 `apple-touch-icon` 引用。

- [ ] **Step 1: 写 SVG 源 `public/icon.svg`（黑底圆角 + 黄「提」字）**

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect width="1024" height="1024" rx="224" fill="#000000"/>
  <text x="512" y="512" font-family="-apple-system, 'PingFang SC', 'Helvetica Neue', sans-serif" font-size="620" font-weight="900" fill="#facc15" text-anchor="middle" dominant-baseline="central">提</text>
</svg>
```

> 字号 620 / 1024 ≈ 60%，落在 maskable 安全区（中间 80%）内；背景填满，无透明边角。

- [ ] **Step 2: 写生成脚本 `scripts/generate-icons.mjs`**

```js
import sharp from 'sharp';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');
const svg = readFileSync(resolve(root, 'public/icon.svg'));

const targets = [
  { size: 192, file: 'icon-192.png' },
  { size: 512, file: 'icon-512.png' },
  { size: 180, file: 'icon-180.png' },
  { size: 512, file: 'icon-maskable-512.png' },
];

for (const { size, file } of targets) {
  await sharp(svg, { density: 384 })
    .resize(size, size)
    .png()
    .toFile(resolve(root, 'public', file));
  console.log(`generated ${file} (${size}x${size})`);
}
```

- [ ] **Step 3: `package.json` 加 sharp 与 scripts**

在 `scripts` 块加一行（保持其它键不变）：

```json
"icons": "node scripts/generate-icons.mjs"
```

在 `devDependencies` 块加一行：

```json
"sharp": "^0.33.5"
```

- [ ] **Step 4: 安装并生成**

Run: `npm install`
Run: `npm run icons`
Expected: 控制台打印 4 行 `generated ...`。

- [ ] **Step 5: 验证 PNG 尺寸正确**

Run:

```bash
node -e "import('sharp').then(async m => { const s = m.default; for (const f of ['icon-192','icon-512','icon-180','icon-maskable-512']) { const md = await s('public/'+f+'.png').metadata(); console.log(f, md.width + 'x' + md.height); } })"
```

Expected: 输出 `icon-192 192x192`、`icon-512 512x512`、`icon-180 180x180`、`icon-maskable-512 512x512`。

- [ ] **Step 6: Commit**

```bash
git add public/icon.svg public/icon-192.png public/icon-512.png public/icon-180.png public/icon-maskable-512.png scripts/generate-icons.mjs package.json package-lock.json
git commit -m "feat(pwa): 黑底黄字图标 + sharp 生成脚本"
```

---

### Task 3: Service Worker — 离线缓存

**Files:**
- Create: `public/sw.js`

**Interfaces:**
- Produces: 部署在 `/Prompter/sw.js` 的 Service Worker，scope 为 `/Prompter/`，导航请求 NetworkFirst、静态资源 CacheFirst、跨域/非 GET 透传。
- Consumes: Task 1 的 base 前缀（硬编码进 precache 列表）。

> spec 已明确：手写 SW 不做自动化单测，靠手动验证（离线 + 版本更新）。本任务以代码 + review + 手动验证清单为主。

- [ ] **Step 1: 写 `public/sw.js`**

```js
// 提词器 Service Worker — 离线缓存
// 发布内容变更时 bump CACHE 版本号以触发更新与旧缓存清理
const CACHE = 'prompter-v1';
const SCOPE = '/Prompter/';
const PRECACHE = [
  SCOPE,
  SCOPE + 'index.html',
  SCOPE + 'manifest.webmanifest',
  SCOPE + 'icon-192.png',
  SCOPE + 'icon-512.png',
  SCOPE + 'icon-180.png',
  SCOPE + 'icon.svg',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.all(
      PRECACHE.map((url) =>
        fetch(url, { cache: 'reload' })
          .then((res) => res.ok && cache.put(url, res.clone()))
          .catch(() => {})
      )
    );
    self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (req.mode === 'navigate') {
    event.respondWith(networkFirst(req));
  } else {
    event.respondWith(cacheFirst(req));
  }
});

async function networkFirst(req) {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 3000);
    const res = await fetch(req, { signal: controller.signal, cache: 'no-store' });
    clearTimeout(timer);
    if (res.ok) {
      const cache = await caches.open(CACHE);
      cache.put(req, res.clone());
    }
    return res;
  } catch {
    const cached = await caches.match(req);
    if (cached) return cached;
    const fallback = await caches.match(SCOPE + 'index.html');
    return fallback || Response.error();
  }
}

async function cacheFirst(req) {
  const cached = await caches.match(req);
  if (cached) return cached;
  try {
    const res = await fetch(req);
    if (res.ok) {
      const cache = await caches.open(CACHE);
      cache.put(req, res.clone());
    }
    return res;
  } catch {
    return Response.error();
  }
}
```

- [ ] **Step 2: 语法自检**

Run: `node --check public/sw.js`
Expected: 无输出（语法正确）。

- [ ] **Step 3: Review 检查清单（逐条过一遍）**

- 导航请求走 NetworkFirst，3s 超时回退缓存 ✓
- 静态资源走 CacheFirst ✓
- 非 GET、跨域请求透传不拦截 ✓
- `activate` 清理非当前版本缓存 ✓
- `skipWaiting` + `clients.claim` 快速接管 ✓
- 内容变更时记得 bump `CACHE`（如改 `prompter-v2`）✓

- [ ] **Step 4: Commit**

```bash
git add public/sw.js
git commit -m "feat(pwa): 手写 Service Worker（NetworkFirst 导航 + CacheFirst 静态）"
```

---

### Task 4: SW 注册

**Files:**
- Create: `src/sw/registerSW.ts`
- Create: `src/sw/registerSW.test.ts`
- Modify: `src/main.tsx`

**Interfaces:**
- Produces: `registerSW(swUrl: string): Promise<void>` —— 不支持 SW 时静默跳过、register 失败不抛错。
- Consumes: Task 3 的 `/Prompter/sw.js`。

- [ ] **Step 1: 写失败测试 `src/sw/registerSW.test.ts`**

```ts
import { describe, it, expect, vi } from 'vitest';
import { registerSW } from './registerSW';

describe('registerSW', () => {
  it('不支持 serviceWorker 时静默跳过', async () => {
    // jsdom 默认不提供 navigator.serviceWorker
    await expect(registerSW('/Prompter/sw.js')).resolves.toBeUndefined();
  });

  it('支持时调用 register 并传入 URL', async () => {
    const register = vi.fn().mockResolvedValue({});
    Object.defineProperty(navigator, 'serviceWorker', {
      value: { register },
      configurable: true,
    });
    await registerSW('/Prompter/sw.js');
    expect(register).toHaveBeenCalledWith('/Prompter/sw.js');
  });

  it('register 抛错时不传播', async () => {
    const register = vi.fn().mockRejectedValue(new Error('fail'));
    Object.defineProperty(navigator, 'serviceWorker', {
      value: { register },
      configurable: true,
    });
    await expect(registerSW('/Prompter/sw.js')).resolves.toBeUndefined();
  });
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `npx vitest run src/sw/registerSW.test.ts`
Expected: FAIL（`Cannot find module './registerSW'`）。

- [ ] **Step 3: 写实现 `src/sw/registerSW.ts`**

```ts
/**
 * 注册 Service Worker。不支持 SW 的环境静默跳过；注册失败不抛错，
 * 以免影响应用主体功能。仅在 production 调用（见 main.tsx）。
 */
export async function registerSW(swUrl: string): Promise<void> {
  if (!('serviceWorker' in navigator)) return;
  try {
    await navigator.serviceWorker.register(swUrl);
  } catch {
    // 注册失败不影响应用使用
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `npx vitest run src/sw/registerSW.test.ts`
Expected: PASS（3 个用例全绿）。

- [ ] **Step 5: 改 `src/main.tsx`，production 下注册**

```tsx
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { registerSW } from './sw/registerSW';
import './index.css';

if (import.meta.env.PROD) {
  registerSW('/Prompter/sw.js');
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

- [ ] **Step 6: 全量测试不破坏**

Run: `npm test`
Expected: 全绿。

- [ ] **Step 7: Commit**

```bash
git add src/sw/registerSW.ts src/sw/registerSW.test.ts src/main.tsx
git commit -m "feat(pwa): production 下注册 Service Worker"
```

---

### Task 5: 「添加到主屏幕」引导

**Files:**
- Create: `src/lib/pwa.ts`
- Create: `src/lib/pwa.test.ts`
- Create: `src/components/AddToHomeScreenPrompt.tsx`
- Create: `src/components/AddToHomeScreenPrompt.test.tsx`
- Modify: `src/App.tsx`

**Interfaces:**
- Produces:
  - `shouldShowInstallPrompt(state): boolean`
  - `detectStandalone(): boolean`
  - `detectIOS(): boolean`
  - `ATTS_DISMISSED_KEY = 'prompter_aths_dismissed'`
  - `<AddToHomeScreenPrompt />` 组件（无 props，自包含）
- Consumes: localStorage（key `prompter_aths_dismissed`）、`beforeinstallprompt` 事件。

- [ ] **Step 1: 写判定函数失败测试 `src/lib/pwa.test.ts`**

```ts
import { describe, it, expect } from 'vitest';
import { shouldShowInstallPrompt } from './pwa';

describe('shouldShowInstallPrompt', () => {
  it('已 standalone 时不显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: true, dismissed: false, isIOS: true, hasBeforeInstallPrompt: false })
    ).toBe(false);
  });

  it('已关闭时不显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: true, isIOS: true, hasBeforeInstallPrompt: false })
    ).toBe(false);
  });

  it('iOS + 未关闭 + 非 standalone 时显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: false, isIOS: true, hasBeforeInstallPrompt: false })
    ).toBe(true);
  });

  it('Android 有 beforeinstallprompt 时显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: false, isIOS: false, hasBeforeInstallPrompt: true })
    ).toBe(true);
  });

  it('桌面浏览器不显示', () => {
    expect(
      shouldShowInstallPrompt({ standalone: false, dismissed: false, isIOS: false, hasBeforeInstallPrompt: false })
    ).toBe(false);
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/lib/pwa.test.ts`
Expected: FAIL（`Cannot find module './pwa'`）。

- [ ] **Step 3: 写实现 `src/lib/pwa.ts`**

```ts
/** localStorage key：用户已关闭「添加到主屏幕」引导 */
export const ATTS_DISMISSED_KEY = 'prompter_aths_dismissed';

export interface InstallPromptState {
  standalone: boolean;
  dismissed: boolean;
  isIOS: boolean;
  hasBeforeInstallPrompt: boolean;
}

/**
 * 是否显示「添加到主屏幕」引导：
 * 已 standalone / 已关闭 → 否；iOS 或有 beforeinstallprompt → 是；其余 → 否。
 */
export function shouldShowInstallPrompt(state: InstallPromptState): boolean {
  if (state.standalone || state.dismissed) return false;
  return state.isIOS || state.hasBeforeInstallPrompt;
}

/** 当前是否 standalone（主屏全屏）模式 */
export function detectStandalone(): boolean {
  if (typeof window === 'undefined') return false;
  const nav = window.navigator as Navigator & { standalone?: boolean };
  return nav.standalone === true || window.matchMedia('(display-mode: standalone)').matches;
}

/** 是否 iOS Safari（需手动引导，无 beforeinstallprompt） */
export function detectIOS(): boolean {
  if (typeof navigator === 'undefined') return false;
  const ua = navigator.userAgent || '';
  return /iPad|iPhone|iPod/.test(ua) || (ua.includes('Macintosh') && 'ontouchend' in document);
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/lib/pwa.test.ts`
Expected: PASS（5 用例全绿）。

- [ ] **Step 5: 写组件失败测试 `src/components/AddToHomeScreenPrompt.test.tsx`**

```tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { AddToHomeScreenPrompt } from './AddToHomeScreenPrompt';
import * as pwa from '../lib/pwa';

beforeEach(() => {
  cleanup();
  localStorage.clear();
  vi.restoreAllMocks();
});

describe('AddToHomeScreenPrompt', () => {
  it('不满足条件时不渲染', () => {
    vi.spyOn(pwa, 'detectStandalone').mockReturnValue(false);
    vi.spyOn(pwa, 'detectIOS').mockReturnValue(false);
    render(<AddToHomeScreenPrompt />);
    expect(screen.queryByText(/添加到主屏幕|安装到主屏幕/)).toBeNull();
  });

  it('iOS + 未关闭时渲染提示文案', () => {
    vi.spyOn(pwa, 'detectStandalone').mockReturnValue(false);
    vi.spyOn(pwa, 'detectIOS').mockReturnValue(true);
    render(<AddToHomeScreenPrompt />);
    expect(screen.getByText(/添加到主屏幕/)).toBeInTheDocument();
  });

  it('点关闭按钮后写 localStorage 并消失', () => {
    vi.spyOn(pwa, 'detectStandalone').mockReturnValue(false);
    vi.spyOn(pwa, 'detectIOS').mockReturnValue(true);
    const { container } = render(<AddToHomeScreenPrompt />);
    fireEvent.click(container.querySelector('[aria-label="关闭"]')!);
    expect(localStorage.getItem('prompter_aths_dismissed')).toBe('1');
    expect(container.querySelector('[aria-label="关闭"]')).toBeNull();
  });
});
```

- [ ] **Step 6: 运行确认失败**

Run: `npx vitest run src/components/AddToHomeScreenPrompt.test.tsx`
Expected: FAIL（找不到组件模块）。

- [ ] **Step 7: 写组件 `src/components/AddToHomeScreenPrompt.tsx`**

```tsx
import { useEffect, useState } from 'react';
import { Share, X } from 'lucide-react';
import { ATTS_DISMISSED_KEY, detectStandalone, detectIOS } from '../lib/pwa';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
}

/**
 * 「添加到主屏幕」引导。
 * iOS：提示用户「分享 → 添加到主屏幕」；Android：捕获 beforeinstallprompt 触发系统安装。
 */
export function AddToHomeScreenPrompt() {
  const [show, setShow] = useState(false);
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    const dismissed = localStorage.getItem(ATTS_DISMISSED_KEY) === '1';
    if (detectIOS() && !dismissed && !detectStandalone()) {
      setShow(true);
    }
    const onBIP = (e: Event) => {
      e.preventDefault();
      const ev = e as BeforeInstallPromptEvent;
      setDeferred(ev);
      if (!dismissed && !detectStandalone()) setShow(true);
    };
    window.addEventListener('beforeinstallprompt', onBIP);
    return () => window.removeEventListener('beforeinstallprompt', onBIP);
  }, []);

  const dismiss = () => {
    localStorage.setItem(ATTS_DISMISSED_KEY, '1');
    setShow(false);
  };

  const install = async () => {
    if (!deferred) return;
    await deferred.prompt();
    setDeferred(null);
    setShow(false);
  };

  if (!show) return null;
  const isIOS = detectIOS();

  return (
    <div className="fixed bottom-5 left-1/2 z-[90] flex w-[92vw] max-w-md -translate-x-1/2 items-center gap-3 rounded-2xl border border-yellow-500/30 bg-neutral-900/95 p-4 shadow-2xl backdrop-blur-xl">
      <Share size={20} className="shrink-0 text-yellow-500" />
      <div className="flex-1 text-sm leading-snug text-neutral-200">
        {isIOS
          ? '点 Safari 底部「分享」→「添加到主屏幕」，以后像 App 一样全屏打开'
          : '安装到主屏幕，以后全屏打开'}
      </div>
      <button
        onClick={isIOS ? dismiss : install}
        className="shrink-0 rounded-full bg-yellow-500 px-3 py-1.5 text-xs font-bold text-black"
      >
        {isIOS ? '知道' : '安装'}
      </button>
      <button onClick={dismiss} aria-label="关闭" className="shrink-0 text-neutral-500 hover:text-white">
        <X size={16} />
      </button>
    </div>
  );
}
```

- [ ] **Step 8: 运行确认通过**

Run: `npx vitest run src/components/AddToHomeScreenPrompt.test.tsx`
Expected: PASS（3 用例全绿）。

- [ ] **Step 9: 改 `src/App.tsx`，在 list 视图接入**

在文件顶部 import 块加：

```tsx
import { AddToHomeScreenPrompt } from './components/AddToHomeScreenPrompt';
```

把最后的 `return (<ScriptList ... />)` 改为：

```tsx
  return (
    <>
      <ScriptList
        scripts={scripts}
        onOpen={openPrompter}
        onEdit={(id) => { setActiveId(id); setEditSnapshot(null); setView('editor'); }}
        onDelete={deleteScript}
        onDeleteAll={clearAll}
        onCreate={handleCreate}
        onImport={handleImport}
      />
      <AddToHomeScreenPrompt />
    </>
  );
```

- [ ] **Step 10: 全量测试不破坏**

Run: `npm test`
Expected: 全绿。

- [ ] **Step 11: Commit**

```bash
git add src/lib/pwa.ts src/lib/pwa.test.ts src/components/AddToHomeScreenPrompt.tsx src/components/AddToHomeScreenPrompt.test.tsx src/App.tsx
git commit -m "feat(pwa): 添加到主屏幕引导（iOS 手动 + Android beforeinstallprompt）"
```

---

### Task 6: Safe-area 适配

**Files:**
- Modify: `src/components/Teleprompter.tsx`（顶部栏，约 291 行）
- Modify: `src/components/Controls.tsx:17`（底部定位）
- Modify: `src/components/ScriptList.tsx:51`（顶部 header）
- Modify: `src/components/ScriptEditor.tsx:32`（顶部 header）
- Modify: `src/components/SettingsPanel.tsx:51`（右侧面板内层）

**Interfaces:**
- Consumes: `index.html` 的 `viewport-fit=cover`（Task 1 保留）。
- 说明：直接用 Tailwind 任意值 `calc(... + env(safe-area-inset-*))`，**不**叠加工具类（避免被 `p-3`/`py-3` 的 padding 覆盖）。

- [ ] **Step 1: Teleprompter 顶部栏（[Teleprompter.tsx:291](src/components/Teleprompter.tsx#L291)）**

将：

```
className="absolute inset-x-0 top-0 z-50 flex items-center justify-between bg-gradient-to-b from-black/90 to-transparent p-3"
```

改为（`p-3` 拆成 `px-3 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))]`）：

```
className="absolute inset-x-0 top-0 z-50 flex items-center justify-between bg-gradient-to-b from-black/90 to-transparent px-3 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))]"
```

- [ ] **Step 2: Controls 底部定位（[Controls.tsx:17](src/components/Controls.tsx#L17)）**

将外层 div 的：

```
className="absolute bottom-4 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-neutral-800 bg-neutral-900/85 p-2 shadow-2xl backdrop-blur-xl"
```

改为（`bottom-4` → `bottom-[calc(1rem+env(safe-area-inset-bottom))]`）：

```
className="absolute bottom-[calc(1rem+env(safe-area-inset-bottom))] left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-neutral-800 bg-neutral-900/85 p-2 shadow-2xl backdrop-blur-xl"
```

- [ ] **Step 3: ScriptList 顶部 header（[ScriptList.tsx:51](src/components/ScriptList.tsx#L51)）**

将：

```
className="sticky top-0 z-50 border-b border-neutral-900 bg-black/60 px-4 py-3 backdrop-blur-xl"
```

改为（`py-3` 拆开）：

```
className="sticky top-0 z-50 border-b border-neutral-900 bg-black/60 px-4 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))] backdrop-blur-xl"
```

- [ ] **Step 4: ScriptEditor 顶部 header（[ScriptEditor.tsx:32](src/components/ScriptEditor.tsx#L32)）**

将：

```
className="sticky top-0 z-50 flex h-16 items-center justify-between border-b border-neutral-900 bg-black/70 px-4 backdrop-blur-xl"
```

改为（去掉固定 `h-16`，高度由 padding 自适应，顶部叠安全区）：

```
className="sticky top-0 z-50 flex items-center justify-between border-b border-neutral-900 bg-black/70 px-4 pb-4 pt-[calc(1rem+env(safe-area-inset-top))] backdrop-blur-xl"
```

- [ ] **Step 5: SettingsPanel 右侧面板（[SettingsPanel.tsx:51](src/components/SettingsPanel.tsx#L51)）**

将内层面板的：

```
className="relative h-full w-80 max-w-[85vw] overflow-y-auto border-l border-neutral-800 bg-neutral-900 p-6 shadow-2xl"
```

改为（`p-6` 拆开，顶/底都叠安全区）：

```
className="relative h-full w-80 max-w-[85vw] overflow-y-auto border-l border-neutral-800 bg-neutral-900 px-6 pb-[calc(1.5rem+env(safe-area-inset-bottom))] pt-[calc(1.5rem+env(safe-area-inset-top))] shadow-2xl"
```

- [ ] **Step 6: 构建验证 + 全量测试**

Run: `npm run build && npm test`
Expected: 构建成功；测试全绿。

- [ ] **Step 7: Commit**

```bash
git add src/components/Teleprompter.tsx src/components/Controls.tsx src/components/ScriptList.tsx src/components/ScriptEditor.tsx src/components/SettingsPanel.tsx
git commit -m "feat(pwa): safe-area 适配（刘海/灵动岛/home indicator）"
```

---

### Task 7: GitHub Actions 部署 + README

**Files:**
- Create: `.github/workflows/deploy.yml`
- Modify: `README.md`

**Interfaces:**
- Produces: push 到 main 自动构建并发布 GitHub Pages；README 主推 PWA 用法。

- [ ] **Step 1: 创建 `.github/workflows/deploy.yml`**

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run build
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: dist
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: YAML 语法校验**

Run: `node -e "require('node:fs').readFileSync('.github/workflows/deploy.yml','utf8')"`
Expected: 无输出（文件可读）。再人工核对缩进为 2 空格、`on:`/`jobs:` 顶层 key 正确。

- [ ] **Step 3: 更新 README 的「怎么用（最终用户）」段**

把 [README.md](README.md) 第 54-62 行（`## 🚀 怎么用（最终用户）` 那一节）整段替换为：

```markdown
## 🚀 怎么用（最终用户）

### 推荐：网页版 PWA（iPhone 全屏 + 离线）

1. 在手机 Safari 打开 **https://jasinghuang.github.io/Prompter/**
2. 点 Safari 底部「分享」→「添加到主屏幕」
3. 以后从桌面图标启动 → **全屏无浏览器外壳**，断网也能用（首次访问后离线缓存生效）

> 微信里点链接打不开全屏：点右上角「…」→「在 Safari 中打开」再做第 2 步。

### 兜底：单 HTML 文件（离线/临时）

拿到 [`teleprompter.html`](teleprompter.html)，浏览器打开即用。注意：本地 `file://` 下无 PWA 全屏/离线能力，iPhone 体验不如网页版，仅供无网应急。
```

- [ ] **Step 4: 更新 README「已知限制」表，补一行 iOS PWA 说明**

在 [README.md](README.md) 「⚠️ 已知限制」表格末尾加一行：

```markdown
| iOS 全屏 | 仅 PWA「添加到主屏幕」可全屏；iPhone Safari 不支持普通网页的 Fullscreen API。 |
```

- [ ] **Step 5: 在 README「开发」节加部署配置提示**

在 [README.md](README.md) 「### 安装与运行」小节的构建说明后追加：

```markdown
### 部署（GitHub Pages，自动）

push 到 `main` 即触发 `.github/workflows/deploy.yml` 自动构建并发布。首次需在仓库 **Settings → Pages → Source 选「GitHub Actions」**（一次性）。部署地址：`https://jasinghuang.github.io/Prompter/`。
```

- [ ] **Step 6: 最终全量验证**

Run: `npm run build && npm test`
Expected: 构建成功、产物含 `dist/manifest.webmanifest` + `dist/sw.js` + `dist/icon-*.png`；测试全绿。

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/deploy.yml README.md
git commit -m "feat(pwa): GitHub Pages 自动部署 + README 主推 PWA 用法"
```

- [ ] **Step 8: 一次性仓库配置（人工）**

在 GitHub 仓库 `jasinghuang/Prompter` → **Settings → Pages → Source** 选择「GitHub Actions」。

- [ ] **Step 9: 合并到 main 触发部署**

合并 `feat/pwa-ios-fullscreen` 到 `main`，在仓库 **Actions** 标签页确认 workflow 跑通，部署完成后访问 `https://jasinghuang.github.io/Prompter/`。

- [ ] **Step 10: iPhone 真机验证清单（spec 核心验收）**

- ① Safari 打开网址 → 分享 → 添加到主屏幕 → 从图标启动 → **无地址栏/工具栏**（全屏）✅
- ② 添加主屏后断网（飞行模式）→ 从图标启动 → **仍能打开、能提词**（SW 离线）✅
- ③ 横屏使用 → 顶部控制栏**不被灵动岛/状态栏遮挡** ✅
- ④ 状态栏时间/电池在黑底上**可读** ✅
- ⑤ 桌面 Chrome 打开 → 现有「全屏」按钮**仍正常**（不破坏桌面体验）✅
- ⑥ 列表页底部出现「添加到主屏幕」引导，关闭后不再弹 ✅

---

## 验收总览

| spec 要求 | 对应任务 |
|---|---|
| PWA meta + manifest（全屏） | Task 1 |
| 图标（黑底黄字「提」） | Task 2 |
| Service Worker 离线 | Task 3 + Task 4 |
| 「添加到主屏幕」引导 | Task 5 |
| Safe-area 适配 | Task 6 |
| GitHub Pages 自动部署 | Task 7 |
| README 主推网址用法 | Task 7 |
| teleprompter.html 保留兜底 | Task 7（README 说明） |
