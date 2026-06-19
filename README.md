# 📱 提词器（Prompter）

一个为**短视频 / Vlog 拍摄**设计的手机提词器。

把手机或 iPad 横放架在三脚架上、对着镜头念稿，屏幕上大字号文字匀速滚动、当前行高亮停在视线中线，省去背稿。纯前端、单 HTML 文件，浏览器打开即用，无需联网、无需服务器、无需安装。

---

## ✨ 功能特性

### 提词核心
- **丝滑无极滚动**：用 CSS `transform` 驱动（GPU 合成、亚像素），从 30 WPN 极慢到 600 WPN 极快都不卡顿
- **逐行高亮**：当前念到的整行高亮（黄字加粗），已读行变暗、未读行正常，视线容易锁定
- **阅读色块**：屏幕中线一条 2 行高的淡黄色「注视带」，当前行始终落在带内
- **自动 / 手动两种模式**：
  - 自动模式：按速度匀速滚动，可随时暂停
  - 手动模式：手指拖拽自由浏览，松手后高亮跟随中线

### 速度与排版调节
- **速度**：30–600 WPN（字/分钟），控制条上直接拖滑块调节，也支持预设档（龟速 80 / 标准 160 / 快语 240 / 极速 320）
- **字号**（24–120 px）、**字间距**（0–0.3 em）、**行距**（1.0–2.5）、**两边间距**（4–20%）
- **文本对齐**：左 / 居中 / 右（默认左对齐）
- **镜像翻转**：水平翻转文字，供分光镜反射玻璃使用
- 所有设置**实时生效**，所见即所得

### 进度与计时
- **录制计时器**：从播放起算的实际时长，暂停即停
- **进度条**：可拖拽跳转任意位置；右端显示按字数 ÷ 速度估算的「预估总时长」

### 快捷键与手势
| 操作 | 效果 |
|------|------|
| `空格` | 播放 / 暂停 |
| `↑` / `↓` | 加速 / 减速（步进 20，按住 `Shift` 微调 5） |
| 双击 / 双指轻触 | 播放 / 暂停 |
| 拖拽 | 手动自由浏览 |

### 稿件管理
- **多稿管理**：卡片列表、搜索（按标题 + 正文）、新建、编辑、删除（二次确认）
- **自动保存**：编辑即存，无保存按钮
- **导入稿件**：支持粘贴文本，或选择 `.txt` / `.md` 文件（可多选）
  - 从**苹果备忘录**导入：备忘录里全选复制 → 提词器导入面板粘贴；或备忘录「发送副本 → 存储到文件」导出 txt 后选文件
- **一键清空全部**（二次确认）

### 移动端体验
- **屏幕常亮**（Wake Lock）：拍摄中防自动锁屏
- **全屏模式**：隐藏浏览器工具栏，最大化显示
- **横屏自适应**：竖屏进入时提示「建议横放设备」
- **触控优化**：禁用长按选词、防误触
- **防误退出**：编辑 / 提词中拦截意外关闭（桌面端）

---

## 🚀 怎么用（最终用户）

1. 拿到 [`teleprompter.html`](teleprompter.html)（项目根目录下的单文件产物）
2. 用 **Chrome**（或任意现代浏览器）双击打开
3. 点「新建稿件」输入文案 → 返回列表点稿件进入提词器
4. 横放设备，按空格或点播放开始念稿

> 这个 HTML 文件是自包含的（JS/CSS 全部内联），可以拷到任何地方、AirDrop 给别人、放手机里随时打开。稿件和设置存在浏览器的 `localStorage`，刷新不丢。

---

## 🛠 技术栈

- **Vite 6** + **React 19** + **TypeScript 5.8**
- **TailwindCSS 4**（`@tailwindcss/vite` 插件，黑底 + 黄强调 + 玻璃态视觉）
- **lucide-react**（图标）
- **Vitest 2** + **@testing-library/react** + **jsdom**（单元测试）
- **vite-plugin-singlefile**（构建时把 JS/CSS 内联成单个 `index.html`）

**纯前端、零后端**。所有逻辑与存储都在浏览器内完成。

---

## 📂 项目结构

