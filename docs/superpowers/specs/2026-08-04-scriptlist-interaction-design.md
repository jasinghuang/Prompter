# 稿件列表交互优化设计

> 日期：2026-08-04
> 范围：ScriptList 卡片交互、Teleprompter 读完回流、已拍摄状态管理
> 目标平台：移动端 PWA（iOS Safari + Android Chrome）

## 背景与动机

当前稿件列表/提词流程存在 4 处交互缺陷，本 spec 统一优化：

1. 卡片上有冗余的"开始提词"按钮（HEAD 版本），与"点卡片即进入"重复
2. 提词自然读完后停留在提词页，用户需手动返回，且不会自动标记"已拍摄"
3. 左右滑动卡片时，稿件文字与露出的绿色/红色背景区重叠，视觉脏
4. 左滑删除需经确认弹窗，交互链路长；期望"用力滑即删"的爽快手感

## 决策摘要

| 议题 | 决策 |
|---|---|
| 什么算"读完" | 自动滚到底（`onReachEnd`）才算；手动返回不标记 |
| 返回节奏 | 滚到底后显示"✓ 已读完·已标记拍摄"提示，停留约 1.2s 后自动回列表 |
| 左滑判定 | 纯距离驱动，两阶段 |
| 状态管理 | 新建独立 `useFilmed` hook（仿 useScripts/useSettings 模式） |
| 触觉反馈 | 纯视觉（CSS 抖动 + 高亮），不用 `navigator.vibrate`（iOS 不支持） |
| 删除弹窗 | 单稿删除弹窗完全移除；清空全部弹窗保留 |

---

## 改动 1：点击卡片进入提词（已满足，仅需部署）

### 现状
- git HEAD 的 [ScriptList.tsx](src/components/ScriptList.tsx) L348 存在"开始提词"按钮
- 工作区**未提交改动**已删除该按钮，改为卡片正文区 `onClick` → `handleOpen`（L293-296）
- 用户手机看到的是 GitHub Pages 部署的旧版（HEAD 或更早），故仍可见按钮

### 改动
- **无额外代码改动**。工作区状态即目标状态
- 提交当前工作区改动 + 重新部署后，手机端自动更新

### 验收
- 卡片上只有「编辑」「删除」两个操作按钮
- 点击卡片正文（非按钮区）进入提词
- 滑动过程中（`swipingId.current` 非空）的 click 被忽略，不误触进入

---

## 改动 2：自然读完 → 自动返回列表 + 标记已拍摄

### 2.1 新文件：`src/store/useFilmed.ts`

仿 [useScripts](src/store/useScripts.ts)/[useSettings](src/store/useSettings.ts) 的 store hook 模式。

```ts
// 语义接口
filmedIds: Set<string>           // 已拍摄稿件 id 集合
isFilmed(id: string): boolean
markFilmed(id: string): void     // 只增不删（读完标记用）
toggleFilmed(id: string): void   // 切换（右滑手动标记用）
clearStale(validIds: string[]): void  // 清理已删除稿件的残留 id
```

- **持久化**：localStorage key 复用现有 `prompter_filmed`（向后兼容 ScriptList 现有数据，零迁移）
- **初始化**：从 localStorage 读取为 `Set<string>`，读取失败回退空 Set
- **clearStale**：接受当前全部 script id，移除集合中不在其中的 id，并持久化。调用时机：App 层在 scripts 变化时调用一次，解决"删稿后 filmedIds 残留"的既有小问题

### 2.2 数据流

```
App（持有 useFilmed）
 ├─→ ScriptList
 │     props: filmedIds, onToggleFilmed
 │     用途: 展示绿标/删除线 + 右滑调用 onToggleFilmed
 │     （移除 ScriptList 内部 filmedIds state 与 localStorage 读写）
 │
 └─→ Teleprompter
       props: onCompleted: () => void
       触发: useAutoScroll 的 onReachEnd
```

### 2.3 Teleprompter 改动

