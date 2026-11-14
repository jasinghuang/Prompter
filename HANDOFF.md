# Prompter-PWA 维护交接

## 项目边界

2026-11-14 从双端仓库拆分。当前目录是独立 Git 仓库；同级 `../Prompter-iOS/` 是另一仓库。父目录 `提词器/` 只负责收纳，不要在父目录执行 Git 初始化。

- GitHub：`https://github.com/jasinghuang/Prompter-PWA`
- Pages：`https://jasinghuang.github.io/Prompter-PWA/`
- 保留原仓库完整历史，历史提交中的 `ios/` 属于拆分前记录；当前版本仅维护 PWA。

## 构建和地址

在本目录运行 `npm ci`、`npm test`、`npm run build`。GitHub Actions 从 `main` 部署 `dist/`。

仓库改名涉及 Vite `base`、manifest 的 `start_url` / `scope`、Service Worker 预缓存路径和 README 地址；修改时须一起核对。应用的 SW 注册路径由 `import.meta.env.BASE_URL` 派生。缓存版本为 `prompter-pwa-v2`。

旧 `/Prompter/` 桌面入口可能需要重新添加。稿件仍使用原 localStorage 键，按浏览器来源保存；请勿通过清理网站数据解决入口问题。

## 清理边界

已移除旧构建产物、浏览器诊断日志和截图、根目录临时 PNG、开发工具缓存，以及 `public/preview-design.html` 和 `public/preview-mirror.html` 原型页。保留源码、测试、图标、设计文档及文档截图。

不要用全局 `*.png` 忽略规则：正式图标和文档图片必须能够入库。`node_modules/`、`dist/` 与本地工具缓存继续忽略。

## 拆分验收与备份

- 拆分前后均为 29 个测试文件、230 项测试通过；现有测试中的 React act、jsdom 媒体和 Node localStorage 警告在拆分前已存在。
- 生产构建通过；单文件 HTML 约 323 kB，gzip 约 92 kB。
- 拆分前 Git bundle、原始引用和清理清单位于本机 `~/.codex/backups/prompter-split-2026-11-14/`，不随项目发布。
