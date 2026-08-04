# 稿件列表交互优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化稿件列表 4 项交互——点击卡片进入、读完自动返回并标记已拍摄、修复滑动文字与背景区重叠、左滑两阶段直接删除并配视觉震动。

**Architecture:** 新建独立 `useFilmed` store hook 管理「已拍摄」状态（仿 useScripts/useSettings 模式），提升至 App 层供 ScriptList 与 Teleprompter 共享；Teleprompter 在 `onReachEnd` 触发完成态（提示 1.2s → 自动返回 + 标记）；ScriptList 滑动逻辑改为两阶段距离判定 + 内容层不透明背景修复重叠。

**Tech Stack:** React 19、TypeScript、Vite、Vitest + @testing-library/react、Tailwind v4、localStorage 持久化。

## Global Constraints

- 目标平台：iOS Safari + Android Chrome 的移动端 PWA。**禁止使用 `navigator.vibrate`**（iOS 不支持），震动反馈一律用 CSS。
- localStorage key `prompter_filmed` 复用现有格式（`JSON.stringify([...Set])`），**向后兼容** ScriptList 当前写入的数据，零迁移。
- 「已拍摄」状态独立于 Script 模型——**不修改 [src/types.ts](src/types.ts) 的 Script 接口**。
- 测试基础设施：Vitest + jsdom + @testing-library/react；hook 用 `renderHook`/`act`，组件用 `render`/`fireEvent`/`screen`；`beforeEach(() => localStorage.clear())`。
- commit message 英文，结尾加 `Co-Authored-By: Claude <noreply@anthropic.com>`。
- 不在 `main` 分支直接提交实现——执行时先开分支。

## 任务依赖与执行顺序

```
Task 1 (useFilmed) ─┬─→ Task 4 (状态提升: ScriptList 受控 + App 接入) ─→ Task 5 (读完回流: Teleprompter + App 接线)
                    │
Task 2 (滑动重叠) ──┤   （都改 ScriptList.tsx，必须串行）
Task 3 (两阶段删除)─┘
```

推荐线性顺序：**Task 1 → 2 → 3 → 4 → 5**（Task 2/3/4 同改 ScriptList.tsx，串行避免冲突）。

---

## Task 1: useFilmed store hook

**Files:**
- Create: `src/store/useFilmed.ts`
- Test: `src/store/useFilmed.test.ts`

**Interfaces:**
- Consumes: 无（独立 store）
- Produces:
  - `useFilmed(): { filmedIds: Set<string>; isFilmed(id: string): boolean; markFilmed(id: string): void; toggleFilmed(id: string): void; clearStale(validIds: string[]): void }`
  - 被 Task 4（App 接入）、Task 5（markFilmed）消费

- [ ] **Step 1: 写失败测试 `src/store/useFilmed.test.ts`**

```ts
import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useFilmed } from './useFilmed';

beforeEach(() => localStorage.clear());

describe('useFilmed', () => {
  it('初始为空', () => {
    const { result } = renderHook(() => useFilmed());
    expect(result.current.filmedIds.size).toBe(0);
    expect(result.current.isFilmed('x')).toBe(false);
  });

  it('向后兼容：读取已有 prompter_filmed', () => {
    localStorage.setItem('prompter_filmed', JSON.stringify(['a', 'b']));
    const { result } = renderHook(() => useFilmed());
    expect(result.current.isFilmed('a')).toBe(true);
    expect(result.current.isFilmed('b')).toBe(true);
  });

  it('markFilmed 只增并持久化', () => {
    const { result } = renderHook(() => useFilmed());
    act(() => result.current.markFilmed('a'));
    expect(result.current.isFilmed('a')).toBe(true);
    act(() => result.current.markFilmed('a')); // 幂等
    expect(result.current.filmedIds.size).toBe(1);
    expect(JSON.parse(localStorage.getItem('prompter_filmed')!)).toEqual(['a']);
  });

  it('toggleFilmed 切换', () => {
    const { result } = renderHook(() => useFilmed());
    act(() => result.current.toggleFilmed('a'));
    expect(result.current.isFilmed('a')).toBe(true);
    act(() => result.current.toggleFilmed('a'));
    expect(result.current.isFilmed('a')).toBe(false);
  });

  it('clearStale 移除无效 id 并持久化', () => {
    localStorage.setItem('prompter_filmed', JSON.stringify(['a', 'b', 'c']));
    const { result } = renderHook(() => useFilmed());
    act(() => result.current.clearStale(['a', 'c'])); // b 已被删除
    expect(result.current.isFilmed('a')).toBe(true);
    expect(result.current.isFilmed('b')).toBe(false);
    expect(result.current.isFilmed('c')).toBe(true);
    expect(JSON.parse(localStorage.getItem('prompter_filmed')!)).toEqual(['a', 'c']);
  });
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npx vitest run src/store/useFilmed.test.ts`
Expected: FAIL（`Cannot find module './useFilmed'`）

