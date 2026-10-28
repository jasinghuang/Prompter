# 提词器 · Perhaps

手机提词器 —— 把手机横放架在三脚架上，大字号文字匀速滚动，省去背稿。

**纯前端、零后端**，浏览器打开即用。支持 PWA 全屏 + 离线。

---

## 功能亮点

### 提词体验

提词时，屏幕中线两侧有黄色发光竖线标记阅读区。**点击屏幕任意位置**开始/暂停滚动（暂停时中央有呼吸态播放提示，它不拦截点击；拖拽浏览时自动隐藏），**手指拖拽**自由回看。播放时左上角红点亮起（暂停为双竖线图标，两态等宽数字不跳动）。

- **双胶囊顶栏**：左「返回 + 录制计时」、右「✓ 标记已拍摄 / 编辑 / 设置」；**播放中右侧操作胶囊自动隐藏**，不与文案抢视线
- **双指捏合**：直接缩放提词字号，捏合中实时显示当前字号
- **回到顶部**：滚动停在最底部时出现按钮，一键回到开头
- **底部工具栏**：暂停时淡入，单行滑块（44px 命中区）调字号和速度，退场与顶栏同款轻动画

### 稿件管理

- **文件夹**：**新建稿件时在编辑页「分组」行决定归入哪个文件夹**（未分组 / 现有 / 内联新建，中文输入法安全）；事后点卡片上的文件夹图标移动。文件夹由稿件派生，移空自动消失，**智能拆分的产物自动继承分组**
- **星标**：卡片右下角星标收藏，未拍摄的星标稿稳定置顶
- **已拍摄沉底**：标记「已拍摄」的稿件自动排到列表底部（未拍星标 → 未拍 → 已拍），待拍永远在上
- **长按多选**：长按任意卡片进入多选，点选/全选后**批量移动到文件夹**（可就地新建）或**批量删除**（2 秒内可整批撤销）
- **撤销删除**：单篇或批量删除后顶部出现「撤销删除」，稿件与已拍摄标记整批还原到原位置
- **返回定位**：从播放页返回列表时，刚打开的卡片保持金色微光，一眼找回位置；文件夹视图在往返后保持不变
- **字数与时长**：每张卡片显示字数和预计口播时长（按当前滚动速度估算）
- **排序/搜索**：按日期、标题、字数排序（升降序），实时过滤标题和内容

### 智能拆分稿件

在编辑页粘贴长文案，选择拆分方式后点击「智能拆分」：

- **按空行**：每段空行拆为独立稿件，标题自动取每段第一行
- **按关键词**：在每个关键词出现处之前切分，新段以关键词开头

### 自动暂停

设置自动暂停模式：**关键词**（滚动到指定词自动停）或**空行**（每段结束自动停）。暂停时顶部弹出提示，3 秒自动消失。

### 提词设置

字号、字间距、行距、两边间距、滚动速度全部可调。支持左/中/右对齐、镜像翻转（分光镜反射）、读完动作（停在原地 / 返回列表并标记已拍摄 / 回到开头重读）。

### 键盘快捷键

| 键 | 效果 |
| --- | --- |
| `空格` | 播放 / 暂停 |
| `↑` `↓` | 加速 / 减速 |

---

## 怎么用

### 推荐：PWA（全屏 + 离线）

1. iPhone Safari 打开 **<https://jasinghuang.github.io/Prompter/>**
2. 点底部「分享」→「添加到主屏幕」
3. 从桌面图标启动 → 全屏无浏览器外壳，断网也能用

> 微信里点链接：右上角「…」→「在 Safari 中打开」再做第 2 步。

### 开发模式

```bash
npm install
npm run dev      # http://localhost:5173
npm test         # 223 个单元测试
npm run build    # 输出 dist/（单文件 HTML）
```

Push 到 `main` 自动通过 GitHub Actions 部署到 GitHub Pages。

---

## 技术栈

**Vite 6 · React 19 · TypeScript · TailwindCSS 4 · lucide-react · Vitest + Testing Library**

- **零运行时依赖**（仅 React 与图标库）：无路由库、无状态管理库、无动画库——三视图状态机手写、FLIP 动画手写、撤销系统手写
- **PWA**：自写 Service Worker（导航 network-first 带 3s 超时兜底、静态资源 cache-first）+ manifest 横屏全屏；`vite-plugin-singlefile` 把整个应用打进一个 HTML
- **平台 API**：Wake Lock（屏幕常亮，含卸载竞态处理）、`beforeinstallprompt`、ResizeObserver、Pointer Events（长按多选/捏合字号）
- **设计系统**：CSS 变量统一管理颜色/圆角/阴影与**控件层级阶梯**（T1 主操作 44px → T2 内容导航 40px → T3 工具 32px → T4 元信息 12px 文字），列表/播放/编辑三页共用同一套 token
- **组件复用**：`CapsuleButton`（胶囊控件体系）、`SegmentedPill`、`FilterChip` 等跨页共享，保证设计语言一致

