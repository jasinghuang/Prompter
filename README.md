# 提词器

手机提词器 —— 把手机横放架在三脚架上，大字号文字匀速滚动，省去背稿。

**纯前端、零后端**，浏览器打开即用。支持 PWA 全屏 + 离线。

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

## 功能

### 提词

- **点击屏幕** 开始 / 暂停滚动
- **手指拖拽** 自由浏览（原生惯性滚动，丝滑）
- 屏幕中线两侧有**黄色发光竖线**标记阅读区
- 顶部**红色指示灯**：播放时亮红 + 发光，暂停时灰色
- 自动保持**屏幕常亮**（Wake Lock），防止拍摄中锁屏

### 调节

底部工具栏（仅暂停时显示，播放中自动隐藏）：

| 控制 | 范围 |
|------|------|
| 字号 | 24–120 px |
| 速度 | 60–380 WPN（字/分钟） |

完整设置面板（点右上角齿轮）：字间距、行距、两边间距、对齐方式、镜像翻转。

### 稿件管理

- 多稿卡片列表、搜索、新建、编辑、删除
- **自动保存**，编辑即存
- **导入**：粘贴文本 或 选择 .txt / .md 文件
- **进度记忆**：每篇稿件自动记住上次阅读位置

### 键盘快捷键

| 键 | 效果 |
|----|------|
| `空格` | 播放 / 暂停 |
| `↑` `↓` | 加速 / 减速 |

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
    │   ├── tokens.ts        # 按码点拆字
    │   ├── speed.ts         # WPN 换算
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
    │   └── useDebouncedCallback.ts
    └── components/
        ├── Teleprompter.tsx # 提词主视图
        ├── ScriptText.tsx   # 逐字渲染
        ├── Controls.tsx     # 底部字号+速度控制
        ├── SettingsPanel.tsx# 设置抽屉
        ├── ScriptEditor.tsx # 稿件编辑
        ├── ScriptList.tsx   # 稿件列表
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
| `prompter_aths_dismissed` | PWA 引导已关闭 |

---

## 已知限制

| 限制 | 说明 |
|------|------|
| iOS 屏幕常亮 | Wake Lock API 在 iOS Safari 的 `file://` 下不可用，网页版正常 |
| 跨设备同步 | 不支持，各设备 localStorage 独立 |
| iOS 全屏 | 仅 PWA「添加到主屏幕」可全屏 |

---

## 许可

个人项目，自由使用。