- [ ] **Step 3: 写实现 `src/store/useFilmed.ts`**

```ts
import { useCallback, useState } from 'react';

const FILMED_KEY = 'prompter_filmed';

function loadFilmed(): Set<string> {
  try {
    const raw = localStorage.getItem(FILMED_KEY);
    return new Set(raw ? JSON.parse(raw) : []);
  } catch {
    return new Set();
  }
}

export function useFilmed() {
  const [filmedIds, setFilmedIds] = useState<Set<string>>(() => loadFilmed());

  const persist = (next: Set<string>) => {
    try {
      localStorage.setItem(FILMED_KEY, JSON.stringify([...next]));
    } catch {
      /* noop */
    }
  };

  const markFilmed = useCallback((id: string) => {
    setFilmedIds((prev) => {
      if (prev.has(id)) return prev;
      const next = new Set(prev);
      next.add(id);
      persist(next);
      return next;
    });
  }, []);

  const toggleFilmed = useCallback((id: string) => {
    setFilmedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      persist(next);
      return next;
    });
  }, []);

  const clearStale = useCallback((validIds: string[]) => {
    const valid = new Set(validIds);
    setFilmedIds((prev) => {
      let changed = false;
      const next = new Set<string>();
      for (const id of prev) {
        if (valid.has(id)) next.add(id);
        else changed = true;
      }
      if (!changed) return prev;
      persist(next);
      return next;
    });
  }, []);

  const isFilmed = useCallback((id: string) => filmedIds.has(id), [filmedIds]);

  return { filmedIds, isFilmed, markFilmed, toggleFilmed, clearStale };
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `npx vitest run src/store/useFilmed.test.ts`
Expected: PASS（5 个用例全绿）

- [ ] **Step 5: 提交**

```bash
git add src/store/useFilmed.ts src/store/useFilmed.test.ts
git commit -m "feat: add useFilmed store hook for filmed-state management

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: 修复滑动文字与背景区重叠

**Files:**
- Modify: `src/components/ScriptList.tsx`（内容层 div，约 L286-297）
- Test: `src/components/ScriptList.test.tsx`（新增用例）

**Interfaces:**
- Consumes: 无新接口
- Produces: 内容层 `data-testid="content-{id}"`，供后续任务的滑动测试定位（Task 3/4 复用）

**根因**：内容层（`<div className="relative p-4">`）无背景，glass-card 半透明（`rgba(19,19,22,0.7)`）。滑动中 |offset| < 72 时内容层仍覆盖绿/红背景层上方，透明 → 文字与背景重叠。

- [ ] **Step 1: 写失败测试（追加到 `src/components/ScriptList.test.tsx` 末尾 `describe` 内）**

```ts
  it('滑动中内容层不透明背景（修复重叠），静止时透明', () => {
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    const contentLayer = screen.getByTestId('content-1');
    // 静止：无内联背景
    expect(contentLayer.style.background).toBe('');
    // 模拟左滑（dx = 50 → 10 = -40）
    const card = contentLayer.parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 50, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 10, clientY: 50 }] });
    expect(contentLayer.style.background).not.toBe('');
  });
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npx vitest run src/components/ScriptList.test.tsx -t "滑动中内容层不透明背景"`
Expected: FAIL（找不到 `data-testid="content-1"`）

- [ ] **Step 3: 给内容层加 testid + 滑动时切换不透明背景**

在 `src/components/ScriptList.tsx` 定位内容层（`className="relative p-4"` 的 div，其 style 含 `transform: translateX(${swipeX}px)`），改为：