---

## 项目结构

```
├── index.html
├── vite.config.ts           # base /Prompter/ + singlefile 打包
├── public/                  # PWA 图标、manifest、Service Worker
│   └── preview-design.html  # 设计方案预览页（开发用）
├── scripts/                 # 图标生成脚本
└── src/
    ├── main.tsx             # SW 注册 + iOS PWA 玻璃降级判定
    ├── App.tsx              # 三视图状态机：list / prompter / editor
    ├── types.ts             # Script/Settings 类型 + 控件层级常量
    ├── index.css            # 设计 token（颜色/层级/玻璃体系）与全部动画
    ├── lib/                 # 纯函数
    │   ├── tokens.ts        #   按码点拆字、可读字数统计
    │   ├── speed.ts         #   速度常量、口播时长估算
    │   ├── split.ts         #   智能拆分（空行/关键词）
    │   ├── editResolve.ts   #   编辑后阅读位置恢复
    │   ├── pinch.ts         #   捏合手势 → 字号换算
    │   ├── format.ts        #   时间格式化
    │   └── pwa.ts           #   PWA/iOS 环境检测与降级判定
    ├── store/               # localStorage 持久化
    │   ├── useScripts.ts    #   稿件 CRUD + 撤销恢复 + 星标/分组
    │   ├── useSettings.ts   #   提词设置（含旧字段迁移）
    │   └── useFilmed.ts     #   已拍摄标记
    ├── hooks/
    │   ├── useAutoScroll.ts #   rAF 驱动原生 scrollTop 自动滚动
    │   ├── useSwipeAction.ts#   卡片滑动手势（划右标记/划左删除）
    │   ├── useWakeLock.ts   #   屏幕常亮
    │   ├── useTimer.ts      #   计时器
    │   ├── usePauseOn*.ts   #   关键词/空行自动暂停
    │   └── useTransientFlag / useDebouncedCallback
    ├── sw/registerSW.ts
    └── components/
        ├── Teleprompter.tsx     # 提词主视图（双胶囊顶栏/中央提示/自动隐藏）
        ├── ScriptList.tsx       # 列表（筛选/排序/长按多选/FLIP 动画）
        ├── SwipeableCard.tsx    # 卡片（滑动/长按多选/高亮定位）
        ├── ScriptEditor.tsx     # 编辑（分组行/智能拆分/自动暂停）
        ├── CapsuleButton.tsx    # 胶囊控件体系（跨页共享）
        ├── Controls.tsx         # 播放页底部滑块栏
        ├── SettingsPanel.tsx    # 设置抽屉
        ├── AutoPauseControl.tsx / SegmentedPill.tsx / Toggle.tsx
        └── AddToHomeScreenPrompt.tsx
```

---

## 数据存储

全部存 `localStorage`，不跨设备同步：

| Key | 内容 |
|-----|------|
| `prompter_scripts` | 稿件列表（含 `starred` / `folder` 字段） |
| `prompter_settings` | 提词设置 |
| `prompter_filmed` | 已拍摄稿件 id |
| `prompter_pos_{id}` | 每篇阅读进度（字 index，缩放后仍准确） |
| `prompter_sort` | 排序偏好 |
| `prompter_recent` | 最近使用（搜索框快捷入口） |
| `prompter_scroll` | 列表滚动位置 |
| `prompter_onboarded` / `prompter_aths_dismissed` | 引导标记 |

---

## 已知限制

| 限制 | 说明 |
|------|------|
| iOS PWA 花屏 | WebKit 的 `backdrop-filter` 在 standalone 模式有渲染 bug（静止画面花屏、旋转屏幕才消失），PWA 内自动降级为无模糊玻璃（`html.glass-solid`），浏览器不受影响 |
| iOS 屏幕常亮 | Wake Lock API 在 iOS Safari 的 `file://` 下不可用，网页版正常 |
| 跨设备同步 | 不支持，各设备 localStorage 独立 |
| iOS 全屏 | 仅 PWA「添加到主屏幕」可全屏 |
| 页面缩放 | 已禁用整页捏合缩放（捏合用于调节字号），系统无障碍缩放不可用 |

---

## 许可

个人项目，自由使用。
