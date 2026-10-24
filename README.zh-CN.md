<p align="center">
  <img src="docs/assets/quark-idle.gif" alt="Particle Library Quark" width="150">
</p>

# Particle Library

<p align="center">
  <a href="https://github.com/fkguo/Particle-Library/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/fkguo/Particle-Library?style=flat-square"></a>
  <a href="https://github.com/fkguo/Particle-Library/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/fkguo/Particle-Library/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/fkguo/Particle-Library/blob/main/LICENSE"><img alt="License: MPL-2.0" src="https://img.shields.io/github/license/fkguo/Particle-Library?style=flat-square"></a>
  <a href="https://doi.org/10.5281/zenodo.23460981"><img alt="DOI" src="https://zenodo.org/badge/DOI/10.5281/zenodo.23460981.svg"></a>
  <a href="https://testflight.apple.com/join/my27SMAt"><img alt="TestFlight beta" src="https://img.shields.io/badge/TestFlight-public%20beta-blue?style=flat-square&logo=apple"></a>
  <img alt="macOS 12+" src="https://img.shields.io/badge/macOS-12%2B-blue?style=flat-square&logo=apple&logoColor=white">
  <img alt="Android 7.0+" src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?style=flat-square&logo=android&logoColor=white">
  <img alt="PDG 2026" src="https://img.shields.io/badge/PDG-2026-8A2BE2?style=flat-square">
  <a href="https://github.com/fkguo/Particle-Library/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/fkguo/Particle-Library/total?style=flat-square&label=downloads"></a>
</p>

[English](README.md) | **简体中文**

Particle Library 是一个离线应用，用于 Particle Data Group 的 *Review of Particle Physics*，支持笔记、文献、PDF 综述和批注。PDG 数据快照保持只读且保存在本机，笔记、Collection、收藏和 PDF 批注与数据分开存储。

第一版是在周末使用 **DeepSeek Harness** 与 **DeepSeek-V4.1-Flash-1017** 构建的。

**支持平台：** macOS 12+（通用二进制）、iPhone/iPadOS 15+，以及 Android 7.0+（API 24，预览 APK；arm64 已在真机测试）。各平台共享 Flutter 响应式布局。