```tsx
                  {/* Card content — slides on swipe */}
                  <div
                    data-testid={`content-${s.id}`}
                    className="relative p-4"
                    style={{
                      transform: `translateX(${swipeX}px)`,
                      background: swipeX !== 0 ? '#131316' : undefined,
                      transition: swipingId.current === s.id ? 'none' : 'transform 0.25s ease-out',
                    }}
                    onClick={() => {
                      if (swipingId.current) return;
                      handleOpen(s.id);
                    }}
                  >
```

> 说明：`#131316` = glass-card 的 RGB(19,19,22)，alpha 改 1。静止时 `undefined` 保留玻璃质感；滑动中变实心滑板，干净遮挡背景层。

- [ ] **Step 4: 运行测试，确认通过**

Run: `npx vitest run src/components/ScriptList.test.tsx`
Expected: PASS（含新用例，且未破坏现有用例）

- [ ] **Step 5: 提交**

```bash
git add src/components/ScriptList.tsx src/components/ScriptList.test.tsx
git commit -m "fix: prevent swipe text/background overlap with opaque content layer

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: 左滑两阶段 + 视觉震动 + 移除单稿删除弹窗

**Files:**
- Modify: `src/components/ScriptList.tsx`（swipe 逻辑 L73-94、卡片外层 className、删除区样式 L279-284、删除按钮 onClick L313-320、移除 confirmId state L37、移除确认弹窗 L361-377、Escape effect L129-134）
- Modify: `src/index.css`（新增 keyframe）
- Test: `src/components/ScriptList.test.tsx`（改现有删除用例 + 新增两阶段用例）

**Interfaces:**
- Consumes: 无
- Produces: `.swipe-shake` CSS class（Task 内消费）；ScriptList props 不变（仍由内部 state 管 filmed，Task 4 再提升）

**阈值**（左负右正）：clamp `[-150, 72]`；阶段2 `≤ -130` 直接删；阶段1 `-130 ~ -40` 回弹；右滑 `> 40` 标记。

- [ ] **Step 1: 改现有"删除按钮含确认"测试 + 新增两阶段测试**

在 `src/components/ScriptList.test.tsx` 中，把现有用例：

```ts
  it('删除按钮调用 onDelete（含确认）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByTestId('delete-1'));
    fireEvent.click(screen.getByText('确认删除'));
    expect(onDelete).toHaveBeenCalledWith('1');
  });
```

替换为：

```ts
  it('删除按钮直接调用 onDelete（无确认弹窗）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    fireEvent.click(screen.getByTestId('delete-1'));
    expect(onDelete).toHaveBeenCalledWith('1');
    expect(screen.queryByText('确认删除')).toBeNull();
  });

  it('左滑越过 -130 松手直接删除（无弹窗）', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 160, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 10, clientY: 50 }] }); // dx = -150
    fireEvent.touchEnd(card);
    expect(onDelete).toHaveBeenCalledWith('1');
    expect(screen.queryByText('确认删除')).toBeNull();
  });

  it('左滑未越过 -130 松手不删除', () => {
    const onDelete = vi.fn();
    render(
      <ScriptList scripts={scripts} onOpen={() => {}} onEdit={() => {}} onDelete={onDelete} onCreate={() => {}} />
    );
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 100, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 30, clientY: 50 }] }); // dx = -70
    fireEvent.touchEnd(card);
    expect(onDelete).not.toHaveBeenCalled();
  });
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npx vitest run src/components/ScriptList.test.tsx`
Expected: FAIL（"删除按钮直接调用"仍出现确认弹窗；两阶段用例未实现）

- [ ] **Step 3: 在 `src/index.css` 的 `.glass-button` 块之后、`prefers-reduced-motion` 块之前，新增 keyframe**

```css
/* Swipe shake — 越过删除阈值时的纯视觉震动反馈（不用 navigator.vibrate，iOS 兼容） */
@keyframes swipe-shake {
  0%, 100% { transform: translateX(0); }
  25% { transform: translateX(-4px); }
  75% { transform: translateX(4px); }
}
.swipe-shake { animation: swipe-shake 0.2s ease-in-out; }
```

- [ ] **Step 4: 改 ScriptList swipe 逻辑与状态**

在 `src/components/ScriptList.tsx`：

**4a. 新增 shake 状态**（在 `swipeOffsets` state 附近）：

```ts
  const [shakeId, setShakeId] = useState<string | null>(null);
  const shookRef = useRef(false);
