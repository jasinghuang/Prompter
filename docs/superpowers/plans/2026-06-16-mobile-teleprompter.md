# 手机提词器 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个纯前端、单 HTML 产出的手机提词器，支持逐字高亮滚动、横屏自适应、字号/字间距/行距/速度调节、镜像翻转、多稿管理与自动保存、进度条与计时器、移动端体验增强。

**Architecture:** Vite + React 19 + TypeScript，TailwindCSS 4（`@tailwindcss/vite` 插件），构建时用 `vite-plugin-singlefile` 内联成单个 `index.html`。纯逻辑（token 拆分、速度换算、自动推进数学、存储、编辑定位解析、防抖、计时）抽成可单元测试的纯函数/hook；UI 组件用 React Testing Library 测关键行为。三视图状态机（list / prompter / editor）由 `App.tsx` 驱动。

**Tech Stack:** Vite 6, React 19, TypeScript 5.8, TailwindCSS 4, lucide-react（图标），Vitest 2 + @testing-library/react + jsdom（测试），vite-plugin-singlefile（构建内联）。

**版本决策（与规格 3.1 的差异）：** 规格写 React 18 + 传统 Tailwind（postcss + tailwind.config.ts）。本计划跟随参考代码 `ref_code` 采用 React 19 + Tailwind 4（`@tailwindcss/vite`）。理由：① 直接对齐参考实现，便于借鉴其观感；② Tailwind 4 免除 `postcss.config.js` / `tailwind.config.ts`，配置更简。这是新项目、无既定约束，属合理优化。

---

## 设计规格

完整设计见 `docs/superpowers/specs/2026-06-16-mobile-teleprompter-design.md`。关键约定：

- 默认设置：`fontSize: 64`（24–120）、`letterSpacing: 0.05`（0–0.3 em）、`lineHeight: 1.6`（1.0–2.5）、`scrollSpeed: 160`（60–360 WPN）、`mirror: false`
- WPN 预设：龟速 80 / 标准 160 / 快语 240 / 极速 320
- 模式：`'manual' | 'auto'`；速度档仅 auto 模式显示
- 编辑返回定位：改动未跨越当前位置则保持，跨越则重置到开头 + 轻提示

## File Structure

```
prompter/
├─ index.html
├─ package.json
├─ vite.config.ts
├─ tsconfig.json
├─ tsconfig.node.json
├─ vitest.config.ts
├─ src/
│  ├─ main.tsx
│  ├─ App.tsx                    # 三视图状态机 + 编辑返回定位 + 横屏提示
│  ├─ index.css                  # Tailwind 4 import + 提词器全局样式
│  ├─ types.ts                   # Script / TeleprompterSettings / DEFAULT_SETTINGS
│  ├─ lib/
│  │  ├─ tokens.ts               # tokenize / countReadableChars
│  │  ├─ speed.ts                # SPEED_PRESETS / msPerChar / estimateDurationSeconds / stepAutoAdvance
│  │  ├─ editResolve.ts          # resolveIndexAfterEdit
│  │  └─ format.ts               # formatTime (mm:ss)
│  ├─ store/
│  │  ├─ storage.ts              # localStorage 读写 + 容错
│  │  ├─ useScripts.ts           # 稿件 CRUD hook
│  │  └─ useSettings.ts          # 全局设置 hook
│  ├─ hooks/
│  │  ├─ useDebouncedCallback.ts
│  │  ├─ useTimer.ts             # 墙钟计时（播放累加/暂停停）
│  │  ├─ useAutoAdvance.ts       # auto 模式 rAF 推进
│  │  ├─ useSmoothScroll.ts      # scrollTop 缓动到中线
│  │  ├─ useWakeLock.ts          # 屏幕常亮 + 降级提示
│  │  └─ useFullscreen.ts        # 全屏
│  └─ components/
│     ├─ ScriptText.tsx          # 逐字渲染 + 三态高亮
│     ├─ Controls.tsx            # 底部胶囊控制条
│     ├─ SettingsPanel.tsx       # 设置抽屉
│     ├─ ScriptEditor.tsx        # 编辑文案 + 自动保存
│     ├─ ScriptList.tsx          # 稿件列表/搜索/新建/删除
│     └─ Teleprompter.tsx        # 提词器主视图（整合）
└─ tests/                        # （测试与源码同目录 *.test.ts(x)，无独立 tests 目录）
```

测试文件与源码同目录、同名加 `.test`：如 `src/lib/speed.test.ts`、`src/components/Controls.test.tsx`。

---

## Task 1: 项目脚手架与测试基建

**Files:**
- Create: `package.json`, `index.html`, `vite.config.ts`, `vitest.config.ts`, `tsconfig.json`, `tsconfig.node.json`, `src/main.tsx`, `src/App.tsx`, `src/index.css`, `src/test-setup.ts`

- [ ] **Step 1: 初始化 package.json 并安装依赖**

Create `package.json`:
```json
{
  "name": "prompter",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "lucide-react": "^0.546.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.1.14",
    "@testing-library/jest-dom": "^6.6.3",
    "@testing-library/react": "^16.1.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^5.0.4",
    "jsdom": "^25.0.1",
    "tailwindcss": "^4.1.14",
    "typescript": "~5.8.2",
    "vite": "^6.2.0",
    "vite-plugin-singlefile": "^2.0.1",
    "vitest": "^2.1.9"
  }
}
```

Run:
```bash
npm install
```
Expected: 依赖安装成功，无错误。

- [ ] **Step 2: 创建 Vite 配置（含 singlefile）**

Create `vite.config.ts`:
```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

export default defineConfig({
  plugins: [react(), tailwindcss(), viteSingleFile()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
});
```

- [ ] **Step 3: 创建 Vitest 配置与测试 setup**

Create `vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test-setup.ts'],
  },
});
```

Create `src/test-setup.ts`:
```ts
import '@testing-library/jest-dom/vitest';
import { afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';

afterEach(() => {
  cleanup();
  localStorage.clear();
});
```

- [ ] **Step 4: 创建 TypeScript 配置**

Create `tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "types": ["vitest/globals"]
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

Create `tsconfig.node.json`:
```json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts", "vitest.config.ts"]
}
```

- [ ] **Step 5: 创建 index.html、入口、空壳 App、Tailwind CSS**

Create `index.html`:
```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
    <title>提词器</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

Create `src/index.css`:
```css
@import "tailwindcss";

html, body, #root {
  height: 100%;
  margin: 0;
}

body {
  background: #050505;
  color: #fff;
  font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
  overscroll-behavior: none;
}
```

Create `src/main.tsx`:
```tsx
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './index.css';

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

Create `src/App.tsx`:
```tsx
export default function App() {
  return <div className="p-8 text-neutral-200">提词器（脚手架）</div>;
}
```

- [ ] **Step 6: 验证 dev 与测试基建可用**

Run:
```bash
npm run dev
```
Expected: Vite 启动，浏览器打开显示"提词器（脚手架）"，黑底白字。Ctrl+C 停止。

Run（应无测试文件时正常退出）:
```bash
npx tsc --noEmit
```
Expected: 无类型错误。

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "chore: 项目脚手架（Vite+React19+TS+Tailwind4+Vitest+singlefile）"
```

---

## Task 2: 类型定义与 tokens / speed 纯函数（TDD）

**Files:**
- Create: `src/types.ts`, `src/lib/tokens.ts`, `src/lib/tokens.test.ts`, `src/lib/speed.ts`, `src/lib/speed.test.ts`

- [ ] **Step 1: 写 types.ts（无测试，纯类型）**

Create `src/types.ts`:
```ts
export interface Script {
  id: string;
  title: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

export interface TeleprompterSettings {
  fontSize: number;
  letterSpacing: number;
  lineHeight: number;
  scrollSpeed: number;
  mirror: boolean;
}

export type ScrollMode = 'manual' | 'auto';

export const DEFAULT_SETTINGS: TeleprompterSettings = {
  fontSize: 64,
  letterSpacing: 0.05,
  lineHeight: 1.6,
  scrollSpeed: 160,
  mirror: false,
};

export const FONT_SIZE_MIN = 24;
export const FONT_SIZE_MAX = 120;
export const LETTER_SPACING_MIN = 0;
export const LETTER_SPACING_MAX = 0.3;
export const LINE_HEIGHT_MIN = 1.0;
export const LINE_HEIGHT_MAX = 2.5;
```

- [ ] **Step 2: 写 tokens 的失败测试**

Create `src/lib/tokens.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { tokenize, countReadableChars } from './tokens';

describe('tokenize', () => {
  it('把字符串拆成带索引的 token 数组', () => {
    expect(tokenize('ab')).toEqual([
      { id: 0, char: 'a' },
      { id: 1, char: 'b' },
    ]);
  });

  it('保留换行符作为独立 token', () => {
    const tokens = tokenize('a\nb');
    expect(tokens).toHaveLength(3);
    expect(tokens[1]).toEqual({ id: 1, char: '\n' });
  });

  it('用码点拆分，正确处理中文（含 emoji 占多码点）', () => {
    expect(tokenize('你好')).toEqual([
      { id: 0, char: '你' },
      { id: 1, char: '好' },
    ]);
  });

  it('空字符串返回空数组', () => {
    expect(tokenize('')).toEqual([]);
  });
});

describe('countReadableChars', () => {
  it('统计非空白字符数', () => {
    expect(countReadableChars('你 好\n世界')).toBe(4);
  });

  it('空串为 0', () => {
    expect(countReadableChars('')).toBe(0);
  });
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `npx vitest run src/lib/tokens.test.ts`
Expected: FAIL（`tokenize` / `countReadableChars` 未定义）。

- [ ] **Step 4: 实现 tokens.ts**

Create `src/lib/tokens.ts`:
```ts
export interface Token {
  id: number;
  char: string;
}

/** 用 Array.from 按码点拆分，正确处理中文与多码点字符。 */
export function tokenize(content: string): Token[] {
  return Array.from(content).map((char, index) => ({ id: index, char }));
}

