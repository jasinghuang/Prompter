# 代码审查发现清单 — 2026-08-04

> **审查对象**：commit `da26a9e`（交互优化 + 工程改进合并后）
> **范围**：ScriptList / Teleprompter / App / useFilmed / useAutoScroll / useWakeLock / useTimer / index.css
> **维度**：bug / 逻辑错误 + 代码臃肿 / 可简化（非 spec 合规，spec 另有 final review）
> **用途**：供后续 agent / 维护者查询，按影响排序，每项含定位、问题、方案、状态

## 总表（按影响程度排序）

| 编号 | 严重性 | 问题 | 文件 | 批次 | 状态 |
|---|---|---|---|---|---|
| CF1 | 真 bug ⭐⭐ | wakeLock 卸载竞态，Android 屏幕常亮泄漏 | useWakeLock.ts / Teleprompter.tsx | 1 | 待修 |
| CF2 | 真 bug ⭐⭐ | 无 onTouchCancel，中断后卡片卡在半滑动 | ScriptList.tsx | 1 | 待修 |
| CF13 | UI 增强 ⭐⭐ | 左滑阶段1后空白区浪费，可做确认提示 | ScriptList.tsx | 1 | 待修 |
| CF3 | 性能 ⭐ | 每次 touchmove 重渲染整个列表，长列表卡顿 | ScriptList.tsx | 2 | 待修 |
| CF4 | 内存 | 删除稿件后滑动状态不清理 | ScriptList.tsx | 1 | 待修 |
| CF12 | 可读性 | 滑动魔法数字散落，应命名常量 | ScriptList.tsx | 1 | 待修 |
| CF5 | 死代码 | Teleprompter touchStartRef.scrollTop 死字段 | Teleprompter.tsx | 1 | 待修 |
| CF6 | 死代码 | ScriptList searchRef 声明后从未读 | ScriptList.tsx | 1 | 待修 |
| CF11 | 死代码 | useAutoScroll 的 RAF fallback 永不可达 | useAutoScroll.ts | 1 | 待修 |
| CF7 | API/死代码 | useFilmed.isFilmed 生产未用（仅测试） | useFilmed.ts | — | 保留 |
| CF8 | API/死代码 | useTimer.reset 生产未用（仅测试） | useTimer.ts | — | 保留 |
| CF9 | 重构 | 滑动手势应抽成 hook（减 ~50 行） | ScriptList.tsx | 2 | 待修 |
| CF10 | 重构 | Teleprompter 11 个 effect，应拆暂停逻辑 | Teleprompter.tsx | 2 | 待修 |

---

## 详情

### CF1 — wakeLock 卸载竞态（真 bug）
- **文件**：`src/hooks/useWakeLock.ts:14-19` + `src/components/Teleprompter.tsx`（mount effect 调 `request()`）
- **问题**：`request()` 内 `await navigator.wakeLock.request('screen')` 未完成时组件卸载 → cleanup 调 `release()` 但 `sentinelRef.current` 还是 null（release 空操作）→ await 返回后 sentinel 被赋值却无人释放 → **Android 屏幕一直亮到页面重载**
- **影响**：耗电；iOS 不支持 wakeLock 无影响，Android 真实可触发
- **方案**：Teleprompter 的 wakeLock effect 加 cancelled flag：
  ```ts
  useEffect(() => {
    let cancelled = false;
    request()
      .then(() => { if (cancelled) release(); })  // 卸载在飞行中 → 释放刚拿到的 sentinel
      .catch(() => showWakeLockFailed());
    return () => { cancelled = true; release(); };
  }, []);
  ```

### CF2 — 无 onTouchCancel（真 bug）
- **文件**：`src/components/ScriptList.tsx`（卡片 div，L259-261 区域）
- **问题**：只绑了 touchStart/Move/End，无 touchCancel。来电/横竖屏切换/滚动被抢占时系统发 touchcancel 而非 touchend → `setSwipe(id,0)` 不执行 → `swipingId.current` 卡住、卡片停在半滑动
- **影响**：中断后卡片卡死，需重新挂载才恢复
- **方案**：加 `onTouchCancel` 复用 touchEnd 的清理逻辑（回弹、清 swipingId/shakeId）

### CF13 — 左滑阶段1后的空白区用于确认提示（UI 增强，新需求）
- **文件**：`src/components/ScriptList.tsx`（删除区 JSX）
- **问题**：阶段1 露出右侧 72px 红区后，继续滑 -72→-130，红区**左侧**露出 `|swipeX|-72` 宽的空白黑区（当前浪费）
- **方案**：红区左侧加渐变提示层（absolute, right:72px, width 随滑动展开），文字随阶段切换：
  - `-72 < swipeX ≤ -130`：显示「继续滑动」
  - `swipeX ≤ -130`：显示「松开删除」（与震动/高亮一致）
- **影响**：把浪费空间变成确认引导，降低误删焦虑