```

**4b. `handleTouchStart`** 重置守卫（现有函数体内加一行）：

```ts
  const handleTouchStart = useCallback((e: React.TouchEvent, id: string) => {
    touchStartX.current = e.touches[0].clientX;
    touchStartY.current = e.touches[0].clientY;
    swipingId.current = id;
    shookRef.current = false;
  }, []);
```

**4c. `handleTouchMove`** 放宽 clamp + 越过 -130 触发震动：

```ts
  const handleTouchMove = useCallback((e: React.TouchEvent, id: string) => {
    if (swipingId.current !== id) return;
    const dx = e.touches[0].clientX - touchStartX.current;
    const dy = e.touches[0].clientY - touchStartY.current;
    if (Math.abs(dy) > Math.abs(dx)) return;
    const clamped = Math.max(-150, Math.min(72, dx));
    setSwipe(id, clamped);
    if (clamped <= -130 && !shookRef.current) {
      shookRef.current = true;
      setShakeId(id);
    }
  }, [setSwipe]);
```

**4d. `handleTouchEnd`** 两阶段判定，移除 `setConfirmId`：

```ts
  const handleTouchEnd = useCallback((_e: React.TouchEvent, id: string) => {
    if (swipingId.current !== id) { swipingId.current = null; return; }
    swipingId.current = null;
    const offset = swipeRef.current.get(id) || 0;
    if (offset > 40) {
      toggleFilmed(id);
    } else if (offset <= -130) {
      onDelete(id);
    }
    setShakeId(null);
    setSwipe(id, 0);
  }, [setSwipe, toggleFilmed, onDelete]);
```

**4e. 移除 `confirmId` state**（删除 `const [confirmId, setConfirmId] = useState<string | null>(null);`）。

**4f. Escape effect** 收敛条件：

```ts
  useEffect(() => {
    if (!confirmClear) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { setConfirmClear(false); } };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [confirmClear]);
```

- [ ] **Step 5: 改卡片外层 className（加 shake class）**

卡片根 div（含 `onTouchStart` 的 `<div key={s.id} className="group relative overflow-hidden rounded-2xl border ...">`）加 `shakeId === s.id` 时追加 `swipe-shake`，并加 `onAnimationEnd` 清理：

```tsx
                <div
                  key={s.id}
                  className={`group relative overflow-hidden rounded-2xl border transition-colors duration-200 ${isFilmed
                    ? 'border-green-500/15 glass-card bg-green-500/[0.03]'
                    : 'border-[#D4A432]/15 glass-card hover:border-[#D4A432]/50 hover:bg-white/[0.07]'
                  }${shakeId === s.id ? ' swipe-shake' : ''}`}
                  onAnimationEnd={() => setShakeId(null)}
                  onTouchStart={(e) => handleTouchStart(e, s.id)}
                  onTouchMove={(e) => handleTouchMove(e, s.id)}
                  onTouchEnd={(e) => handleTouchEnd(e, s.id)}
                >
```

> 抖动作用于卡片外层（原本无 transform），与内容层的 `translateX(swipeX)` 嵌套叠加，无冲突。

- [ ] **Step 6: 删除区视觉越过阈值时变亮 + 图标放大**

红色背景层 div（`absolute inset-y-0 right-0`，原 `background: swipeX < -20 ? '#DC2626' : ...`）：

```tsx
                  {/* Left swipe (←): red "删除" on the right */}
                  <div className="absolute inset-y-0 right-0 flex w-[72px] items-center justify-center rounded-r-2xl transition-opacity duration-200"
                    style={{
                      background: swipeX < -130 ? '#EF4444' : (swipeX < -20 ? '#DC2626' : 'transparent'),
                      opacity: swipeX < -20 ? 1 : 0,
                    }}
                  >
                    <Trash2 size={20} strokeWidth={2.5} className="text-white transition-transform duration-150"
                      style={{ transform: swipeX < -130 ? 'scale(1.15)' : 'scale(1)' }}
                    />
                  </div>
