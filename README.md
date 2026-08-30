# 提词器 · Perhaps

手机提词器 —— 把手机横放架在三脚架上，大字号文字匀速滚动，省去背稿。

**纯前端、零后端**，浏览器打开即用。支持 PWA 全屏 + 离线。

---

## 功能亮点

### 提词体验

提词时，屏幕中线两侧有黄色发光竖线标记阅读区。**点击屏幕**开始/暂停滚动，**手指拖拽**自由浏览。播放时左上角指示灯亮起。底部毛玻璃工具栏在暂停时淡入，单行滑块（44px 高命中区）调节字号和速度，参数胶囊实时显示数值。

- **双指捏合**：直接缩放提词字号（不再缩放页面），捏合中实时显示当前字号
- **回到顶部**：滚动停在最底部时出现按钮，一键回到开头
- **轻点切换**：单击屏幕开始/暂停，捏合后自动抑制误触

![提词器](docs/images/03-teleprompter.png)

### 智能拆分稿件

在编辑页输入或粘贴长文案，选择拆分方式后点击「智能拆分」：

- **按空行**：每段空行拆为独立稿件，标题自动取每段第一行
- **按关键词**：在每个关键词出现处之前切分，新段以关键词开头，标题取每段第一行

![智能拆分](docs/images/02-editor-split.png)

### 自动暂停

设置自动暂停模式：**关键词**（滚动到指定词自动停）或**空行**（每段结束自动停）。暂停时顶部弹出提示，3 秒自动消失。

### 提词设置

字号、字间距、行距、两边间距、滚动速度全部可调。支持左/中/右对齐，镜像翻转（分光镜反射），速度预设一键切换。

![设置面板](docs/images/04-settings.png)

### 稿件管理

- **字数统计**：每张卡片显示字数
- **排序**：按日期、标题、字数排序，支持升/降序
- **搜索**：实时过滤标题和内容
- **安全删除**：单篇和清空全部都有二次确认

![稿件管理](docs/images/01-scriptlist.png)

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
npm test         # 95 个单元测试
npm run build    # 输出 dist/
```

Push 到 `main` 自动通过 GitHub Actions 部署到 GitHub Pages。

---

## 技术栈

Vite 6 · React 19 · TypeScript · TailwindCSS 4 · lucide-react · Vitest

---

## 项目结构

```
├── index.html
├── vite.config.ts
├── public/                  # PWA 图标、manifest、Service Worker
├── scripts/                 # 图标生成脚本
└── src/
    ├── main.tsx
    ├── App.tsx              # 三视图：list / prompter / editor
    ├── types.ts
    ├── lib/                 # 纯函数
    │   ├── tokens.ts        # 按码点拆字、可读字数统计
    │   ├── speed.ts         # 速度换算
    │   ├── editResolve.ts   # 编辑后阅读位置恢复
    │   ├── format.ts        # 时间格式化
    │   └── pwa.ts           # PWA 检测
    ├── store/               # localStorage 持久化
    │   ├── useScripts.ts    # 稿件 CRUD
    │   └── useSettings.ts   # 提词设置
    ├── hooks/
    │   ├── useAutoScroll.ts # 自动滚动（原生 scrollTop）
    │   ├── useTimer.ts      # 计时器
    │   ├── useWakeLock.ts   # 屏幕常亮
    │   ├── useTransientFlag.ts
    │   └── useDebouncedCallback.ts
    └── components/
        ├── Teleprompter.tsx     # 提词主视图
        ├── ScriptText.tsx       # 逐字渲染
        ├── Controls.tsx         # 底部毛玻璃控制栏
        ├── SettingsPanel.tsx    # 设置抽屉
        ├── AutoPauseControl.tsx # 自动暂停控制
        ├── ScriptEditor.tsx     # 稿件编辑
        ├── ScriptList.tsx       # 稿件列表
        └── AddToHomeScreenPrompt.tsx
```

---

## 数据存储

全部存 `localStorage`，不跨设备同步：

| Key | 内容 |
|-----|------|
| `prompter_scripts` | 稿件列表（JSON） |
| `prompter_settings` | 提词设置 |
| `prompter_pos_{id}` | 每篇进度记忆 |
| `prompter_onboarded` | 新手引导已看过 |
| `prompter_aths_dismissed` | PWA 引导已关闭 |

---

## 已知限制

| 限制 | 说明 |
|------|------|
| iOS 屏幕常亮 | Wake Lock API 在 iOS Safari 的 `file://` 下不可用，网页版正常 |
| 跨设备同步 | 不支持，各设备 localStorage 独立 |
| iOS 全屏 | 仅 PWA「添加到主屏幕」可全屏 |
| 页面缩放 | 已禁用整页捏合缩放（捏合用于调节字号，iOS 靠 viewport `maximum-scale=1` 拦截），系统无障碍缩放不可用 |

---

## 许可

个人项目，自由使用。