```
prompter/
├─ index.html               # Vite 入口
├─ teleprompter.html        # ⭐ 最终交付产物（构建后的单 HTML）
├─ package.json
├─ vite.config.ts           # 含 singlefile 插件
├─ vitest.config.ts
├─ tsconfig.json
├─ docs/                    # 设计文档与实现计划
└─ src/
   ├─ main.tsx              # 入口
   ├─ App.tsx               # 三视图状态机：list / prompter / editor
   ├─ types.ts              # Script / TeleprompterSettings 类型与默认值
   ├─ lib/                  # 纯函数（可单测）
   │  ├─ tokens.ts          # 按码点拆字
   │  ├─ speed.ts           # WPN 换算、自动推进数学、速度常量
   │  ├─ lines.ts           # 视觉行分组（逐行高亮）
   │  ├─ editResolve.ts     # 编辑后阅读位置解析
   │  └─ format.ts          # 时间格式化 mm:ss
   ├─ store/                # localStorage 持久化层 + hooks
   │  ├─ storage.ts
   │  ├─ useScripts.ts      # 稿件 CRUD + 清空 + 导入
   │  └─ useSettings.ts     # 全局提词设置
   ├─ hooks/
   │  ├─ useAutoScroll.ts   # ⭐ transform 连续滚动（丝滑核心）
   │  ├─ useTimer.ts        # 墙钟计时
   │  ├─ useWakeLock.ts     # 屏幕常亮 + 降级
   │  ├─ useDebouncedCallback.ts
   │  ├─ useAutoAdvance.ts  # （旧逐字推进，已被 useAutoScroll 取代，保留）
   │  └─ useSmoothScroll.ts # （旧 scrollTop 缓动，保留）
   └─ components/
      ├─ Teleprompter.tsx   # 提词器主视图（整合滚动/高亮/交互）
      ├─ ScriptText.tsx     # 逐字渲染 + 逐行三态高亮
      ├─ Controls.tsx       # 底部胶囊控制条（含速度滑块）
      ├─ SettingsPanel.tsx  # 设置抽屉
      ├─ ScriptEditor.tsx   # 编辑文案 + 自动保存
      └─ ScriptList.tsx     # 稿件列表/搜索/新建/删除/清空/导入
```

---

## 💻 开发

### 环境要求
- Node.js 18+
- npm（首次安装依赖）

### 安装与运行

```bash
# 安装依赖
npm install

# 启动开发服务器（热更新）
npm run dev
# 然后浏览器打开 http://localhost:5173

# 跑单元测试
npm test

# 构建生产产物（生成 dist/index.html 单文件）
npm run build
```

构建后把 `dist/index.html` 复制为项目根的 `teleprompter.html` 即是交付物：

```bash
cp dist/index.html ./teleprompter.html
```

### 测试

```bash
npm test          # 单次跑全部
npm run test:watch # 监听模式
```

纯函数（速度换算、行分组、编辑定位、时间格式、token 拆分、存储容错）和组件交互（控制条、设置面板、列表、编辑器）均有单元测试覆盖。逐行高亮与滚动的真实视觉效果因依赖浏览器布局，靠手动验证。

---

## 🗄 数据存储

- **稿件**：`localStorage` key `prompter_scripts`（JSON 数组）
- **设置**：`localStorage` key `prompter_settings`
- 存储按**域名/文件来源**隔离——不同设备、不同打开方式各自独立，不跨设备同步
- 读取时若 JSON 损坏会回退到空列表 / 默认设置，不会崩溃

---

## ⚠️ 已知限制

| 限制 | 说明 |
|------|------|
| iOS 屏幕常亮 | Wake Lock API 在 iOS（Safari / iOS Chrome）的 `file://` 下基本不工作，会显示「请到系统设置调长自动锁屏」的降级提示。Chrome on Mac/Win/Android 正常。 |
| 强制横屏 | iOS 不允许网页强制旋转屏幕，只能提示用户横放设备 + UI 自适应。 |
| 跨设备同步 | 不支持。各设备的 `localStorage` 独立，换设备要重新粘贴 / 导入稿件。 |

---

## 🧭 设计文档

详细的需求确认、架构决策、与参考实现的差异，见 [`docs/superpowers/specs/`](docs/superpowers/specs/) 下的设计文档；分任务的实现计划见 [`docs/superpowers/plans/`](docs/superpowers/plans/)。

---

## 📄 许可

个人项目，自由使用。