```

- [ ] **Step 7: 卡片删除按钮直接删除（不弹窗）**

卡片内删除按钮（`data-testid={`delete-${s.id}`}`）：

```tsx
                        <button
                          data-testid={`delete-${s.id}`}
                          onClick={(e) => { e.stopPropagation(); onDelete(s.id); }}
                          className="flex items-center justify-center rounded-lg bg-red-500/15 px-2.5 py-1.5 text-xs text-red-400 transition-colors hover:bg-red-500/25 hover:text-red-300 active:scale-95"
                          aria-label="删除稿件"
                        >
                          <Trash2 size={13} />
                        </button>
```

- [ ] **Step 8: 移除"确认删除"弹窗 JSX**

删除整个 `{confirmId && (...)}` 块（原 L361-377 的"确认删除稿件"对话框）。

- [ ] **Step 9: 运行全部 ScriptList 测试，确认通过**

Run: `npx vitest run src/components/ScriptList.test.tsx`
Expected: PASS（含改造后的删除用例 + 两个两阶段用例 + Task 2 的重叠用例）

- [ ] **Step 10: 跑全量测试确认无回归**

Run: `npx vitest run`
Expected: 全绿（尤其 App.test.tsx 进入提词器流程未受影响）

- [ ] **Step 11: 提交**

```bash
git add src/components/ScriptList.tsx src/components/ScriptList.test.tsx src/index.css
git commit -m "feat: two-stage left-swipe delete with visual shake, remove confirm modal

- Stage 1 (-72): reveal delete zone, release to snap back
- Stage 2 (<= -130): direct delete, no confirm dialog
- Card delete button also deletes directly (no modal)
- swipe-shake CSS animation on threshold crossing (iOS-safe, no vibrate)
- Keep clear-all confirm modal

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: filmedIds 状态提升（ScriptList 受控化 + App 接入 useFilmed）

**Files:**
- Modify: `src/components/ScriptList.tsx`（Props 接口、移除内部 filmedIds state L40-53、handleTouchEnd 用 prop）
- Modify: `src/App.tsx`（接入 useFilmed、clearStale、下发 filmedIds/onToggleFilmed）
- Test: `src/components/ScriptList.test.tsx`（所有 render 加 props + 新增受控用例）
- Test: `src/App.test.tsx`（新增 clearStale 用例）

**Interfaces:**
- Consumes: Task 1 的 `useFilmed`
- Produces:
  - ScriptList Props 新增：`filmedIds: Set<string>`、`onToggleFilmed: (id: string) => void`
  - ScriptList 移除内部 filmed state，改为受控

- [ ] **Step 1: 更新 ScriptList 测试——所有 render 加新 props + 新增受控用例**

在 `src/components/ScriptList.test.tsx`，给**所有** `<ScriptList ... />` render 调用补两个 prop：`filmedIds={new Set()}` 和 `onToggleFilmed={() => {}}`（现有 6 个用例 + Task 2/3 新增用例都要补）。

然后在 `describe` 末尾新增：

```ts
  it('右滑标记调用 onToggleFilmed', () => {
    const onToggleFilmed = vi.fn();
    render(
      <ScriptList scripts={scripts} filmedIds={new Set()} onToggleFilmed={onToggleFilmed} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    const card = screen.getByTestId('content-1').parentElement!;
    fireEvent.touchStart(card, { touches: [{ clientX: 50, clientY: 50 }] });
    fireEvent.touchMove(card, { touches: [{ clientX: 120, clientY: 50 }] }); // dx = 70
    fireEvent.touchEnd(card);
    expect(onToggleFilmed).toHaveBeenCalledWith('1');
  });

  it('filmedIds 受控：已标记稿件显示绿标', () => {
    render(
      <ScriptList scripts={scripts} filmedIds={new Set(['1'])} onToggleFilmed={() => {}} onOpen={() => {}} onEdit={() => {}} onDelete={() => {}} onCreate={() => {}} />
    );
    // 已拍摄稿件标题带 line-through
    const title = screen.getByText('视频脚本');
    expect(title.className).toContain('line-through');
  });
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npx vitest run src/components/ScriptList.test.tsx`
Expected: FAIL（Props 缺失警告；现有 render 缺新 props 报错）

- [ ] **Step 3: ScriptList 受控化——改 Props 接口**

