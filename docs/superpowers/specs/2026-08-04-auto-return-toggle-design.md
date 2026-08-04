# 读完自动返回开关 — 设计

> 日期：2026-08-04
> 范围：把「读完自动返回列表 + 标记已拍摄」做成可选功能（默认关闭）
> 决策：方案 A — 开关关时，读完只停止播放（回到此功能加入前的朴素行为），不提示、不标记、不自动返回

## 改动

1. **types.ts**：`TeleprompterSettings` 加 `autoReturnOnComplete: boolean`；`DEFAULT_SETTINGS` 加 `autoReturnOnComplete: false`
2. **SettingsPanel.tsx**：AutoPause 区附近加一个 toggle（仿「镜像翻转」样式），文案「读完自动返回」，副标题「读完自动标记已拍摄并返回列表」
3. **Teleprompter.tsx**：`onReachEnd` 加判断——开 → 当前完成流程（提示 + onCompleted + 延迟返回）；关 → 只 `setIsPlaying(false)`

## 持久化
随 useSettings 自动（整个 settings 对象存 localStorage，已有机制）。

## 测试
Teleprompter.test.tsx 现有完成用例在 `autoReturnOnComplete: true` 下跑；补一个默认（false）时「读完不回流」的用例。

## 行为
- 默认（关）：读完停在提词页（朴素）
- 开启：读完 → 提示 → 标记已拍摄 → 自动返回（当前行为）