/** 非空白字符数，用于预估总时长（排除空格/换行）。 */
export function countReadableChars(content: string): number {
  return Array.from(content).filter((c) => c.trim().length > 0).length;
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `npx vitest run src/lib/tokens.test.ts`
Expected: PASS。

- [ ] **Step 6: 写 speed 的失败测试**

Create `src/lib/speed.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import {
  SPEED_PRESETS,
  SPEED_MIN,
  SPEED_MAX,
  msPerChar,
  estimateDurationSeconds,
  stepAutoAdvance,
} from './speed';

describe('speed 常量', () => {
  it('包含 4 个预设档', () => {
    expect(SPEED_PRESETS.map((p) => p.wpn)).toEqual([80, 160, 240, 320]);
  });
  it('范围 60–360', () => {
    expect(SPEED_MIN).toBe(60);
    expect(SPEED_MAX).toBe(360);
  });
});

describe('msPerChar', () => {
  it('160 WPN → 60000/160 = 375ms', () => {
    expect(msPerChar(160)).toBe(375);
  });
  it('80 WPN → 750ms', () => {
    expect(msPerChar(80)).toBe(750);
  });
  it('非正数返回 Infinity', () => {
    expect(msPerChar(0)).toBe(Infinity);
  });
});

describe('estimateDurationSeconds', () => {
  it('总时长 = 字数 / WPN * 60', () => {
    // 1600 字 @ 160 WPN → 10 分钟 = 600 秒
    expect(estimateDurationSeconds(1600, 160)).toBe(600);
  });
  it('字数为 0 → 0', () => {
    expect(estimateDurationSeconds(0, 160)).toBe(0);
  });
  it('WPN 为 0 → 0', () => {
    expect(estimateDurationSeconds(100, 0)).toBe(0);
  });
});

describe('stepAutoAdvance', () => {
  it('未到每字阈值时不推进，累加 dt', () => {
    // 160 WPN → 375ms/字
    expect(stepAutoAdvance(100, 200, 160)).toEqual({ accumulator: 300, advance: 0 });
  });
  it('累积超过阈值时推进整数字数并保留余数', () => {
    // 累积 400, dt 50 → 450; 450/375 = 1 余 75
    expect(stepAutoAdvance(400, 50, 160)).toEqual({ accumulator: 75, advance: 1 });
  });
  it('可一次推进多字', () => {
    // 累积 0, dt 800 → 800; 800/375 = 2 余 50
    expect(stepAutoAdvance(0, 800, 160)).toEqual({ accumulator: 50, advance: 2 });
  });
});
```

- [ ] **Step 7: 运行测试确认失败**

Run: `npx vitest run src/lib/speed.test.ts`
Expected: FAIL（模块未定义）。

- [ ] **Step 8: 实现 speed.ts**

Create `src/lib/speed.ts`:
```ts
export const SPEED_PRESETS = [
  { id: 'slow', name: '龟速', wpn: 80 },
  { id: 'normal', name: '标准', wpn: 160 },
  { id: 'fast', name: '快语', wpn: 240 },
  { id: 'very-fast', name: '极速', wpn: 320 },
] as const;

export const SPEED_MIN = 60;
export const SPEED_MAX = 360;

/** 每推进一个字符需要的毫秒数。 */
export function msPerChar(wpn: number): number {
  if (wpn <= 0) return Infinity;
  return 60000 / wpn;
}

/** 预估总时长（秒）= 可读字数 / WPN * 60。 */
export function estimateDurationSeconds(charCount: number, wpn: number): number {
  if (wpn <= 0 || charCount <= 0) return 0;
  return (charCount / wpn) * 60;
}

/**
 * 自动推进的单步计算（纯函数）。
 * 给定当前累积量 accumulatorMs 与本帧增量 deltaMs，
 * 返回新的累积量（扣除已消耗）与本帧应推进的字符数。
 */
export function stepAutoAdvance(
  accumulatorMs: number,
  deltaMs: number,
  wpn: number
): { accumulator: number; advance: number } {
  const next = accumulatorMs + deltaMs;
  const mpc = msPerChar(wpn);
  if (mpc === Infinity || next < mpc) return { accumulator: next, advance: 0 };
  const advance = Math.floor(next / mpc);
  return { accumulator: next - advance * mpc, advance };
}
```

- [ ] **Step 9: 运行测试确认通过**

Run: `npx vitest run src/lib/speed.test.ts`
Expected: PASS。

- [ ] **Step 10: 提交**

```bash
git add src/types.ts src/lib/tokens.ts src/lib/tokens.test.ts src/lib/speed.ts src/lib/speed.test.ts
git commit -m "feat: 类型定义与 tokens/speed 纯函数"
```

---

## Task 3: editResolve 与 format 纯函数（TDD）

**Files:**
- Create: `src/lib/editResolve.ts`, `src/lib/editResolve.test.ts`, `src/lib/format.ts`, `src/lib/format.test.ts`

- [ ] **Step 1: 写 editResolve 失败测试**

Create `src/lib/editResolve.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { resolveIndexAfterEdit } from './editResolve';

describe('resolveIndexAfterEdit', () => {
  it('内容在当前位置之前未改 → 保持原位置', () => {
    // old: "abcde", index 3; new: "abcXY" → 前 3 字符 "abc" 一致 → 保持 3
    expect(resolveIndexAfterEdit('abcde', 'abcXY', 3)).toBe(3);
  });

  it('内容在当前位置之前有改动 → 重置 0', () => {
    // old: "abcde", index 3; new: "aXcde" → 前 3 字符 "aXc" != "abc" → 0
    expect(resolveIndexAfterEdit('abcde', 'aXcde', 3)).toBe(0);
  });

  it('新内容短于当前位置 → 重置 0', () => {
    expect(resolveIndexAfterEdit('abcde', 'ab', 3)).toBe(0);
  });

  it('index 为 0 → 总是 0', () => {
    expect(resolveIndexAfterEdit('abcde', 'XYZ', 0)).toBe(0);
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/lib/editResolve.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 editResolve.ts**

Create `src/lib/editResolve.ts`:
```ts
/**
 * 编辑文案后，决定提词器当前阅读位置如何调整。
 * - 若当前位置之前的内容（前 index 字符）未变 → 保持原 index
 * - 否则（前缀改动，或新内容短于 index）→ 重置到 0（开头）
 */
export function resolveIndexAfterEdit(
  oldContent: string,
  newContent: string,
  oldIndex: number
): number {
  if (oldIndex <= 0) return 0;
  if (newContent.length <= oldIndex) return 0;
  const oldPrefix = oldContent.slice(0, oldIndex);
  const newPrefix = newContent.slice(0, oldIndex);
  return oldPrefix === newPrefix ? oldIndex : 0;
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/lib/editResolve.test.ts`
Expected: PASS。

- [ ] **Step 5: 写 format 失败测试**

Create `src/lib/format.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { formatTime } from './format';

describe('formatTime', () => {
  it('0 秒 → 00:00', () => {
    expect(formatTime(0)).toBe('00:00');
  });
  it('32 秒 → 00:32', () => {
    expect(formatTime(32)).toBe('00:32');
  });
  it('135 秒 → 02:15', () => {
    expect(formatTime(135)).toBe('02:15');
  });
  it('取整（向下）', () => {
    expect(formatTime(32.9)).toBe('00:32');
  });
  it('负数当作 0', () => {
    expect(formatTime(-5)).toBe('00:00');
  });
});
```

- [ ] **Step 6: 运行确认失败**

Run: `npx vitest run src/lib/format.test.ts`
Expected: FAIL。

- [ ] **Step 7: 实现 format.ts**

Create `src/lib/format.ts`:
```ts
/** 秒数 → mm:ss 字符串（向下取整，负数当 0）。 */
export function formatTime(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds));
  const mm = Math.floor(s / 60);
  const ss = s % 60;
  return `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}`;
}
```

- [ ] **Step 8: 运行确认通过**

Run: `npx vitest run src/lib/format.test.ts`
Expected: PASS。

- [ ] **Step 9: 提交**

```bash
git add src/lib/editResolve.ts src/lib/editResolve.test.ts src/lib/format.ts src/lib/format.test.ts
git commit -m "feat: 编辑返回定位解析与时间格式化"
```

---

## Task 4: storage 层（TDD）

**Files:**
- Create: `src/store/storage.ts`, `src/store/storage.test.ts`

- [ ] **Step 1: 写失败测试**

Create `src/store/storage.test.ts`:
```ts
import { describe, it, expect, beforeEach } from 'vitest';
import { loadScripts, saveScripts, loadSettings, saveSettings, SCRIPTS_KEY, SETTINGS_KEY } from './storage';
import { DEFAULT_SETTINGS } from '../types';

beforeEach(() => localStorage.clear());

describe('scripts 存储', () => {
  it('无数据时返回空数组', () => {
    expect(loadScripts()).toEqual([]);
  });

  it('保存后可读回', () => {
    const data = [{ id: '1', title: 't', content: 'c', createdAt: 1, updatedAt: 1 }];
    saveScripts(data);
    expect(loadScripts()).toEqual(data);
  });

  it('JSON 损坏时回退空数组', () => {
    localStorage.setItem(SCRIPTS_KEY, '{not json');
    expect(loadScripts()).toEqual([]);
  });

  it('解析为非数组时回退空数组', () => {
    localStorage.setItem(SCRIPTS_KEY, '{"a":1}');
    expect(loadScripts()).toEqual([]);
  });
});