`src/components/ScriptList.tsx` 的 `interface Props`：

```ts
interface Props {
  scripts: Script[];
  filmedIds: Set<string>;
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onCreate: () => void;
  onToggleFilmed: (id: string) => void;
  onDeleteAll?: () => void;
}
```

函数签名解构加 `filmedIds`、`onToggleFilmed`：

```ts
export function ScriptList({ scripts, filmedIds, onOpen, onEdit, onDelete, onCreate, onToggleFilmed, onDeleteAll }: Props) {
```

- [ ] **Step 4: 移除 ScriptList 内部 filmed state**

删除以下两段（原 L40-53）：

```ts
  const [filmedIds, setFilmedIds] = useState<Set<string>>(() => { ... });
  const toggleFilmed = useCallback((id: string) => { ... }, []);
```

`handleTouchEnd` 内 `toggleFilmed(id)` 改为 `onToggleFilmed(id)`，依赖数组 `[setSwipe, toggleFilmed, onDelete]` 改为 `[setSwipe, onToggleFilmed, onDelete]`：

```ts
  const handleTouchEnd = useCallback((_e: React.TouchEvent, id: string) => {
    if (swipingId.current !== id) { swipingId.current = null; return; }
    swipingId.current = null;
    const offset = swipeRef.current.get(id) || 0;
    if (offset > 40) {
      onToggleFilmed(id);
    } else if (offset <= -130) {
      onDelete(id);
    }
    setShakeId(null);
    setSwipe(id, 0);
  }, [setSwipe, onToggleFilmed, onDelete]);
```

> 渲染处 `const isFilmed = filmedIds.has(s.id);` 不变（现在 filmedIds 是 prop，同名）。

- [ ] **Step 5: App 接入 useFilmed**

`src/App.tsx`：

5a. import：
```ts
import { useFilmed } from './store/useFilmed';
```

5b. 在 `useSettings()` 之后加：
```ts
  const { scripts, addScript, updateScript, deleteScript, clearAll, importScript } = useScripts();
  const { settings, updateSettings } = useSettings();
  const { filmedIds, markFilmed, toggleFilmed, clearStale } = useFilmed();
```

5c. clearStale effect（放在现有 effect 附近）：
```ts
  // 清理已删除稿件的 filmed 残留 id
  useEffect(() => {
    clearStale(scripts.map((s) => s.id));
  }, [scripts, clearStale]);
```

5d. `<ScriptList>` 下发新 props：
```ts
      <ScriptList
        scripts={scripts}
        filmedIds={filmedIds}
        onOpen={openPrompter}
        onEdit={(id) => { setActiveId(id); setEditSnapshot(null); setView('editor'); }}
        onDelete={deleteScript}
        onCreate={handleCreate}
        onToggleFilmed={toggleFilmed}
        onDeleteAll={clearAll}
      />
```

- [ ] **Step 6: App clearStale 测试**

在 `src/App.test.tsx` 的 `describe` 内新增：

```ts
  it('清理已删除稿件的 filmed 残留', () => {
    localStorage.setItem('prompter_filmed', JSON.stringify(['gone']));
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: '1', title: 't', content: 'c', createdAt: 1, updatedAt: 1 },
    ]));
    render(<App />);
    // clearStale 应移除不存在的 'gone'
    expect(JSON.parse(localStorage.getItem('prompter_filmed')!)).toEqual([]);
  });
```

- [ ] **Step 7: 运行 ScriptList + App 测试，确认通过**

Run: `npx vitest run src/components/ScriptList.test.tsx src/App.test.tsx`
Expected: PASS

- [ ] **Step 8: 跑全量测试**

Run: `npx vitest run`
Expected: 全绿

- [ ] **Step 9: 提交**