当前 `onReachEnd: () => setIsPlaying(false)`（[L145](src/components/Teleprompter.tsx#L145)）。

新增"完成态"：
- 新增 state `completed: boolean`（默认 false）
- `onReachEnd` 回调改为：`setIsPlaying(false)` + `setCompleted(true)` + 立即调用 `props.onCompleted()`（App 端 `markFilmed(id)`，标记不等提示结束）
- `completed === true` 时，显示居中轻提示组件："✓ 已读完·已标记拍摄"
- `completed` 置 true 后，启动 `setTimeout(1200ms)` → 调用 `onBack()`（回列表）。用 `useRef` 持有 timer，组件卸载/手动返回时清理
- 守卫：`useAutoScroll` 内已有 `ended` 标志保证单次触发；Teleprompter 层额外用 `completed` state 保证提示/回调只走一次

### 2.4 App 改动

- 引入 `useFilmed()`，获得 `filmedIds`、`markFilmed`、`toggleFilmed`、`clearStale`
- scripts 变化时 `useEffect` 调 `clearStale(scripts.map(s => s.id))`
- `<ScriptList>` props：
  - 移除其内部 `filmedIds` state（改为受控）
  - 传入 `filmedIds={filmedIds}`、`onToggleFilmed={toggleFilmed}`
- `<Teleprompter>` 传入 `onCompleted={() => markFilmed(active.id)}`

### 2.5 边界与语义
- `onReachEnd` 一旦触发 = 读完。即使用户在 1.2s 提示窗口内手动按返回，仍已标记（`markFilmed` 在 `onReachEnd` 时立即调用）
- 手动返回（`handleBack`）**不**触发 `onCompleted`，不标记（Q1=A 语义）
- 同一次播放只触发一次：`useAutoScroll` 的 `ended` 标志 + Teleprompter 的 `completed` state 双重保证
- 重新进入同一稿件：`completed` 重置为 false（组件重新挂载自然重置）

---

## 改动 3：修复滑动重叠

### 根因
卡片 DOM 结构（[L255-333](src/components/ScriptList.tsx#L255-L333)）：
```
<div relative overflow-hidden glass-card>       // 外层，rgba(19,19,22,0.7) + blur
  <div absolute left-0 w-72px 绿色背景>          // z 底层
  <div absolute right-0 w-72px 红色背景>         // z 底层
  <div relative p-4 translateX(swipeX) 内容>     // 透明！滑动层
```

内容层无背景。滑动中（|offset| < 72）内容层仍覆盖在绿/红背景层上方，半透明玻璃 + 透明内容层 → 文字与背景层重叠。

### 修复
给内容层（`<div className="relative p-4">`）按滑动状态切换背景：
- `swipeX === 0`（静止）：无背景，保留 glass-card 玻璃质感
- `swipeX !== 0`（滑动中）：加不透明背景 `#131316`（= glass-card 的 RGB(19,19,22)，alpha 改 1）

实现：内容层 `style` 或 className 动态拼接：
```tsx
style={{
  transform: `translateX(${swipeX}px)`,
  background: swipeX !== 0 ? '#131316' : undefined,
  transition: swipingId.current === s.id ? 'none' : 'transform 0.25s ease-out',
}}
```
- 滑动中内容层成为"实心滑板"，干净遮住下方背景层；移开后绿/红层干净露出
- 静止时玻璃质感不受影响
- 少了 blur 叠加导致的轻微色差，在快速滑动中视觉上不可察

---

## 改动 4：左滑两阶段 + 纯视觉"震动"

### 4.1 阈值与 clamp

当前（[L79](src/components/ScriptList.tsx#L79)）：`Math.max(-72, Math.min(72, dx))`

改为（左滑放宽，右滑不变）：
```ts
setSwipe(id, Math.max(-150, Math.min(72, dx)));
```

阈值图（左负右正）：
```
右滑标记:   [ 0 ←──── 40 ──── 72 ]          (不变)
左滑删除:   [-150 ←─ -130 ── -72 ── 0 ]
              直接删    阶段2   阶段1
```

### 4.2 松手判定（handleTouchEnd，[L82-94](src/components/ScriptList.tsx#L82-L94)）

| offset | 行为 |
|---|---|
| `> 40` | 右滑：`toggleFilmed(id)`（不变） |
| `<= -130` | 左滑阶段2：直接 `onDelete(id)`，**无弹窗** |
| `-130 < offset <= -40` | 左滑阶段1：回弹，不删 |
| `-40 < offset <= 40` | 回弹（不变） |

### 4.3 越过 -130 的纯视觉反馈

在 `handleTouchMove` 中，当 offset 跨过 -130 时（用 `useRef` 守卫，每次滑动周期只触发一次）：
- 删除区背景层：`#DC2626 → #EF4444`（变亮）
- `Trash2` 图标：`scale-110`
- 卡片内容层添加 CSS 抖动 class，触发一次 `shake` keyframe 动画（~200ms，横向小幅往返）

新增 CSS keyframe（[src/index.css](src/index.css)）：
```css
@keyframes swipe-shake {
  0%, 100% { transform: translateX(0); }
  25% { transform: translateX(-4px); }
  75% { transform: translateX(4px); }
}
.swipe-shake { animation: swipe-shake 0.2s ease-in-out; }
```

> 注：抖动作用于"已平移的内容层"，keyframe 的 translateX 需与当前 `swipeX` 平移叠加（用内层包裹元素承载抖动，或用 CSS variable 组合，实现时择优）。

### 4.4 移除单稿删除弹窗（confirmId）

- 移除 ScriptList 中 `confirmId` state、`confirmClear` 保留
- 移除"确认删除稿件"弹窗 JSX（[L361-377](src/components/ScriptList.tsx#L361-L377)）
- 卡片右上角「删除」按钮：`onClick` 改为直接 `onDelete(s.id)`，不再 `setConfirmId`
- 卡片按钮仍保留 `data-testid="delete-{id}"`（测试稳定性）
- 「清空全部」弹窗（confirmClear）**保留**——批量操作误删风险高

### 4.5 Escape 监听收敛
[L129-134](src/components/ScriptList.tsx#L129-L134) 的 Escape effect 条件由 `confirmId || confirmClear` 改为仅 `confirmClear`。

---

## 明确不做（YAGNI）

- 不加删除后的"撤销"toast
- 不调用 `navigator.vibrate`（iOS 不支持，纯视觉方案已定）
- 不改「清空全部」弹窗
- 不改右滑标记的阈值与交互
- 不改 Script 类型（filmed 状态独立存储，不污染稿件模型）

---

## 测试策略

### 改动 2（useFilmed + 读完回流）
- **`useFilmed.test.ts`**：初始加载（含向后兼容已有 localStorage）、`markFilmed` 只增、`toggleFilmed` 切换、`clearStale` 移除无效 id 并持久化
- **`Teleprompter.test.tsx`** 补充：模拟 `onReachEnd` → 断言 `onCompleted` 被调用一次 + `onBack` 在 ~1.2s 后调用（用 vi.useFakeTimers）；手动 `handleBack` 不触发 `onCompleted`
- **`App.test.tsx`** 补充：提词读完 → 断言该 id 被标记 filmed + 视图回 list；手动返回不标记

### 改动 3（重叠修复）
- 视觉回归：可加一个 `ScriptList` 测试断言滑动中内容层拿到不透明背景 class/style（`background === '#131316'`），静止时为透明

### 改动 4（两阶段左滑）
- **`ScriptList.test.tsx`** 补充：
  - 模拟 touch 序列滑到 -100 松手 → 不断言删除、卡片回弹
  - 滑过 -130 松手 → 断言 `onDelete` 被调用、无弹窗
  - 卡片「删除」按钮点击 → 断言 `onDelete` 直接调用、无弹窗 DOM
  - 「清空全部」仍弹窗

### 现有测试维护
- ScriptList 现有删除相关测试（依赖 confirmId 弹窗的）需改为直接删除断言
- Teleprompter 现有 onBack 测试保持（手动返回路径不变）

---

## 受影响文件清单

| 文件 | 改动类型 |
|---|---|
| `src/store/useFilmed.ts` | 新建 |
| `src/store/useFilmed.test.ts` | 新建 |
| `src/App.tsx` | 接入 useFilmed，下发给 ScriptList/Teleprompter |
| `src/App.test.tsx` | 补读完回流用例 |
| `src/components/ScriptList.tsx` | filmedIds 改受控；滑动阈值/松手判定/视觉反馈；移除 confirmId 弹窗 |
| `src/components/ScriptList.test.tsx` | 两阶段滑动 + 删除按钮直接删用例 |
| `src/components/Teleprompter.tsx` | completed 态 + onCompleted + 提示 + 延迟返回 |
| `src/components/Teleprompter.test.tsx` | 补读完回流用例 |
| `src/index.css` | 新增 swipe-shake keyframe |

（改动 1 无代码改动，仅提交+部署。）