describe('settings 存储', () => {
  it('无数据时返回默认设置', () => {
    expect(loadSettings()).toEqual(DEFAULT_SETTINGS);
  });

  it('保存后读回并合并默认值（缺字段补默认）', () => {
    saveSettings({ ...DEFAULT_SETTINGS, fontSize: 100 });
    const loaded = loadSettings();
    expect(loaded.fontSize).toBe(100);
    expect(loaded.scrollSpeed).toBe(DEFAULT_SETTINGS.scrollSpeed);
  });

  it('JSON 损坏时回退默认设置', () => {
    localStorage.setItem(SETTINGS_KEY, 'broken');
    expect(loadSettings()).toEqual(DEFAULT_SETTINGS);
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/store/storage.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 storage.ts**

Create `src/store/storage.ts`:
```ts
import { Script, TeleprompterSettings, DEFAULT_SETTINGS } from '../types';

export const SCRIPTS_KEY = 'prompter_scripts';
export const SETTINGS_KEY = 'prompter_settings';

export function loadScripts(): Script[] {
  try {
    const raw = localStorage.getItem(SCRIPTS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as Script[]) : [];
  } catch {
    return [];
  }
}

export function saveScripts(scripts: Script[]): void {
  localStorage.setItem(SCRIPTS_KEY, JSON.stringify(scripts));
}

export function loadSettings(): TeleprompterSettings {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return { ...DEFAULT_SETTINGS };
    const parsed = JSON.parse(raw);
    return { ...DEFAULT_SETTINGS, ...(parsed as Partial<TeleprompterSettings>) };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettings(settings: TeleprompterSettings): void {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/store/storage.test.ts`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/store/storage.ts src/store/storage.test.ts
git commit -m "feat: localStorage 存储层（含容错）"
```

---

## Task 5: useDebouncedCallback hook（TDD）

**Files:**
- Create: `src/hooks/useDebouncedCallback.ts`, `src/hooks/useDebouncedCallback.test.ts`

- [ ] **Step 1: 写失败测试**

Create `src/hooks/useDebouncedCallback.test.ts`:
```ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useDebouncedCallback } from './useDebouncedCallback';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('useDebouncedCallback', () => {
  it('在窗口内多次调用只触发一次（最后一次）', () => {
    const fn = vi.fn();
    const { result } = renderHook(() => useDebouncedCallback(fn, 500));

    act(() => {
      result.current('a');
      result.current('b');
      result.current('c');
    });
    expect(fn).not.toHaveBeenCalled();

    act(() => {
      vi.advanceTimersByTime(500);
    });
    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn).toHaveBeenCalledWith('c');
  });

  it('组件卸载时取消未触发的调用', () => {
    const fn = vi.fn();
    const { result, unmount } = renderHook(() => useDebouncedCallback(fn, 500));
    act(() => result.current('x'));
    unmount();
    act(() => vi.advanceTimersByTime(500));
    expect(fn).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/hooks/useDebouncedCallback.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现**

Create `src/hooks/useDebouncedCallback.ts`:
```ts
import { useCallback, useEffect, useRef } from 'react';

/** 返回一个防抖后的回调：停止调用 delay ms 后才真正执行最后一次。 */
export function useDebouncedCallback<T extends (...args: any[]) => void>(
  callback: T,
  delay: number
): T {
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  return useCallback(
    (...args: Parameters<T>) => {
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => callbackRef.current(...args), delay);
    },
    [delay]
  ) as T;
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/hooks/useDebouncedCallback.test.ts`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/hooks/useDebouncedCallback.ts src/hooks/useDebouncedCallback.test.ts
git commit -m "feat: useDebouncedCallback 防抖 hook"
```

---

## Task 6: useScripts 与 useSettings hooks（TDD）

**Files:**
- Create: `src/store/useScripts.ts`, `src/store/useScripts.test.ts`, `src/store/useSettings.ts`, `src/store/useSettings.test.ts`

- [ ] **Step 1: 写 useScripts 失败测试**

Create `src/store/useScripts.test.ts`:
```ts
import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useScripts } from './useScripts';

beforeEach(() => localStorage.clear());

describe('useScripts', () => {
  it('初始为空，addScript 后新增一篇并持久化', () => {
    const { result } = renderHook(() => useScripts());
    expect(result.current.scripts).toEqual([]);
    act(() => result.current.addScript());
    expect(result.current.scripts).toHaveLength(1);
    expect(result.current.scripts[0].title).toBe('未命名稿件');
    // 持久化
    const stored = JSON.parse(localStorage.getItem('prompter_scripts')!);
    expect(stored).toHaveLength(1);
  });

  it('updateContent 更新正文与 updatedAt', () => {
    const { result } = renderHook(() => useScripts());
    act(() => result.current.addScript());
    const id = result.current.scripts[0].id;
    act(() => result.current.updateContent(id, '新内容'));
    expect(result.current.scripts[0].content).toBe('新内容');
  });

  it('updateScript 更新标题与正文', () => {
    const { result } = renderHook(() => useScripts());
    act(() => result.current.addScript());
    const id = result.current.scripts[0].id;
    act(() => result.current.updateScript(id, '标题', '正文'));
    const s = result.current.scripts[0];
    expect(s.title).toBe('标题');
    expect(s.content).toBe('正文');
  });

  it('deleteScript 删除指定稿件', () => {
    const { result } = renderHook(() => useScripts());
    act(() => result.current.addScript());
    const id = result.current.scripts[0].id;
    act(() => result.current.deleteScript(id));
    expect(result.current.scripts).toHaveLength(0);
  });

  it('初始读取已持久化的稿件', () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: 'x', title: 't', content: 'c', createdAt: 1, updatedAt: 1 },
    ]));
    const { result } = renderHook(() => useScripts());
    expect(result.current.scripts).toHaveLength(1);
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/store/useScripts.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 useScripts.ts**

Create `src/store/useScripts.ts`:
```ts
import { useCallback, useEffect, useState } from 'react';
import { Script } from '../types';
import { loadScripts, saveScripts } from './storage';

export function useScripts() {
  const [scripts, setScripts] = useState<Script[]>(() => loadScripts());

  useEffect(() => {
    saveScripts(scripts);
  }, [scripts]);

  const addScript = useCallback(() => {
    const now = Date.now();
    const newScript: Script = {
      id: crypto.randomUUID(),
      title: '未命名稿件',
      content: '',
      createdAt: now,
      updatedAt: now,
    };
    setScripts((prev) => [newScript, ...prev]);
    return newScript.id;
  }, []);

  const updateContent = useCallback((id: string, content: string) => {
    setScripts((prev) =>
      prev.map((s) => (s.id === id ? { ...s, content, updatedAt: Date.now() } : s))
    );
  }, []);

  const updateScript = useCallback((id: string, title: string, content: string) => {
    setScripts((prev) =>
      prev.map((s) => (s.id === id ? { ...s, title, content, updatedAt: Date.now() } : s))
    );
  }, []);

  const deleteScript = useCallback((id: string) => {
    setScripts((prev) => prev.filter((s) => s.id !== id));
  }, []);

  return { scripts, addScript, updateContent, updateScript, deleteScript };
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/store/useScripts.test.ts`
Expected: PASS。

- [ ] **Step 5: 写 useSettings 失败测试**

Create `src/store/useSettings.test.ts`:
```ts
import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useSettings } from './useSettings';
import { DEFAULT_SETTINGS } from '../types';

beforeEach(() => localStorage.clear());

describe('useSettings', () => {
  it('初始为默认设置', () => {
    const { result } = renderHook(() => useSettings());
    expect(result.current.settings).toEqual(DEFAULT_SETTINGS);
  });

  it('updateSettings 合并并持久化', () => {
    const { result } = renderHook(() => useSettings());
    act(() => result.current.updateSettings({ fontSize: 100 }));
    expect(result.current.settings.fontSize).toBe(100);
    const stored = JSON.parse(localStorage.getItem('prompter_settings')!);
    expect(stored.fontSize).toBe(100);
  });
});
```

- [ ] **Step 6: 运行确认失败**

Run: `npx vitest run src/store/useSettings.test.ts`
Expected: FAIL。

- [ ] **Step 7: 实现 useSettings.ts**

Create `src/store/useSettings.ts`:
```ts
import { useCallback, useEffect, useState } from 'react';
import { TeleprompterSettings } from '../types';
import { loadSettings, saveSettings } from './storage';

export function useSettings() {
  const [settings, setSettings] = useState<TeleprompterSettings>(() => loadSettings());

  useEffect(() => {
    saveSettings(settings);
  }, [settings]);

  const updateSettings = useCallback((patch: Partial<TeleprompterSettings>) => {
    setSettings((prev) => ({ ...prev, ...patch }));
  }, []);

  return { settings, updateSettings };
}
```

- [ ] **Step 8: 运行确认通过**

Run: `npx vitest run src/store/useSettings.test.ts`
Expected: PASS。

- [ ] **Step 9: 提交**

```bash
git add src/store/useScripts.ts src/store/useScripts.test.ts src/store/useSettings.ts src/store/useSettings.test.ts
git commit -m "feat: useScripts / useSettings 持久化 hooks"
```

---

## Task 7: useTimer hook（TDD）

**Files:**
- Create: `src/hooks/useTimer.ts`, `src/hooks/useTimer.test.ts`

- [ ] **Step 1: 写失败测试**

Create `src/hooks/useTimer.test.ts`:
```ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useTimer } from './useTimer';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('useTimer', () => {
  it('初始 elapsed 为 0', () => {
    const { result } = renderHook(() => useTimer());
    expect(result.current.elapsedSeconds).toBe(0);
  });

  it('start 后随时间累加，stop 后停止', () => {
    const { result } = renderHook(() => useTimer());
    act(() => result.current.start());
    act(() => vi.advanceTimersByTime(3200));
    expect(result.current.elapsedSeconds).toBe(3);
    act(() => result.current.stop());
    act(() => vi.advanceTimersByTime(5000));
    expect(result.current.elapsedSeconds).toBe(3);
  });

  it('reset 归零并停止', () => {
    const { result } = renderHook(() => useTimer());
    act(() => result.current.start());
    act(() => vi.advanceTimersByTime(5000));
    act(() => result.current.reset());
    expect(result.current.elapsedSeconds).toBe(0);
    act(() => vi.advanceTimersByTime(5000));
    expect(result.current.elapsedSeconds).toBe(0);
  });

  it('卸载时清理定时器', () => {
    const { result, unmount } = renderHook(() => useTimer());
    act(() => result.current.start());
    unmount();
    expect(() => act(() => vi.advanceTimersByTime(10000))).not.toThrow();
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/hooks/useTimer.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 useTimer.ts**

Create `src/hooks/useTimer.ts`:
```ts
import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * 墙钟计时器。start 起算、stop 停、reset 归零。
 * elapsedSeconds 每秒更新一次（向下取整显示用）。
 */
export function useTimer() {
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const clear = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
  }, []);

  const start = useCallback(() => {
    clear();
    intervalRef.current = setInterval(() => {
      setElapsedSeconds((s) => s + 1);
    }, 1000);
  }, [clear]);

  const stop = useCallback(() => {
    clear();
  }, [clear]);

  const reset = useCallback(() => {
    clear();
    setElapsedSeconds(0);
  }, [clear]);

  useEffect(() => clear, [clear]);

  return { elapsedSeconds, start, stop, reset };
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/hooks/useTimer.test.ts`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/hooks/useTimer.ts src/hooks/useTimer.test.ts
git commit -m "feat: useTimer 墙钟计时 hook"
```

---

## Task 8: useAutoAdvance hook（TDD）

**Files:**
- Create: `src/hooks/useAutoAdvance.ts`, `src/hooks/useAutoAdvance.test.ts`

- [ ] **Step 1: 写失败测试**

Create `src/hooks/useAutoAdvance.test.ts`:
```ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useAutoAdvance } from './useAutoAdvance';

beforeEach(() => {
  vi.useFakeTimers();
});
afterEach(() => vi.useRealTimers());

describe('useAutoAdvance', () => {
  it('running=false 时不推进', () => {
    const onAdvance = vi.fn();
    const { result } = renderHook(() =>
      useAutoAdvance({ running: false, wpn: 160, enabled: true, onAdvance })
    );
    act(() => vi.advanceTimersByTime(2000));
    expect(onAdvance).not.toHaveBeenCalled();
    expect(result.current).toBe(false); // 无返回值占位，hook 仅副作用
  });

  it('running=true 时按 WPN 推进', () => {
    const onAdvance = vi.fn();
    renderHook(() =>
      useAutoAdvance({ running: true, wpn: 160, enabled: true, onAdvance })
    );
    // 160 WPN → 375ms/字；rAF 在 jsdom 需手动驱动
    // 驱动若干帧累计 ~ 800ms → 应推进约 2 字
    act(() => {
      for (let i = 0; i < 16; i++) {
        // 每帧 50ms
        vi.advanceTimersByTime(50);
      }
    });
    const total = onAdvance.mock.calls.reduce((sum, [n]) => sum + n, 0);
    expect(total).toBeGreaterThanOrEqual(1);
  });

  it('enabled=false 时即使 running 也不推进', () => {
    const onAdvance = vi.fn();
    renderHook(() =>
      useAutoAdvance({ running: true, wpn: 160, enabled: false, onAdvance })
    );
    act(() => {
      for (let i = 0; i < 16; i++) vi.advanceTimersByTime(50);
    });
    expect(onAdvance).not.toHaveBeenCalled();
  });
});
```

> 注：`useAutoAdvance` 依赖 `requestAnimationFrame`。jsdom 默认无 rAF，需在测试里 polyfill（见 Step 3 的 hook 内置降级）或用 `vi.advanceTimersByTime` 驱动。为保持测试稳定，本 hook 内部将 rAF 适配为基于 `performance.now`，并在测试中通过 `vi.advanceTimersByTime` 驱动 `performance.now`（Vitest fake timers 同步推进 performance.now）。

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/hooks/useAutoAdvance.test.ts`
Expected: FAIL（或因 rAF 未定义报错）。

- [ ] **Step 3: 实现 useAutoAdvance.ts**

Create `src/hooks/useAutoAdvance.ts`:
```ts
import { useEffect, useRef } from 'react';
import { stepAutoAdvance } from '../lib/speed';

interface Options {
  running: boolean;
  wpn: number;
  enabled: boolean;
  onAdvance: (chars: number) => void;
}

/**
 * 自动模式：按 WPN 用 requestAnimationFrame 推进字符数。
 * - running 且 enabled 时启动 rAF 循环
 * - 每帧累加 deltaTime，超过 msPerChar 即回调推进
 */
export function useAutoAdvance({ running, wpn, enabled, onAdvance }: Options) {
  const onAdvanceRef = useRef(onAdvance);
  onAdvanceRef.current = onAdvance;

  useEffect(() => {
    if (!running || !enabled) return;

    const raf =
      typeof requestAnimationFrame === 'function'
        ? requestAnimationFrame
        : (cb: FrameRequestCallback) => setTimeout(() => cb(performance.now()), 16) as unknown as number;
    const caf =
      typeof cancelAnimationFrame === 'function'
        ? cancelAnimationFrame
        : (id: number) => clearTimeout(id);

    let accumulator = 0;
    let last = performance.now();
    let id: number;

    const tick = (now: number) => {
      const delta = now - last;
      last = now;
      const { accumulator: nextAcc, advance } = stepAutoAdvance(accumulator, delta, wpn);
      accumulator = nextAcc;
      if (advance > 0) onAdvanceRef.current(advance);
      id = raf(tick);
    };

    id = raf(tick);
    return () => caf(id);
  }, [running, enabled, wpn]);
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/hooks/useAutoAdvance.test.ts`
Expected: PASS。若 jsdom 无 `requestAnimationFrame`，hook 内置 setTimeout 降级可被 `vi.advanceTimersByTime` 驱动。

- [ ] **Step 5: 提交**

```bash
git add src/hooks/useAutoAdvance.ts src/hooks/useAutoAdvance.test.ts
git commit -m "feat: useAutoAdvance 自动推进 hook"
```

---

## Task 9: useSmoothScroll hook

**Files:**
- Create: `src/hooks/useSmoothScroll.ts`

> 滚动跟随依赖真实 DOM 布局（offsetTop / clientHeight）与 rAF，jsdom 中 offsetTop 恒为 0，难以做有意义的断言。本 hook 以"行为正确性"为主，手动验证为主；纯缓动数学已由 Task 2 的 `stepAutoAdvance` 之外不另抽出。这里实现一个稳定的"缓动到目标 scrollTop"函数，并在 Teleprompter 集成时手动验证。

- [ ] **Step 1: 实现 useSmoothScroll.ts**

Create `src/hooks/useSmoothScroll.ts`:
```ts
import { useCallback, useRef } from 'react';

/** 把 element 滚动到容器中线（垂直居中）。用 rAF 缓动，避免瞬移卡顿。 */
export function useSmoothScroll() {
  const rafRef = useRef<number | null>(null);

  const cancel = useCallback(() => {
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
  }, []);

  const scrollIntoContainerCenter = useCallback(
    (container: HTMLElement, target: HTMLElement) => {
      cancel();
      const computeTarget = () =>
        target.offsetTop - container.clientHeight / 2 + target.offsetHeight / 2;

      const animate = () => {
        const goal = computeTarget();
        const current = container.scrollTop;
        const diff = goal - current;
        // 误差小于 1px 视为到位
        if (Math.abs(diff) < 1) {
          container.scrollTop = goal;
          rafRef.current = null;
          return;
        }
        container.scrollTop = current + diff * 0.18; // 缓动系数
        rafRef.current = requestAnimationFrame(animate);
      };
      rafRef.current = requestAnimationFrame(animate);
    },
    [cancel]
  );

  return { scrollIntoContainerCenter, cancel };
}
```

- [ ] **Step 2: 类型检查**

Run: `npx tsc --noEmit`
Expected: 无错误。

- [ ] **Step 3: 提交**

```bash
git add src/hooks/useSmoothScroll.ts
git commit -m "feat: useSmoothScroll 滚动缓动 hook"
```

---

## Task 10: ScriptText 组件（逐字三态高亮）

**Files:**
- Create: `src/components/ScriptText.tsx`, `src/components/ScriptText.test.tsx`

- [ ] **Step 1: 写失败测试**

Create `src/components/ScriptText.test.tsx`:
```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ScriptText } from './ScriptText';

describe('ScriptText', () => {
  it('按字符渲染，换行渲染为换行', () => {
    const { container } = render(
      <ScriptText content={'ab\nc'} currentIndex={0} onTokenClick={() => {}} />
    );
    const spans = container.querySelectorAll('span[data-idx]');
    expect(spans).toHaveLength(4); // a, b, \n, c
    expect(container.querySelectorAll('br')).toHaveLength(1);
  });

  it('当前字标记 data-state="current"，已读 "read"，未读 "unread"', () => {
    const { container } = render(
      <ScriptText content={'abcde'} currentIndex={2} onTokenClick={() => {}} />
    );
    const states = Array.from(container.querySelectorAll('span[data-idx]')).map((s) =>
      s.getAttribute('data-state')
    );
    expect(states).toEqual(['read', 'read', 'current', 'unread', 'unread']);
  });

  it('点击字符回调其 index', () => {
    const onClick = vi.fn();
    const { container } = render(
      <ScriptText content={'abc'} currentIndex={0} onTokenClick={onClick} />
    );
    (container.querySelector('span[data-idx="2"]') as HTMLElement).click();
    expect(onClick).toHaveBeenCalledWith(2);
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/components/ScriptText.test.tsx`
Expected: FAIL。

- [ ] **Step 3: 实现 ScriptText.tsx**

Create `src/components/ScriptText.tsx`:
```tsx
import { memo } from 'react';
import { tokenize } from '../lib/tokens';

interface Props {
  content: string;
  currentIndex: number;
  onTokenClick: (index: number) => void;
}

function stateOf(index: number, currentIndex: number): 'read' | 'current' | 'unread' {
  if (index < currentIndex) return 'read';
  if (index === currentIndex) return 'current';
  return 'unread';
}

export const ScriptText = memo(function ScriptText({ content, currentIndex, onTokenClick }: Props) {
  const tokens = tokenize(content);
  return (
    <>
      {tokens.map((t) => {
        if (t.char === '\n') return <br key={t.id} />;
        return (
          <span
            key={t.id}
            data-idx={t.id}
            data-state={stateOf(t.id, currentIndex)}
            onClick={() => onTokenClick(t.id)}
            className="word"
          >
            {t.char}
          </span>
        );
      })}
    </>
  );
});
```

- [ ] **Step 4: 在 index.css 追加三态样式**

Append to `src/index.css`:
```css
.word {
  display: inline-block;
  transition: color 0.25s ease, transform 0.25s ease;
  cursor: pointer;
  border-radius: 4px;
  padding: 0 1px;
}
.word[data-state='read'] {
  color: #525252; /* neutral-600 */
}
.word[data-state='current'] {
  color: #eab308; /* yellow-500 */
  font-weight: 800;
  transform: scale(1.08);
}
.word[data-state='unread'] {
  color: #a3a3a3; /* neutral-400 */
}
```

- [ ] **Step 5: 运行确认通过**

Run: `npx vitest run src/components/ScriptText.test.tsx`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add src/components/ScriptText.tsx src/components/ScriptText.test.tsx src/index.css
git commit -m "feat: ScriptText 逐字三态高亮组件"
```

---

## Task 11: Controls 组件（底部胶囊控制条）

**Files:**
- Create: `src/components/Controls.tsx`, `src/components/Controls.test.tsx`

- [ ] **Step 1: 写失败测试**

Create `src/components/Controls.test.tsx`:
```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { Controls } from './Controls';

const baseProps = {
  mode: 'manual' as const,
  isPlaying: false,
  wpn: 160,
  onSetMode: vi.fn(),
  onTogglePlay: vi.fn(),
  onJump: vi.fn(),
};

describe('Controls', () => {
  it('点手动模式按钮调用 onSetMode("manual")', () => {
    const onSetMode = vi.fn();
    render(<Controls {...baseProps} onSetMode={onSetMode} />);
    fireEvent.click(screen.getByTitle('手动模式'));
    expect(onSetMode).toHaveBeenCalledWith('manual');
  });

  it('点播放按钮调用 onTogglePlay', () => {
    const onTogglePlay = vi.fn();
    render(<Controls {...baseProps} onTogglePlay={onTogglePlay} />);
    fireEvent.click(screen.getByTitle('播放'));
    expect(onTogglePlay).toHaveBeenCalled();
  });

  it('快进/后退调用 onJump(+20 / -20)', () => {
    const onJump = vi.fn();
    render(<Controls {...baseProps} onJump={onJump} />);
    fireEvent.click(screen.getByTitle('后退'));
    fireEvent.click(screen.getByTitle('快进'));
    expect(onJump).toHaveBeenNthCalledWith(1, -20);
    expect(onJump).toHaveBeenNthCalledWith(2, 20);
  });

  it('速度档仅在 auto 模式显示', () => {
    const { rerender } = render(<Controls {...baseProps} mode="manual" />);
    expect(screen.queryByTitle('速度')).toBeNull();
    rerender(<Controls {...baseProps} mode="auto" />);
    expect(screen.getByText(/160/)).toBeInTheDocument();
  });

  it('播放中按钮标题为"暂停"', () => {
    render(<Controls {...baseProps} isPlaying mode="manual" />);
    expect(screen.getByTitle('暂停')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/components/Controls.test.tsx`
Expected: FAIL。

- [ ] **Step 3: 实现 Controls.tsx**

Create `src/components/Controls.tsx`:
```tsx
import { MousePointer2, Clock, Play, Pause, Rewind, FastForward } from 'lucide-react';
import { ScrollMode } from '../types';

interface Props {
  mode: ScrollMode;
  isPlaying: boolean;
  wpn: number;
  onSetMode: (mode: ScrollMode) => void;
  onTogglePlay: () => void;
  onJump: (delta: number) => void;
}

export function Controls({ mode, isPlaying, wpn, onSetMode, onTogglePlay, onJump }: Props) {
  return (
    <div className="absolute bottom-4 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-neutral-800 bg-neutral-900/85 p-2 shadow-2xl backdrop-blur-xl">
      {/* 模式 */}
      <div className="flex items-center gap-1 px-2">
        <button
          title="手动模式"
          onClick={() => onSetMode('manual')}
          className={`rounded-full p-2 transition-all ${
            mode === 'manual' ? 'bg-yellow-500 text-black' : 'text-neutral-500 hover:text-white'
          }`}
        >
          <MousePointer2 size={18} />
        </button>
        <button
          title="自动模式"
          onClick={() => onSetMode('auto')}
          className={`rounded-full p-2 transition-all ${
            mode === 'auto' ? 'bg-yellow-500 text-black' : 'text-neutral-500 hover:text-white'
          }`}
        >
          <Clock size={18} />
        </button>
      </div>

      {/* 播放控制 */}
      <div className="flex items-center gap-1 border-l border-neutral-800 px-2">
        <button
          title="后退"
          onClick={() => onJump(-20)}
          className="rounded-full p-2 text-neutral-500 transition-all hover:text-white"
        >
          <Rewind size={18} />
        </button>
        <button
          title={isPlaying ? '暂停' : '播放'}
          onClick={onTogglePlay}
          className={`rounded-full p-3 transition-all ${
            isPlaying
              ? 'bg-yellow-500/10 text-yellow-500'
              : 'bg-yellow-500 text-black shadow-[0_0_15px_rgba(234,179,8,0.4)]'
          }`}
        >
          {isPlaying ? <Pause size={22} /> : <Play size={22} fill="currentColor" />}
        </button>
        <button
          title="快进"
          onClick={() => onJump(20)}
          className="rounded-full p-2 text-neutral-500 transition-all hover:text-white"
        >
          <FastForward size={18} />
        </button>
      </div>

      {/* 速度档：仅 auto 模式 */}
      {mode === 'auto' && (
        <div className="border-l border-neutral-800 px-3">
          <span className="text-[10px] font-bold uppercase tracking-wider text-neutral-400" title="速度">
            {wpn} WPN
          </span>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/components/Controls.test.tsx`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/components/Controls.tsx src/components/Controls.test.tsx
git commit -m "feat: Controls 底部胶囊控制条"
```

---

## Task 12: SettingsPanel 组件（设置抽屉）

**Files:**
- Create: `src/components/SettingsPanel.tsx`, `src/components/SettingsPanel.test.tsx`

- [ ] **Step 1: 写失败测试**

Create `src/components/SettingsPanel.test.tsx`:
```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { SettingsPanel } from './SettingsPanel';
import { DEFAULT_SETTINGS } from '../types';

const baseProps = {
  open: true,
  settings: DEFAULT_SETTINGS,
  onChange: vi.fn(),
  onClose: vi.fn(),
};

describe('SettingsPanel', () => {
  it('open=false 时不渲染', () => {
    const { container } = render(<SettingsPanel {...baseProps} open={false} />);
    expect(container.querySelector('input[type="range"]')).toBeNull();
  });

  it('拖动字号滑块调用 onChange({ fontSize })', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    const sliders = screen.getAllByLabelText('字号');
    fireEvent.change(sliders[0], { target: { value: '90' } });
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ fontSize: 90 }));
  });

  it('镜像开关点击切换', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} onChange={onChange} />);
    fireEvent.click(screen.getByRole('switch'));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ mirror: true }));
  });

  it('点击预设按钮"标准"设置 scrollSpeed=160', () => {
    const onChange = vi.fn();
    render(<SettingsPanel {...baseProps} settings={{ ...DEFAULT_SETTINGS, scrollSpeed: 80 }} onChange={onChange} />);
    fireEvent.click(screen.getByText('标准'));
    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ scrollSpeed: 160 }));
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/components/SettingsPanel.test.tsx`
Expected: FAIL。

- [ ] **Step 3: 实现 SettingsPanel.tsx**

Create `src/components/SettingsPanel.tsx`:
```tsx
import { Settings, Minimize2, Type, AlignJustify, FlipHorizontal, Gauge, MoveHorizontal } from 'lucide-react';
import { TeleprompterSettings, FONT_SIZE_MIN, FONT_SIZE_MAX, LETTER_SPACING_MIN, LETTER_SPACING_MAX, LINE_HEIGHT_MIN, LINE_HEIGHT_MAX, } from '../types';
import { SPEED_MIN, SPEED_MAX, SPEED_PRESETS } from '../lib/speed';