```bash
git add src/components/ScriptList.tsx src/components/ScriptList.test.tsx src/App.tsx src/App.test.tsx
git commit -m "refactor: lift filmed-state to useFilmed, make ScriptList controlled

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: 读完自动返回列表 + 标记已拍摄

**Files:**
- Modify: `src/components/Teleprompter.tsx`（Props 加 onCompleted、completed 态、提示 UI、延迟返回、timer 清理）
- Modify: `src/App.tsx`（Teleprompter 下发 onCompleted={markFilmed}）
- Test: `src/components/Teleprompter.test.tsx`（**新建**）

**Interfaces:**
- Consumes: Task 1 的 `useFilmed.markFilmed`（经 App 传入）；Task 4 的 App 接线
- Produces: Teleprompter Props 新增 `onCompleted: () => void`

**语义**：`onReachEnd` → 立即 `setIsPlaying(false)` + `setCompleted(true)` + `onCompleted()`（App 端 `markFilmed`）→ 显示"✓ 已读完·已标记拍摄"提示 → 1.2s 后 `onBack()`。手动 `handleBack` 不触发 `onCompleted`（不标记）。

- [ ] **Step 1: 写失败测试（新建 `src/components/Teleprompter.test.tsx`）**

```ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { Teleprompter } from './Teleprompter';
import { Script, DEFAULT_SETTINGS } from '../types';

// mock useAutoScroll，暴露 onReachEnd 供测试触发（jsdom 无真实滚动）
vi.mock('../hooks/useAutoScroll', () => ({
  useAutoScroll: vi.fn(),
}));

import { useAutoScroll } from '../hooks/useAutoScroll';

const script: Script = { id: '1', title: '测试稿', content: '一二三四五', createdAt: 1, updatedAt: 1 };
let reachEnd: (() => void) | null = null;

beforeEach(() => {
  localStorage.clear();
  localStorage.setItem('prompter_onboarded', '1'); // 跳过 onboarding 遮罩
  reachEnd = null;
  vi.mocked(useAutoScroll).mockImplementation((opts: any) => {
    reachEnd = opts.onReachEnd;
    return { current: 0 } as any;
  });
});

function renderTel(overrides: Partial<{ onBack: ReturnType<typeof vi.fn>; onCompleted: ReturnType<typeof vi.fn> }> = {}) {
  const handlers = {
    onIndexChange: vi.fn(),
    onChangeSettings: vi.fn(),
    onBack: vi.fn(),
    onEdit: vi.fn(),
    onCompleted: vi.fn(),
    ...overrides,
  };
  render(
    <Teleprompter
      script={script}
      settings={DEFAULT_SETTINGS}
      index={0}
      onIndexChange={handlers.onIndexChange}
      onChangeSettings={handlers.onChangeSettings}
      onBack={handlers.onBack}
      onEdit={handlers.onEdit}
      onCompleted={handlers.onCompleted}
    />
  );
  return handlers;
}