**iPhone/iPad 公开 TestFlight beta：**
[加入测试](https://testflight.apple.com/join/my27SMAt)。TestFlight 是预发布版本，可能比最新正式版更新。

## 截图

| χc1(3872) | π 电极化率 |
| --- | --- |
| <img src="docs/assets/screenshots/desktop-x3872.jpg" alt="χc1(3872) 粒子页" width="640"> | <img src="docs/assets/screenshots/desktop-polarizability.jpg" alt="π 电极化率测量页" width="640"> |
| 粒子页：左侧页面目录、身份、量子数与右侧上下文栏。 | 测量页：左侧目录、定义、来源、PDG 平均和右侧上下文栏。 |

| iPhone |
| --- |
| <img src="docs/assets/screenshots/iphone-search.jpg" alt="iPhone 上的 Particle Library 搜索页" width="300"> |
| iPhone 响应式布局。 |

英文界面、PDG 2026 数据快照；桌面为深色主题，iPhone 为浅色主题。

## 功能

- **离线 PDG 数据**：只读 SQLite 快照，SHA-256 完整性校验、首次启动安装、schema 校验和原始字段查看。
- **搜索与导航**：粒子名与别名、希腊字母/LaTeX 写法、MC 编号、PDG 标识符、专题、衰变、文献和自由文本搜索。
- **综述全文检索**：离线检索 121 篇 PDG 综述全文，跳转到命中页，并显示所在节标题和表格/图注。
- **条目页面**：粒子、专题、衰变模式、系列/性质和文献页面，包含汇总、全部测量、误差、脚注、历史、文献和原始记录。
- **数据语义**：区分 PDG Average / PDG Fit；保留 limit、range、CL、scale factor 和 used-in-average/fit 等字段，不擅自归一化。
- **数学排版**：PDG ASCII 表达式、粒子符号、衰变方程和单位在无歧义时排版为数学；否则保留原文。
- **历史与趋势**：按版次查看汇总值和带非对称误差的趋势图。
- **笔记**：本机 Markdown 笔记，支持锚点、反向链接、Collection、标签、搜索、JSON/Markdown 导入/导出和冲突保护；所有“加入笔记”入口共用同一个选择器。
- **标签**：跨笔记筛选、浏览、重命名和删除。
- **完整备份**：一个 ZIP 包含设置、收藏、笔记、高亮 anchor 和已缓存综述 PDF；导入自动识别格式并安全合并；移动端导出会打开系统分享面板。
- **文献**：本地文献信息、可选 Crossref 题名补全、INSPIRE 搜索、BibTeX/cite key 和 Zotero 本地桥接。
- **Zotero 索引（仅 macOS 桌面）**：手动构建/更新的本地 Zotero 条目缓存，避免 INSPIRE 结果逐条请求。
- **PDG 综述**：按需缓存 PDF、选择性清理、PDF 文字高亮；高亮直接存为带 review anchor 的本地笔记，可搜索、打标签、导出，并显示在右侧批注栏。
- **PDF 高亮即笔记**：每条高亮都是一个带综述锚点的普通本地笔记，搜索、标签、反向链接、导出和回收站直接复用，不需要第二套批注数据库。
- **桌面工作区**：可独立收起的左侧页面目录和右侧上下文栏、可拖拽分栏、移动端紧凑布局。
- **双语界面**：中文/英文界面，支持跟随系统、浅色/深色主题。
- **更新检查**：后台检查新版本，Settings → About 也可手动“检查更新”，提示后打开下载页面。

## 环境要求

- macOS 12 或更高版本（通用二进制；已在 macOS 15.6 Apple Silicon 验证）；
- iOS/iPadOS 15 或更高版本；
- Android 7.0+（API 24）预览版 APK。

正式发布包会内置 PDG 快照。只有从源码构建才额外需要 Flutter/Xcode 和快照文件；这些是**贡献者**要求，见 [BUILDING.md](docs/development/BUILDING.md)。

源码构建可从 PDG 官方下载本版本使用的快照：

- [pdgall-2026.0.sqlite](https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite)
- [PDG API 下载页](https://pdg.lbl.gov/2026/api/index.html)

## 安装

打开 **[最新 Release](https://github.com/fkguo/Particle-Library/releases/latest)**。

- **macOS 12+（通用二进制）**：下载
  `Particle-Library-*-macOS-universal.dmg`（或 `.zip`）。当前为 ad-hoc
  签名、未公证；运行前请核对 `SHA256SUMS.txt`。

  **首次打开被 macOS 拦截时**，任选一种：

  ```text
  右键点击 App → 打开 → 仍要打开
  ```

  或：

  ```text
  系统设置 → 隐私与安全性 → 仍要打开
  ```

  这是因为应用未经过 Apple 公证，属于预期提示。不要全局关闭 Gatekeeper。
- **iPhone/iPad（TestFlight beta）**：通过公开链接加入测试：
  [testflight.apple.com/join/my27SMAt](https://testflight.apple.com/join/my27SMAt)。

  1. 从 App Store 安装 **TestFlight**。
  2. 在 iPhone/iPad 上打开链接，点 **Accept**。
  3. 在 TestFlight 中安装 **Particle Library** 并打开。

  需要 iOS/iPadOS 15+ 和 Apple ID。更新通过 TestFlight 推送；构建 90 天后过期。
  这是 TestFlight 预发布 beta；App Store 分发另行处理。这个 TestFlight 链接只
  覆盖 iPhone/iPad；macOS 和 Android 通过 GitHub Releases 分发。
- **Android 7.0+（API 24）**：Release 中提供已签名预览 APK，现代手机/平板用
  `Particle-Library-*-Android-arm64-v8a.apk`；32 位设备不再构建。详见
  [Android 构建说明](docs/development/ANDROID.md)。

  **Android 0.2.0 起使用新的签名 key。** 0.1.x 的 key 已丢失，Android 会把
  0.2.x 当成不同应用，不能覆盖 0.1.x；0.2.x 之间可以覆盖升级。卸载旧版前：
  在 0.1.x 打开 设置 → 数据 → 导出完整备份；卸载旧版，安装当前 0.2.x，
  再导入备份。不备份直接卸载会删除本地笔记，且 Android 自动备份关闭。
- **Windows/Linux/web**：本版本未构建。

macOS 版已内置 PDG 快照，发布包对普通用户是自包含的。源码构建者可直接下载
[`pdgall-2026.0.sqlite`](https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite)（
[PDG 官方 API 页面](https://pdg.lbl.gov/2026/api/index.html)）。

内置快照是官方 PDG 原始文件；应用打开前会校验固定的 SHA-256，哈希和构建步骤见
[`assets/README.md`](assets/README.md)。应用另外内置两个独立的只读派生资产：

- `pdg_notes_2026.sqlite`：pdgLive 额外补充内容——条目说明与旧名注释、
  209 条 pdgLive 相关文献及其 INSPIRE 记录号/cite key、引用关系，以及条目→综述链接；
- `review_index_2026.sqlite`：由 121 篇 PDG 综述 PDF 构建的页面级全文索引。

这 209 条是 pdgLive 注释实际引用的文献；官方库的其他文献由应用按需向 INSPIRE
获取 BibTeX/cite key。

## 从源码构建

- [构建说明（英文）](docs/development/BUILDING.md)
- [平台支持矩阵（英文）](docs/development/PLATFORMS.md)

macOS 已验证的简短流程：

```bash
# 先下载官方快照；详见 assets/README.md：
# curl -LO https://pdg.lbl.gov/2026/api/pdgall-2026.0.sqlite
# mv pdgall-2026.0.sqlite assets/
flutter pub get
flutter test
flutter build macos --release
open "build/macos/Build/Products/Release/Particle Library.app"
```

## 测试

```bash
flutter analyze
flutter test
```

测试覆盖快照契约、显示语义、数学解析、笔记/标签、PDF 批注坐标与持久化、Zotero 缓存解析和 UI 辅助逻辑。测试默认离线；联网测试需显式开启。

## 本机数据与隐私

- PDG 快照只读并校验哈希；
- 笔记保存在应用支持目录中的独立 SQLite 数据库；设置、收藏和最近搜索保存在同一目录的 JSON 文件中；
- Zotero 索引也保存在应用支持目录；
- PDG 综述 PDF 按需从 PDG 网站下载；
- Zotero 仅通过 `http://127.0.0.1:23119` 只读访问，且仅桌面版可用；索引仅在设置中手动刷新时更新；
- 更新检查在启动时和手动点击时访问 jsDelivr、raw.githubusercontent.com 和 GitHub Releases API；这会将 IP 地址披露给这些服务，但不会自动安装更新。iOS 更新通过 TestFlight（或上架后的 App Store）交付；
- 不使用遥测、分析或账户服务，也没有相关计划。

## 仓库结构

```text
lib/            Flutter 应用
test/           单元与 widget 测试
assets/         图标/主题资源；PDG 快照需自行提供
macos/          macOS runner
ios/            iOS runner
android/        Android runner 与发布签名
tool/           发布/打包辅助脚本
docs/           构建、发布与用户文档
```

## 引用

如果在学术工作中使用 Particle Library，请引用 Particle Data Group 最新版的
*Review of Particle Physics*：

```text
F. Takahashi et al. (Particle Data Group),
Review of Particle Physics,
Int. J. Mod. Phys. A 41, 2630011 (2026).
https://doi.org/10.1142/S0217751X26300115
```

本应用也有一个始终指向最新归档版本的 DOI：

```text
Guo, Feng-Kun. Particle Library.
Zenodo. https://doi.org/10.5281/zenodo.23460981
```

GitHub 也会通过 [`CITATION.cff`](CITATION.cff) 展示这些引用元数据。

## 文档

- [文档索引（英文）](docs/README.md)
- [构建说明（英文）](docs/development/BUILDING.md)
- [Android 构建说明（英文）](docs/development/ANDROID.md)
- [平台支持矩阵（英文）](docs/development/PLATFORMS.md)
- [许可说明（英文）](docs/development/LICENSING.md)
- [更新检查（英文）](docs/development/UPDATES.md)
- [发布流程（英文）](docs/development/RELEASING.md)
- [隐私政策（英文）](docs/app-store/PRIVACY.md)

构建、平台、发布、许可、更新和隐私文档为英文；用户 README 中英双语。

## License

- **应用代码**：Mozilla Public License 2.0（MPL-2.0），见 [LICENSE](LICENSE)。Copyright 2026 Particle Library contributors。
  源码：<https://github.com/fkguo/Particle-Library>。
- **PDG 数据快照**：CC BY 4.0，需保留 Particle Data Group 署名；MPL-2.0 不覆盖数据。
- **PDG 综述 PDF**：从 PDG 按需下载，并受 PDG 条款约束。
- **第三方依赖**：见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

Particle Library 是独立项目；PDG 数据按 CC BY 4.0 使用并署名。
