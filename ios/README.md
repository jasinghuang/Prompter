# 提词器 · iOS 原生版（SwiftUI 重写）

Web PWA 保持不动；此目录是全原生重写版，里程碑：**M1 数据层+列表 → M2 编辑（分组/拆分）→ M3 播放引擎（UIScrollView+TextKit2+CADisplayLink）→ M4 设置/镜子/多选批量 → M5 AirPods 点头控制**。

## 构建（首次）

前置：Xcode 16+（App Store 安装）与 XcodeGen：

```bash
brew install xcodegen   # 已装可跳过
cd ios
xcodegen generate       # 由 project.yml 生成 Prompter.xcodeproj
open Prompter.xcodeproj
```

Xcode 里：Target → Signing & Capabilities → Team 选你的个人 Apple ID（免费账号即可）→ 插上 iPhone → Cmd+R。

> 免费账号 7 天签名过期，用 AltStore 自动续签或重新 Cmd+R 一次。

## 数据迁移（PWA → App）

1. 网页版列表页工具行点「**导出**」→ 剪贴板拿到全部数据
2. 打开 App：启动时自动检测剪贴板，弹「检测到提词器数据，导入？」
   （也可 头部 ⋯ 菜单 → 从剪贴板导入）

反向：App 头部 ⋯ 菜单 → 拷贝导出数据。

## 当前状态（M1）

- [x] SwiftData 模型（starred/folder/isFilmed）
- [x] 分层排序：星标未拍 → 未拍 → 星标已拍 → 已拍沉底（组内日期/标题/字数 + 升降）
- [x] 列表页：搜索 / 筛选 chips / 排序 / 卡片（三级视觉层级、幽灵操作钮、按压反馈）
- [x] 单删 + 顶部「撤销删除」2 秒窗口；清空全部确认
- [x] 剪贴板智能导入 + 导出（与 PWA JSON 互通）
- [x] 编辑页（标题/正文/保存）；播放页为 M3 占位（仅导航往返）
- [ ] M2+：分组行、智能拆分、滚动引擎、设置面板、镜子、多选批量、AirPods

## 测试

Xcode：Cmd+U（PrompterCoreTests：字数/时长/格式化/分层/迁移解码）。
纯逻辑已用 `swiftc -typecheck` 验证（SwiftData 宏需完整 Xcode）。