describe('Teleprompter 读完回流', () => {
  it('onReachEnd 触发 onCompleted 并显示提示', () => {
    const h = renderTel();
    act(() => reachEnd!());
    expect(h.onCompleted).toHaveBeenCalledTimes(1);
    expect(screen.getByText(/已读完/)).toBeInTheDocument();
  });

  it('1.2s 后自动调用 onBack', () => {
    vi.useFakeTimers();
    const h = renderTel();
    act(() => reachEnd!());
    expect(h.onBack).not.toHaveBeenCalled();
    act(() => { vi.advanceTimersByTime(1200); });
    expect(h.onBack).toHaveBeenCalledTimes(1);
    vi.useRealTimers();
  });

  it('手动返回不触发 onCompleted', () => {
    const h = renderTel();
    // 点返回按钮（aria-label="返回"）
    act(() => {
      screen.getByLabelText('返回').click();
    });
    expect(h.onCompleted).not.toHaveBeenCalled();
    expect(h.onBack).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `npx vitest run src/components/Teleprompter.test.tsx`
Expected: FAIL（Props 缺 `onCompleted`；`/已读完/` 找不到）

- [ ] **Step 3: Teleprompter 加完成态**

`src/components/Teleprompter.tsx`：

3a. Props 接口加 `onCompleted`：
```ts
interface Props {
  script: Script;
  settings: TeleprompterSettings;
  index: number;
  onIndexChange: (i: number) => void;
  onChangeSettings: (patch: Partial<TeleprompterSettings>) => void;
  onBack: () => void;
  onEdit: () => void;
  onCompleted: () => void;
}
```

解构加 `onCompleted`（`export function Teleprompter({ ..., onBack, onEdit, onCompleted }: Props)`)。

3b. 新增 completed state + timer ref（在 `pauseReason` state 附近）：
```ts
  const [completed, setCompleted] = useState(false);
  const completionTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
```

3c. 卸载清理（合并到现有 pauseTimer 清理 effect，或新增）：
```ts
  useEffect(() => {
    return () => {
      if (completionTimerRef.current) clearTimeout(completionTimerRef.current);
    };
  }, []);
```

3d. 改 `useAutoScroll` 的 `onReachEnd`（原 `onReachEnd: () => setIsPlaying(false)`）：
```ts
  const scrollRef = useAutoScroll({
    running: isPlaying,
    pxPerSec,
    getViewport,
    getMaxOffset,
    onTick: computeActive,
    onReachEnd: () => {
      setIsPlaying(false);
      setCompleted(true);
      onCompleted();
      if (completionTimerRef.current) clearTimeout(completionTimerRef.current);
      completionTimerRef.current = setTimeout(() => onBack(), 1200);
    },
  });
```

3e. 在 pauseReason 提示附近新增完成提示（z-40，绿色文案）：
```tsx
      {/* ── Completed Notice ── */}
      {completed && (
        <div className="absolute inset-x-0 top-20 z-40 mx-auto w-fit rounded-full border border-white/10 glass-surface px-4 py-2.5 text-center text-xs text-green-400">
          ✓ 已读完·已标记拍摄
        </div>
      )}
```

- [ ] **Step 4: App 下发 onCompleted**

`src/App.tsx` 的 `<Teleprompter>` 调用，加 `onCompleted`：

```ts
        <Teleprompter
          script={active}
          settings={settings}
          index={prompterIndex}
          onIndexChange={(i) => { setPrompterIndex(i); savePosition(active.id, i); }}
          onChangeSettings={updateSettings}
          onBack={() => setView('list')}
          onEdit={openEditorFromPrompter}
          onCompleted={() => markFilmed(active.id)}
        />
```

- [ ] **Step 5: 运行 Teleprompter 测试，确认通过**

Run: `npx vitest run src/components/Teleprompter.test.tsx`
Expected: PASS（3 个用例）

- [ ] **Step 6: 跑全量测试 + 类型检查**

Run: `npx vitest run && npx tsc --noEmit`
Expected: 全绿、无类型错误

- [ ] **Step 7: 提交**

```bash
git add src/components/Teleprompter.tsx src/components/Teleprompter.test.tsx src/App.tsx
git commit -m "feat: auto-return to list and mark filmed on teleprompter completion

onReachEnd shows a completion notice, calls onCompleted (markFilmed),
and returns to the list after ~1.2s. Manual back does not mark filmed.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Spec 覆盖自审（写计划后）

| Spec 要求 | 对应任务 |
|---|---|
| 改动1 点击卡片进入（已满足，需部署） | Global Constraints 注明；无代码任务（工作区已改） |
| 改动2.1 useFilmed hook | Task 1 |
| 改动2.2-2.5 数据流/边界/onCompleted | Task 4（App 接入）+ Task 5（Teleprompter 完成态） |
| 改动3 滑动重叠修复 | Task 2 |
| 改动4.1-4.2 两阶段阈值/松手 | Task 3 Step 4c/4d |
| 改动4.3 视觉震动（CSS） | Task 3 Step 3/4a-4b/5 |
| 改动4.4 移除单稿弹窗 + 按钮直接删 | Task 3 Step 4e/7/8 |
| 改动4.5 Escape 收敛 | Task 3 Step 4f |
| clearStale 清理残留 | Task 1（实现）+ Task 4 Step 5c/6（接入+测试） |
| 清空全部弹窗保留 | Task 3 不碰 confirmClear（保留） |
| 不做：撤销 toast / vibrate / 改 Script 类型 | Global Constraints 约束 |

**类型一致性**：`useFilmed` 在 Task 1 定义的 `markFilmed/toggleFilmed/clearStale/isFilmed/filmedIds` 命名，与 Task 4（App 解构）、Task 5（markFilmed）引用完全一致。ScriptList Props 的 `filmedIds`/`onToggleFilmed` 在 Task 4 定义，Task 4 测试引用一致。Teleprompter 的 `onCompleted` 在 Task 5 定义，App 引用一致。

**占位扫描**：无 TBD/TODO；所有代码步骤含完整可运行代码。