### CF3 — 每次 touchmove 重渲染整个列表（性能）
- **文件**：`src/components/ScriptList.tsx:52-55, 64-76`
- **问题**：`setSwipeOffsets((prev)=>({...prev,[id]:offset}))` 每帧（60Hz）创建新对象 → `filtered.map(...)` 每帧重渲染所有卡片。50 篇 × 60fps = 3000 次卡片渲染/秒
- **影响**：中端机长列表卡顿；稿件少（十几篇内）体感不到
- **方案**（批次2）：拆 `SwipeableCard` 子组件，offset 状态下沉到单卡，父组件不参与移动循环；或 ref + 直接 DOM 改 transform + rAF 节流

### CF4 — 删除稿件后滑动状态不清理（内存）
- **文件**：`src/components/ScriptList.tsx`（handleTouchEnd + swipeRef/swipeOffsets）
- **问题**：`onDelete(id)` 后仍 `setSwipe(id,0)`，`swipeRef.current` 与 `swipeOffsets` 残留该 id 条目，长期使用单调增长
- **影响**：轻微，慢速增长
- **方案**：删除分支跳过 `setSwipe(id,0)`；加 effect 按 `scripts` id 集合清理无效 key

### CF5 — Teleprompter touchStartRef.scrollTop 死字段（死代码）
- **文件**：`src/components/Teleprompter.tsx:85, 308-310`
- **问题**：`touchStartRef` 类型含 `scrollTop`，`handlePointerDown` 存了但 `handlePointerUp` 只读 `y`，scrollTop 从未用
- **方案**：类型简化为 `{ y: number } | null`，移除 scrollTop 捕获

### CF6 — ScriptList searchRef 死代码
- **文件**：`src/components/ScriptList.tsx:41, 153`
- **问题**：`searchRef` 声明并绑到 input，但从未读取
- **方案**：删除声明与 ref 绑定

### CF11 — useAutoScroll RAF fallback 死防御（死代码）
- **文件**：`src/hooks/useAutoScroll.ts:27-34`
- **问题**：`typeof requestAnimationFrame === 'function' ? raf : setTimeout fallback` 在所有 PWA 目标浏览器都不可达（jsdom 也提供 RAF）
- **方案**：直接用 `requestAnimationFrame`/`cancelAnimationFrame`

### CF7 — useFilmed.isFilmed 生产未用（保留）
- **文件**：`src/store/useFilmed.ts:60-62`
- **reviewer 建议**：删除导出，或让 ScriptList 用它
- **裁决：保留**。`isFilmed` 是 store hook 的完整查询 API（与 `filmedIds` 配对），有测试覆盖。ScriptList 直接读 `filmedIds.has` 是渲染优化（避免每次渲染调函数），不代表 isFilmed 无价值。hook API 完整性 > 洁癖。

### CF8 — useTimer.reset 生产未用（保留）
- **文件**：`src/hooks/useTimer.ts:29-32`
- **reviewer 建议**：删除，或在 Teleprompter 显式用
- **裁决：保留**。reset 是计时器的合理 public API（归零语义），有测试覆盖。Teleprompter 每个 script 新挂载隐式重置——脆弱但工作，未来若改为同挂载切稿可能需要 reset。API 完整性 > 洁癖。

### CF9 — 滑动手势抽成 hook（重构，批次2）
- **文件**：`src/components/ScriptList.tsx:43-91, 259-261`
- **问题**：4 ref + 2 state + 3 handler 全堆在列表组件，与渲染混杂
- **方案**：抽 `useSwipeAction(onSwipeRight, onSwipeLeft)`，返回 `{ offset, shaking, bind }`；ScriptList 减 ~50 行，逻辑可独立测试。与 CF3 的 SwipeableCard 一并做

### CF10 — Teleprompter 11 个 effect 应拆（重构，批次2）
- **文件**：`src/components/Teleprompter.tsx`（L69-271 共 11 个 useEffect）
- **问题**：onboarding 自动关、wake lock、timer 同步、点击 blur、键盘、scrollToIndex、scroll 监听、重新测量、关键词暂停、段落暂停、reach-end 全在一个组件
- **方案**：至少抽 `usePauseOnKeyword(...)` 和 `usePauseOnParagraph(...)`（各自有 ref，独立关注点）

### CF12 — 滑动魔法数字命名常量（可读性）
- **文件**：`src/components/ScriptList.tsx`（多处）
- **问题**：`-150 / 72 / 40 / -130 / -20 / 20` 散落，clamp 限制与提交阈值两类概念混在一起硬编码
- **方案**：
  ```ts
  const SWIPE_LIMIT_RIGHT = 72;
  const SWIPE_LIMIT_LEFT = -150;
  const COMMIT_FILMED_PX = 40;
  const COMMIT_DELETE_PX = -130;
  const REVEAL_FILMED_PX = 20;
  const REVEAL_DELETE_PX = -20;
  ```

---

## 批次划分

- **批次1（低中风险，本次）**：CF1、CF2、CF13、CF4、CF12、CF5、CF6、CF11（真 bug + 死代码 + 提示区 + 常量）。CF7/CF8 保留不修。
- **批次2（大重构，后续）**：CF3 + CF9 + CF10（SwipeableCard 拆分 / swipe hook / Teleprompter effect 拆分）。建议单独分支，因为涉及结构重构、回归风险较高。