interface Props {
  open: boolean;
  settings: TeleprompterSettings;
  onChange: (patch: Partial<TeleprompterSettings>) => void;
  onClose: () => void;
}

function Slider({
  label, icon, value, min, max, step, suffix, onChange,
}: {
  label: string;
  icon: React.ReactNode;
  value: number;
  min: number;
  max: number;
  step: number;
  suffix?: string;
  onChange: (v: number) => void;
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-sm">
        <span className="flex items-center gap-2 text-neutral-400">{icon}{label}</span>
        <span className="font-mono text-white">{value}{suffix}</span>
      </div>
      <input
        type="range" aria-label={label}
        min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className="w-full accent-yellow-500"
      />
    </div>
  );
}

export function SettingsPanel({ open, settings, onChange, onClose }: Props) {
  if (!open) return null;
  return (
    <div className="absolute inset-0 z-[70] flex justify-end">
      <div className="absolute inset-0 bg-black/60" onClick={onClose} />
      <div className="relative h-full w-80 max-w-[85vw] overflow-y-auto border-l border-neutral-800 bg-neutral-900 p-6 shadow-2xl">
        <div className="mb-6 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-semibold text-white">
            <Settings size={20} /> 提词设置
          </h2>
          <button onClick={onClose} className="text-neutral-500 hover:text-white" aria-label="关闭设置">
            <Minimize2 size={20} />
          </button>
        </div>

        <div className="space-y-6">
          <Slider label="字号" icon={<Type size={16} />} value={settings.fontSize}
            min={FONT_SIZE_MIN} max={FONT_SIZE_MAX} step={2} suffix="px"
            onChange={(v) => onChange({ fontSize: v })} />
          <Slider label="字间距" icon={<MoveHorizontal size={16} />} value={settings.letterSpacing}
            min={LETTER_SPACING_MIN} max={LETTER_SPACING_MAX} step={0.01} suffix="em"
            onChange={(v) => onChange({ letterSpacing: v })} />
          <Slider label="行距" icon={<AlignJustify size={16} />} value={settings.lineHeight}
            min={LINE_HEIGHT_MIN} max={LINE_HEIGHT_MAX} step={0.1}
            onChange={(v) => onChange({ lineHeight: v })} />
          <Slider label="滚动速度" icon={<Gauge size={16} />} value={settings.scrollSpeed}
            min={SPEED_MIN} max={SPEED_MAX} step={20} suffix=" WPN"
            onChange={(v) => onChange({ scrollSpeed: v })} />
          <div className="flex flex-wrap gap-2">
            {SPEED_PRESETS.map((p) => (
              <button
                key={p.id}
                onClick={() => onChange({ scrollSpeed: p.wpn })}
                className={`rounded-lg px-2.5 py-1 text-xs font-bold transition-colors ${
                  settings.scrollSpeed === p.wpn
                    ? 'bg-yellow-500/15 text-yellow-500'
                    : 'bg-neutral-800 text-neutral-400 hover:text-white'
                }`}
              >
                {p.name}
              </button>
            ))}
          </div>

          <div className="flex items-center justify-between rounded-xl bg-neutral-800 p-4">
            <div className="flex items-center gap-3">
              <FlipHorizontal size={18} className="text-neutral-400" />
              <div>
                <span className="block text-sm text-white">镜像翻转</span>
                <span className="text-[10px] text-neutral-500">用于分光镜反射</span>
              </div>
            </div>
            <button
              role="switch" aria-checked={settings.mirror}
              onClick={() => onChange({ mirror: !settings.mirror })}
              className={`relative h-6 w-12 rounded-full transition-colors ${settings.mirror ? 'bg-yellow-500' : 'bg-neutral-700'}`}
            >
              <span className={`absolute top-1 h-4 w-4 rounded-full bg-white transition-all ${settings.mirror ? 'left-7' : 'left-1'}`} />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/components/SettingsPanel.test.tsx`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/components/SettingsPanel.tsx src/components/SettingsPanel.test.tsx
git commit -m "feat: SettingsPanel 设置抽屉"
```

---

## Task 13: ScriptEditor 组件（自动保存）

**Files:**
- Create: `src/components/ScriptEditor.tsx`, `src/components/ScriptEditor.test.tsx`

- [ ] **Step 1: 写失败测试**

Create `src/components/ScriptEditor.test.tsx`:
```tsx
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, fireEvent, screen, act } from '@testing-library/react';
import { ScriptEditor } from './ScriptEditor';
import { Script } from '../types';

const makeScript = (over: Partial<Script> = {}): Script => ({
  id: '1', title: '原标题', content: '原内容', createdAt: 1, updatedAt: 1, ...over,
});

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('ScriptEditor', () => {
  it('编辑标题 500ms 后触发 onSave（防抖）', () => {
    const onSave = vi.fn();
    render(<ScriptEditor script={makeScript()} onSave={onSave} onBack={() => {}} />);
    const title = screen.getByDisplayValue('原标题');
    fireEvent.change(title, { target: { value: '新标题' } });
    expect(onSave).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '新标题', '原内容');
  });

  it('编辑正文 500ms 后触发 onSave', () => {
    const onSave = vi.fn();
    render(<ScriptEditor script={makeScript()} onSave={onSave} onBack={() => {}} />);
    const content = screen.getByDisplayValue('原内容');
    fireEvent.change(content, { target: { value: '新内容' } });
    act(() => vi.advanceTimersByTime(500));
    expect(onSave).toHaveBeenCalledWith('1', '原标题', '新内容');
  });

  it('返回按钮调用 onBack', () => {
    const onBack = vi.fn();
    render(<ScriptEditor script={makeScript()} onSave={() => {}} onBack={onBack} />);
    fireEvent.click(screen.getByTitle('返回'));
    expect(onBack).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/components/ScriptEditor.test.tsx`
Expected: FAIL。

- [ ] **Step 3: 实现 ScriptEditor.tsx**

Create `src/components/ScriptEditor.tsx`:
```tsx
import { useState } from 'react';
import { ChevronLeft } from 'lucide-react';
import { Script } from '../types';
import { useDebouncedCallback } from '../hooks/useDebouncedCallback';

interface Props {
  script: Script;
  onSave: (id: string, title: string, content: string) => void;
  onBack: () => void;
}

export function ScriptEditor({ script, onSave, onBack }: Props) {
  const [title, setTitle] = useState(script.title);
  const [content, setContent] = useState(script.content);

  const debouncedSave = useDebouncedCallback(
    (t: string, c: string) => onSave(script.id, t, c),
    500
  );

  const onTitleChange = (v: string) => {
    setTitle(v);
    debouncedSave(v, content);
  };
  const onContentChange = (v: string) => {
    setContent(v);
    debouncedSave(title, v);
  };

  return (
    <div className="flex min-h-screen flex-col bg-black">
      <header className="sticky top-0 z-50 flex h-16 items-center justify-between border-b border-neutral-900 bg-black/70 px-4 backdrop-blur-xl">
        <button title="返回" onClick={onBack} className="rounded-full p-2 text-neutral-400 hover:bg-neutral-800 hover:text-white">
          <ChevronLeft size={20} />
        </button>
        <span className="text-[10px] font-mono uppercase tracking-widest text-neutral-500">自动保存</span>
      </header>
      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-4 p-4">
        <input
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
          placeholder="稿件标题"
          className="w-full rounded-xl border border-neutral-800 bg-neutral-900 p-4 text-xl font-bold text-white focus:border-yellow-500/50 focus:outline-none"
        />
        <textarea
          value={content}
          onChange={(e) => onContentChange(e.target.value)}
          placeholder="在此输入或粘贴提词稿件..."
          className="min-h-[60vh] flex-1 resize-none rounded-xl border border-neutral-800 bg-neutral-900 p-6 text-lg leading-relaxed text-neutral-300 focus:border-yellow-500/50 focus:outline-none"
        />
      </main>
    </div>
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/components/ScriptEditor.test.tsx`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/components/ScriptEditor.tsx src/components/ScriptEditor.test.tsx
git commit -m "feat: ScriptEditor 编辑+自动保存"
```

---

## Task 14: ScriptList 组件（列表/搜索/新建/删除）

**Files:**
- Create: `src/components/ScriptList.tsx`, `src/components/ScriptList.test.tsx`

- [ ] **Step 1: 写失败测试**

Create `src/components/ScriptList.test.tsx`:
```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, fireEvent, screen } from '@testing-library/react';
import { ScriptList } from './ScriptList';
import { Script } from '../types';

const scripts: Script[] = [
  { id: '1', title: '视频脚本', content: '今天介绍产品', createdAt: 1, updatedAt: 100 },
  { id: '2', title: '会议发言', content: '各位同事好', createdAt: 1, updatedAt: 200 },
];

describe('ScriptList', () => {
  it('渲染所有稿件标题', () => {
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.getByText('会议发言')).toBeInTheDocument();
  });

  it('搜索过滤（标题）', () => {
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.change(screen.getByPlaceholderText('搜索稿件...'), { target: { value: '视频' } });
    expect(screen.getByText('视频脚本')).toBeInTheDocument();
    expect(screen.queryByText('会议发言')).toBeNull();
  });

  it('新建按钮调用 onCreate', () => {
    const onCreate = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={onCreate} />
    );
    fireEvent.click(screen.getByText('新建稿件'));
    expect(onCreate).toHaveBeenCalled();
  });

  it('卡片点击调用 onOpen', () => {
    const onOpen = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={onOpen} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByText('视频脚本'));
    expect(onOpen).toHaveBeenCalledWith('1');
  });

  it('删除按钮调用 onDelete（含确认）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByTestId('delete-1'));
    fireEvent.click(screen.getByText('确认删除'));
    expect(onDelete).toHaveBeenCalledWith('1');
  });

  it('空状态显示引导', () => {
    render(
      <ScriptList scripts={[]} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    expect(screen.getByText(/新建第一篇/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/components/ScriptList.test.tsx`
Expected: FAIL。

- [ ] **Step 3: 实现 ScriptList.tsx**

Create `src/components/ScriptList.tsx`:
```tsx
import { useState } from 'react';
import { Search, Plus, FileText, Edit3, Trash2, Play, ChevronLeft } from 'lucide-react';
import { Script } from '../types';

interface Props {
  scripts: Script[];
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onCreate: () => void;
}

export function ScriptList({ scripts, onOpen, onEdit, onDelete, onCreate }: Props) {
  const [query, setQuery] = useState('');
  const [confirmId, setConfirmId] = useState<string | null>(null);

  const filtered = scripts.filter(
    (s) =>
      s.title.toLowerCase().includes(query.toLowerCase()) ||
      s.content.toLowerCase().includes(query.toLowerCase())
  );

  return (
    <div className="flex min-h-screen flex-col bg-[#050505] text-white">
      <header className="sticky top-0 z-50 border-b border-neutral-900 bg-black/60 px-4 py-3 backdrop-blur-xl">
        <div className="mx-auto flex max-w-5xl items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-yellow-500 text-black">
            <FileText size={20} />
          </div>
          <h1 className="text-base font-bold">稿件管理</h1>
          <div className="relative ml-auto">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-neutral-600" size={16} />
            <input
              placeholder="搜索稿件..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-40 rounded-full border border-neutral-800 bg-neutral-900 py-2 pl-9 pr-3 text-sm focus:border-yellow-500/50 focus:outline-none sm:w-64"
            />
          </div>
          <button
            onClick={onCreate}
            className="flex items-center gap-2 rounded-full bg-yellow-500 px-4 py-2 text-sm font-bold text-black active:scale-95"
          >
            <Plus size={18} /> 新建稿件
          </button>
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-8">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-24 text-center">
            <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-3xl bg-neutral-900 text-neutral-700">
              <FileText size={32} />
            </div>
            <p className="text-neutral-500">点击右上角"新建稿件"开始创作你的第一篇提词脚本</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            {filtered.map((s) => (
              <div
                key={s.id}
                onClick={() => onOpen(s.id)}
                className="group relative cursor-pointer overflow-hidden rounded-2xl border border-neutral-800/60 bg-neutral-900/40 p-5 transition-all hover:border-yellow-500/30 hover:bg-neutral-900"
              >
                <div className="mb-3 flex items-start justify-between">
                  <div className="rounded-lg bg-neutral-800 p-2 text-neutral-400 group-hover:text-yellow-500">
                    <FileText size={18} />
                  </div>
                  <div className="flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
                    <button
                      onClick={(e) => { e.stopPropagation(); onEdit(s.id); }}
                      className="rounded-lg p-2 text-neutral-400 hover:bg-neutral-800 hover:text-white"
                    >
                      <Edit3 size={16} />
                    </button>
                    <button
                      data-testid={`delete-${s.id}`}
                      onClick={(e) => { e.stopPropagation(); setConfirmId(s.id); }}
                      className="rounded-lg p-2 text-neutral-400 hover:bg-red-500/10 hover:text-red-400"
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                </div>
                <h3 className="mb-1 truncate text-lg font-semibold">{s.title}</h3>
                <p className="mb-3 line-clamp-2 text-sm text-neutral-500">
                  {s.content || <span className="italic text-neutral-700">无内容...</span>}
                </p>
                <div className="flex items-center gap-2 border-t border-neutral-800/50 pt-3 text-[10px] text-neutral-600">
                  {new Date(s.updatedAt).toLocaleDateString()}
                  <span className="ml-auto flex items-center gap-1 text-yellow-500 opacity-0 group-hover:opacity-100">
                    开始提词 <Play size={12} fill="currentColor" />
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* 删除确认 */}
      {confirmId && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/80" onClick={() => setConfirmId(null)} />
          <div className="relative w-full max-w-sm rounded-3xl border border-neutral-800 bg-neutral-900 p-8">
            <h3 className="mb-2 text-xl font-bold">确认删除稿件？</h3>
            <p className="mb-6 text-sm text-neutral-400">此操作不可撤销。</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmId(null)} className="flex-1 rounded-xl bg-neutral-800 py-3 text-sm font-bold">取消</button>
              <button
                onClick={() => { onDelete(confirmId); setConfirmId(null); }}
                className="flex-1 rounded-xl bg-red-500 py-3 text-sm font-bold"
              >确认删除</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/components/ScriptList.test.tsx`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/components/ScriptList.tsx src/components/ScriptList.test.tsx
git commit -m "feat: ScriptList 列表/搜索/新建/删除"
```

---

## Task 15: Teleprompter 主视图组件（整合）

**Files:**
- Create: `src/components/Teleprompter.tsx`

> 本任务整合：ScriptText、Controls、SettingsPanel、计时器、进度条、自动推进、滚动跟随、镜像、手动拖拽、Wake Lock/全屏调用、横屏提示。
> **index 受控**：当前阅读位置由父组件（App）持有并经 `index` / `onIndexChange` 传入，使"编辑后返回定位"可在 App 层用 `resolveIndexAfterEdit` 控制（见 Task 17）。无独立单测（集成逻辑手动验证，各子件已单测）。

- [ ] **Step 1: 实现 Teleprompter.tsx**

Create `src/components/Teleprompter.tsx`:
```tsx
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, Settings, Edit3, Maximize2 } from 'lucide-react';
import { Script, TeleprompterSettings, ScrollMode } from '../types';
import { countReadableChars } from '../lib/tokens';
import { estimateDurationSeconds } from '../lib/speed';
import { formatTime } from '../lib/format';
import { useTimer } from '../hooks/useTimer';
import { useAutoAdvance } from '../hooks/useAutoAdvance';
import { useSmoothScroll } from '../hooks/useSmoothScroll';
import { useWakeLock } from '../hooks/useWakeLock';
import { ScriptText } from './ScriptText';
import { Controls } from './Controls';
import { SettingsPanel } from './SettingsPanel';

interface Props {
  script: Script;
  settings: TeleprompterSettings;
  index: number;
  onIndexChange: (i: number) => void;
  onChangeSettings: (patch: Partial<TeleprompterSettings>) => void;
  onBack: () => void;
  onEdit: () => void;
}

export function Teleprompter({ script, settings, index, onIndexChange, onChangeSettings, onBack, onEdit }: Props) {
  const [mode, setMode] = useState<ScrollMode>('auto');
  const [isPlaying, setIsPlaying] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showLandscapeHint, setShowLandscapeHint] = useState(false);
  const [wakeLockFailed, setWakeLockFailed] = useState(false);

  const containerRef = useRef<HTMLDivElement>(null);
  const charCount = useMemo(() => countReadableChars(script.content), [script.content]);
  const estimatedTotal = estimateDurationSeconds(charCount, settings.scrollSpeed);

  const { elapsedSeconds, start: startTimer, stop: stopTimer } = useTimer();
  const { scrollIntoContainerCenter } = useSmoothScroll();
  const { request, release } = useWakeLock();

  // 字数变化（编辑返回）导致越界时钳制
  useEffect(() => {
    const len = script.content.length;
    if (index > len - 1) onIndexChange(Math.max(0, len - 1));
  }, [script.content.length]); // eslint-disable-line react-hooks/exhaustive-deps

  // 横屏提示：竖屏进入时显示一次
  useEffect(() => {
    const check = () => setShowLandscapeHint(window.innerHeight > window.innerWidth);
    check();
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, []);

  // 当前字变化 → 平滑滚动到中线
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const el = container.querySelector<HTMLElement>(`span[data-idx="${index}"]`);
    if (el) scrollIntoContainerCenter(container, el);
  }, [index, scrollIntoContainerCenter]);

  const advance = useCallback((n: number) => {
    const len = script.content.length;
    const next = Math.min(Math.max(0, index + n), Math.max(0, len - 1));
    if (next >= len - 1 && n > 0) setIsPlaying(false); // 到结尾停止
    if (next !== index) onIndexChange(next);
  }, [index, script.content.length, onIndexChange]);

  // 自动推进：auto 模式 + 播放中
  useAutoAdvance({
    running: mode === 'auto' && isPlaying,
    wpn: settings.scrollSpeed,
    enabled: true,
    onAdvance: advance,
  });

  // 播放/暂停副作用：计时器 + Wake Lock
  useEffect(() => {
    if (isPlaying) {
      startTimer();
      request().catch(() => setWakeLockFailed(true));
    } else {
      stopTimer();
      release();
    }
    return () => release();
  }, [isPlaying]); // eslint-disable-line react-hooks/exhaustive-deps

  const togglePlay = () => setIsPlaying((p) => !p);
  const handleSetMode = (m: ScrollMode) => {
    setMode(m);
    setIsPlaying(false);
  };

  // 进度条跳转
  const seekToFraction = (frac: number) => {
    const len = script.content.length;
    onIndexChange(Math.round(frac * Math.max(0, len - 1)));
  };

  // 手动模式：拖拽自由滚动，松手后高亮离中线最近的字
  const onPointerUp = useCallback(() => {
    if (mode !== 'manual') return;
    const container = containerRef.current;
    if (!container) return;
    const mid = container.scrollTop + container.clientHeight / 2;
    const spans = Array.from(container.querySelectorAll<HTMLElement>('span[data-idx]'));
    let best = 0;
    let bestDist = Infinity;
    for (const s of spans) {
      const center = s.offsetTop + s.offsetHeight / 2;
      const d = Math.abs(center - mid);
      if (d < bestDist) { bestDist = d; best = Number(s.dataset.idx); }
    }
    onIndexChange(best);
  }, [mode, onIndexChange]);

  const enterFullscreen = () => {
    if (document.fullscreenEnabled) document.documentElement.requestFullscreen?.().catch(() => {});
  };

  const progress = script.content.length > 1 ? index / (script.content.length - 1) : 0;

  return (
    <div className="relative h-[100dvh] w-screen overflow-hidden bg-black">
      {/* 顶部栏 */}
      <div className="absolute inset-x-0 top-0 z-50 flex items-center justify-between bg-gradient-to-b from-black/90 to-transparent p-3">
        <div className="flex items-center gap-2">
          <button onClick={onBack} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><ChevronLeft size={18} /></button>
          <div className="flex items-center gap-1.5 rounded-lg border border-neutral-800 bg-neutral-900/60 px-2.5 py-1">
            <span className="h-1.5 w-1.5 rounded-full bg-red-500" style={{ boxShadow: isPlaying ? '0 0 6px #ef4444' : 'none' }} />
            <span className="font-mono text-xs tabular-nums text-neutral-200">{formatTime(elapsedSeconds)}</span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="max-w-[140px] truncate text-[11px] text-neutral-500">{script.title}</span>
          <button onClick={onEdit} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><Edit3 size={18} /></button>
          <button onClick={() => setShowSettings(true)} className="rounded-full bg-neutral-900/60 p-2 text-neutral-400 hover:text-white"><Settings size={18} /></button>
        </div>
      </div>

      {/* 进度条 */}
      <div className="absolute inset-x-4 top-14 z-40 flex items-center gap-2">
        <span className="font-mono text-[9px] tabular-nums text-neutral-600">{formatTime(elapsedSeconds)}</span>
        <input
          type="range" min={0} max={1} step={0.001} value={progress}
          onChange={(e) => seekToFraction(parseFloat(e.target.value))}
          className="h-1 w-full accent-yellow-500"
        />
        <span className="font-mono text-[9px] tabular-nums text-neutral-600">{formatTime(estimatedTotal)}</span>
      </div>

      {/* 阅读线 */}
      <div className="pointer-events-none absolute inset-x-0 top-1/2 z-10 h-px bg-yellow-500/30">
        <span className="absolute left-3 top-1/2 -translate-y-1/2 bg-black px-1.5 text-[8px] uppercase tracking-widest text-yellow-500/50">Reading Area</span>
      </div>

      {/* 阅读区 */}
      <div
        ref={containerRef}
        onPointerUp={onPointerUp}
        className={`h-full w-full overflow-y-auto px-[8%] pb-[18vh] pt-[16vh] ${settings.mirror ? 'mirror-mode' : ''}`}
        style={{
          fontSize: `${settings.fontSize}px`,
          lineHeight: settings.lineHeight,
          letterSpacing: `${settings.letterSpacing}em`,
        }}
      >
        <div className="mx-auto max-w-4xl text-center">
          <ScriptText content={script.content} currentIndex={index} onTokenClick={(i) => onIndexChange(i)} />
        </div>
      </div>

      {/* 控制条 */}
      <Controls
        mode={mode}
        isPlaying={isPlaying}
        wpn={settings.scrollSpeed}
        onSetMode={handleSetMode}
        onTogglePlay={togglePlay}
        onJump={(d) => advance(d)}
      />

      {/* 全屏按钮 */}
      <button onClick={enterFullscreen} className="absolute bottom-5 right-4 z-50 rounded-full border border-neutral-800 bg-neutral-900/80 p-2.5 text-neutral-400 backdrop-blur-xl hover:text-white" title="全屏">
        <Maximize2 size={18} />
      </button>

      {/* 横屏提示 */}
      {showLandscapeHint && (
        <div className="absolute inset-x-0 bottom-24 z-40 mx-auto w-fit rounded-full bg-black/80 px-4 py-2 text-center text-xs text-neutral-300 backdrop-blur">
          建议横放设备以获得最佳提词效果
        </div>
      )}

      {/* Wake Lock 降级提示 */}
      {wakeLockFailed && (
        <div className="absolute inset-x-0 bottom-32 z-40 mx-auto w-fit rounded-full bg-black/80 px-4 py-2 text-center text-xs text-yellow-400/90 backdrop-blur">
          当前设备无法自动保持常亮，请在系统设置中调长自动锁屏
        </div>
      )}

      <SettingsPanel
        open={showSettings}
        settings={settings}
        onChange={onChangeSettings}
        onClose={() => setShowSettings(false)}
      />
    </div>
  );
}
```

> **依赖说明**：本文件引用 `useWakeLock`（Task 16）。若按序执行，先完成 Task 16 再做本任务类型检查；否则临时注释 `useWakeLock` 相关行先通过 `tsc`。

- [ ] **Step 2: 在 index.css 追加镜像样式**

Append to `src/index.css`:
```css
.mirror-mode {
  transform: scaleX(-1);
}
```

- [ ] **Step 3: 类型检查**

Run: `npx tsc --noEmit`
Expected: 无错误。`useWakeLock` 将在 Task 16 创建——若顺序执行先做 Task 16 再回头检查；或临时在本文件顶部注释掉 useWakeLock 引用先通过类型。**推荐：先完成 Task 16（useWakeLock）再做本任务类型检查。**

- [ ] **Step 4: 提交**

```bash
git add src/components/Teleprompter.tsx src/index.css
git commit -m "feat: Teleprompter 主视图整合"
```

---

## Task 16: useWakeLock hook

**Files:**
- Create: `src/hooks/useWakeLock.ts`, `src/hooks/useWakeLock.test.ts`

- [ ] **Step 1: 写失败测试**

Create `src/hooks/useWakeLock.test.ts`:
```ts
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useWakeLock } from './useWakeLock';

type WL = { released: Promise<void>; release: () => Promise<void> };

beforeEach(() => {
  // 默认无 wakeLock
  // @ts-expect-error delete if present
  delete navigator.wakeLock;
});
afterEach(() => vi.restoreAllMocks());

describe('useWakeLock', () => {
  it('不支持时 request 返回的 Promise reject', async () => {
    const { result } = renderHook(() => useWakeLock());
    await expect(result.current.request()).rejects.toBeDefined();
  });

  it('支持时 request 调用 navigator.wakeLock.request', async () => {
    const release = vi.fn().mockResolvedValue(undefined);
    const request = vi.fn().mockResolvedValue({ release } as unknown as WL);
    Object.defineProperty(navigator, 'wakeLock', { value: { request }, configurable: true });
    const { result } = renderHook(() => useWakeLock());
    await act(() => result.current.request());
    expect(request).toHaveBeenCalledWith('screen');
  });

  it('release 幂等（无 active 时不报错）', async () => {
    const { result } = renderHook(() => useWakeLock());
    await expect(result.current.release()).resolves.toBeUndefined();
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/hooks/useWakeLock.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 useWakeLock.ts**

Create `src/hooks/useWakeLock.ts`:
```ts
import { useCallback, useRef } from 'react';

interface WakeLockSentinel {
  released: boolean;
  release: () => Promise<void>;
}
interface NavigatorWakeLock {
  request(type: 'screen'): Promise<WakeLockSentinel>;
}

export function useWakeLock() {
  const sentinelRef = useRef<WakeLockSentinel | null>(null);

  const request = useCallback(async () => {
    const wl = (navigator as unknown as { wakeLock?: NavigatorWakeLock }).wakeLock;
    if (!wl) throw new Error('Wake Lock 不被当前环境支持');
    const sentinel = await wl.request('screen');
    sentinelRef.current = sentinel;
  }, []);

  const release = useCallback(async () => {
    const s = sentinelRef.current;
    sentinelRef.current = null;
    if (s && !s.released) {
      try { await s.release(); } catch { /* 已释放则忽略 */ }
    }
  }, []);

  return { request, release };
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/hooks/useWakeLock.test.ts`
Expected: PASS。

- [ ] **Step 5: 回到 Teleprompter 确认类型**

Run: `npx tsc --noEmit`
Expected: 无错误（Teleprompter 引用的 useWakeLock 现已存在）。

- [ ] **Step 6: 提交**

```bash
git add src/hooks/useWakeLock.ts src/hooks/useWakeLock.test.ts
git commit -m "feat: useWakeLock 屏幕常亮 hook（含降级）"
```

---

## Task 17: App.tsx 视图状态机 + 编辑返回定位

**Files:**
- Modify: `src/App.tsx`
- Create: `src/App.test.tsx`

- [ ] **Step 1: 写失败测试**

Create `src/App.test.tsx`:
```tsx
import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import App from './App';

beforeEach(() => localStorage.clear());

describe('App', () => {
  it('初始显示稿件管理，且为空状态', () => {
    render(<App />);
    expect(screen.getByText(/新建第一篇/)).toBeInTheDocument();
  });

  it('新建稿件 → 进入编辑视图', () => {
    render(<App />);
    fireEvent.click(screen.getByText('新建稿件'));
    // 编辑器正文输入框存在
    expect(screen.getByPlaceholderText('在此输入或粘贴提词稿件...')).toBeInTheDocument();
  });

  it('编辑后返回提词器，若改动跨越位置则重置到开头并提示', async () => {
    render(<App />);
    fireEvent.click(screen.getByText('新建稿件'));
    // 输入正文
    const content = screen.getByPlaceholderText('在此输入或粘贴提词稿件...');
    fireEvent.change(content, { target: { value: '一二三四五' } });
    // 返回列表
    fireEvent.click(screen.getByTitle('返回'));
    // 打开提词器
    await waitFor(() => expect(screen.getByText('未命名稿件')).toBeInTheDocument());
    fireEvent.click(screen.getByText('未命名稿件'));
    // 进入提词器（应能渲染）
    await waitFor(() => expect(screen.getByText('Reading Area')).toBeInTheDocument());
  });
});
```

> 说明：此测试主要验证视图状态机能从 列表 → 编辑 → 列表 → 提词器 正确流转且不崩溃；编辑返回定位的"重置到开头 + 提示"分支依赖具体 index，作为集成行为在手动验证中确认（纯函数 `resolveIndexAfterEdit` 已在 Task 3 单测覆盖）。

- [ ] **Step 2: 运行确认失败**

Run: `npx vitest run src/App.test.tsx`
Expected: FAIL（App 还是脚手架空壳）。

- [ ] **Step 3: 重写 App.tsx**

Modify `src/App.tsx`:
```tsx
import { useState } from 'react';
import { ScriptList } from './components/ScriptList';
import { ScriptEditor } from './components/ScriptEditor';
import { Teleprompter } from './components/Teleprompter';
import { useScripts } from './store/useScripts';
import { useSettings } from './store/useSettings';
import { resolveIndexAfterEdit } from './lib/editResolve';

type View = 'list' | 'prompter' | 'editor';

export default function App() {
  const { scripts, addScript, updateScript, deleteScript } = useScripts();
  const { settings, updateSettings } = useSettings();

  const [view, setView] = useState<View>('list');
  const [activeId, setActiveId] = useState<string | null>(null);
  // 提词器当前阅读位置（受控，供编辑返回定位使用）
  const [prompterIndex, setPrompterIndex] = useState(0);
  // 从提词器进入编辑时的快照
  const [editSnapshot, setEditSnapshot] = useState<{ content: string; index: number } | null>(null);
  const [resetNotice, setResetNotice] = useState(false);

  const active = scripts.find((s) => s.id === activeId) ?? null;

  const openPrompter = (id: string) => {
    setActiveId(id);
    setPrompterIndex(0);
    setEditSnapshot(null);
    setView('prompter');
  };

  const openEditorFromPrompter = () => {
    if (!active) return;
    setEditSnapshot({ content: active.content, index: prompterIndex });
    setView('editor');
  };

  const handleCreate = () => {
    const id = addScript();
    setActiveId(id);
    setEditSnapshot(null);
    setView('editor');
  };

  if (view === 'prompter' && active) {
    return (
      <>
        <Teleprompter
          script={active}
          settings={settings}
          index={prompterIndex}
          onIndexChange={setPrompterIndex}
          onChangeSettings={updateSettings}
          onBack={() => setView('list')}
          onEdit={openEditorFromPrompter}
        />
        {resetNotice && (
          <div className="fixed left-1/2 top-20 z-[120] -translate-x-1/2 rounded-full bg-black/85 px-4 py-2 text-xs text-yellow-400 backdrop-blur">
            文案改动已跨越当前位置，已重置到开头
          </div>
        )}
      </>
    );
  }

  if (view === 'editor' && active) {
    return (
      <ScriptEditor
        script={active}
        onSave={(id, title, content) => {
          updateScript(id, title, content);
          // 从提词器进入编辑的情形：判断返回后定位
          if (editSnapshot) {
            const newIndex = resolveIndexAfterEdit(editSnapshot.content, content, editSnapshot.index);
            if (newIndex === 0 && editSnapshot.index !== 0) {
              setResetNotice(true);
              setTimeout(() => setResetNotice(false), 3000);
            }
            setPrompterIndex(newIndex);
            setEditSnapshot({ content, index: newIndex });
          }
        }}
        onBack={() => setView(editSnapshot ? 'prompter' : 'list')}
      />
    );
  }

  return (
    <ScriptList
      scripts={scripts}
      onOpen={openPrompter}
      onEdit={(id) => { setActiveId(id); setEditSnapshot(null); setView('editor'); }}
      onDelete={deleteScript}
      onCreate={handleCreate}
    />
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run: `npx vitest run src/App.test.tsx`
Expected: PASS。

- [ ] **Step 5: 全量测试**

Run: `npx vitest run`
Expected: 全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add src/App.tsx src/App.test.tsx
git commit -m "feat: App 视图状态机 + 编辑返回定位"
```

---

## Task 18: 移动端体验增强补全（beforeunload + 触控）

**Files:**
- Modify: `src/App.tsx`

- [ ] **Step 1: 在 App.tsx 追加 beforeunload（编辑/提词中防误退出）**

在 `App.tsx` 顶部 `import { useState }` 旁加入 `useEffect`，并在组件内增加：
```tsx
import { useState, useEffect } from 'react';
```
组件内（`return` 之前）追加：
```tsx
  useEffect(() => {
    const handler = (e: BeforeUnloadEvent) => {
      if (view !== 'list') {
        e.preventDefault();
        e.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [view]);
```

- [ ] **Step 2: 触控优化 —— index.css 追加禁用文本选择与触摸滚动优化**

Append to `src/index.css`:
```css
/* 提词器内禁用长按选择文字，避免误触 */
.teleprompter-touch, .teleprompter-touch * {
  -webkit-user-select: none;
  user-select: none;
  -webkit-tap-highlight-color: transparent;
}
/* 播放/暂停等按钮允许点击但不缩放 */
button {
  touch-action: manipulation;
}
```

并在 `Teleprompter.tsx` 阅读区容器 className 加 `teleprompter-touch`：
找到 `className={`h-full w-full overflow-y-auto px-[8%] pb-[18vh] pt-[16vh] ${settings.mirror ? 'mirror-mode' : ''}`}`
改为：
```tsx
className={`teleprompter-touch h-full w-full overflow-y-auto px-[8%] pb-[18vh] pt-[16vh] ${settings.mirror ? 'mirror-mode' : ''}`}
```

- [ ] **Step 3: 类型检查 + 全量测试**

Run: `npx tsc --noEmit && npx vitest run`
Expected: 无类型错误，全部测试 PASS。

- [ ] **Step 4: 提交**

```bash
git add src/App.tsx src/index.css src/components/Teleprompter.tsx
git commit -m "feat: 移动端体验增强（防误退出 + 触控优化）"
```

---

## Task 19: 构建验证 —— 产出单 HTML

**Files:**
- 无新建（验证 `dist/index.html`）

- [ ] **Step 1: 构建**

Run: `npm run build`
Expected: Vite 构建成功，`dist/` 下生成单个 `index.html`（JS/CSS 已内联，无独立 chunk / css 文件）。

- [ ] **Step 2: 验证产物为单文件**

Run:
```bash
ls -la dist/ && echo "---html 体积---" && du -h dist/index.html
```
Expected: `dist/` 仅含 `index.html`（可能含 vite.svg，无 .js/.css 外链）。`index.html` 内部已内联 `<script>` 与 `<style>`。

验证内联：
```bash
grep -c "src=\"/" dist/index.html
```
Expected: `0`（没有外部 src 引用）。若不为 0，检查 `vite-plugin-singlefile` 是否生效。

- [ ] **Step 3: 手动验证（核心功能走查）**

打开 `dist/index.html`（用 Chrome）：
1. 列表页空状态 → 点"新建稿件" → 进入编辑
2. 输入一段中文正文（如 100 字）→ 自动保存 → 返回列表能看到该稿
3. 点稿件进入提词器 → 自动模式播放 → 文字逐字高亮、滚动、当前字停在中线
4. 调速度（设置面板）→ 滚动快慢变化、进度条右端预估时长变化
5. 调字号/字间距/行距 → 实时变化
6. 切手动模式 → 手指拖拽自由滚动，松手高亮离中线最近的字
7. 点字符跳转
8. 进度条拖拽跳转
9. 镜像翻转 → 文字水平镜像
10. 横放窗口/设备 → 布局自适应
11. 点全屏按钮 → 进入全屏
12. 关闭刷新 → 稿件与设置仍在（localStorage）

- [ ] **Step 4: 把 dist/index.html 作为最终产物复制到项目根（可选交付物）**

Run:
```bash
cp dist/index.html ./teleprompter.html
```
Expected: 项目根生成 `teleprompter.html`，可直接发给别人用浏览器打开。

- [ ] **Step 5: 确认 .gitignore（忽略 dist，保留 teleprompter.html 产物）**

脚手架阶段的 `.gitignore` 已含 `dist/`、`node_modules/`、`.superpowers/`、`ref_code/` 等（设计文档阶段已创建）。确认其包含：
```
dist/
```
且**未**忽略 `teleprompter.html`（作为交付物纳入版本控制）。若已满足则无需改动。

- [ ] **Step 6: 提交**

```bash
git add .gitignore teleprompter.html
git commit -m "build: 构建验证并产出单 HTML（teleprompter.html）"
```

---

## 完成标准

- `npx vitest run` 全绿
- `npx tsc --noEmit` 无错误
- `npm run build` 产出单 `dist/index.html`（无外链 JS/CSS）
- 手动走查 Task 19 Step 3 全部 12 项通过
- 交付物 `teleprompter.html` 可在 Chrome 直接打开使用
