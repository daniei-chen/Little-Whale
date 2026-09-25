# 🐋 小鲸鱼

> 粘贴分享链接，保存**无水印原片**。全程在手机本地完成，**不上传链接、不需要服务器**。

支持 **抖音 / 小红书 / 哔哩哔哩 / 微博 / 快手 / 知乎** 六个平台。

---

## 📥 下载安装

### 主渠道：官网（推荐）

👉 **https://whale.kaogong.art/app/**

国内服务器，直连快且稳，20MB 大约几秒。

### 备用：GitHub Releases

如果上面那个打不开（服务器维护等），可以从本仓库的
[Releases](https://github.com/daniei-chen/Little-Whale/releases) 下载。

> ⚠️ **GitHub 在国内不翻墙基本下不动**，原因：
>
> | 域名 | 用途 | 国内直连 |
> |---|---|---|
> | `github.com` | 网页 | ⚠️ 时好时坏 |
> | **`objects.githubusercontent.com`** | **Release 附件（APK 就在这）** | ❌ **基本连不上** |
> | `raw.githubusercontent.com` | 代码 / raw | ❌ 被墙 |
>
> 所以 **官网才是主渠道**，GitHub 只是多一个备份 + 给海外用户用。

---

## 更新机制

App 内建自动检查更新，**不需要用户翻墙**：

```
主地址   https://whale.kaogong.art/app/version.json          ← 自己的服务器
备用地址 https://cdn.jsdelivr.net/gh/daniei-chen/Little-Whale@main/server/version.json
                    ↑ jsDelivr 转发 GitHub 上的同一个文件（国内实测可直连）
```

两个地址**任一可用**就能检查到更新 —— 单一渠道挂掉不影响用户。

流程：App 启动 3 秒后静默拉清单 → 比对 build 号 → 有新版弹窗 →
点「立即更新」跳官网下载页。

同一个版本 24 小时内只提醒一次；网络失败静默跳过，**永远不打扰用户**。

### 为什么不用 GitHub Releases 做更新源

因为 App **检查不到、也下不动**（原因见上表）。
也考虑过 Google 的应用内更新，但国内设备大多没有 Google Play 服务。

### 发版

```powershell
.\tools\release.ps1 -Notes "新增快手、知乎"
```

自动改版本号（`pubspec.yaml` / `lib/config.dart` / `server/version.json` 三处同步）→
跑检查和测试（不过就拒绝发版）→ 构建 APK → 提交推送。

**推完之后还要做两件事**（脚本会在结尾提醒）：

1. 把 APK 传到服务器：`/var/www/whale.kaogong.art/app/download/`
2. 把 `server/version.json` 的内容同步到
   `/var/www/whale.kaogong.art/app/version.json`

> 服务器上的清单是**主**，仓库里那份是 jsDelivr 用的**备用副本**，两边要保持一致。

---

## 功能

| 平台 | 视频 | 图文 | 备注 |
|---|---|---|---|
| 抖音 | ✅ | ✅ | 视频走手机分享页取直链；图文从 DOM 抠图 |
| 小红书 | ✅ | ✅ | 视频用原始上传对象；图片换公开 CDN 节点 |
| 哔哩哔哩 | ✅ | — | 公开 API + wbi 签名；未登录最高 720P |
| 微博 | ✅ | ✅ | 借 WebView 的 Cookie 调接口 |
| 快手 | ✅ | ✅ | 手机分享页取 `<video>` 直链 |
| 知乎 | 专栏 | ✅ | **回答页需登录**，专栏文章不需要 |

### 核心特点

- **无水印**：所有平台都取原片。小红书去掉 `!h5_1080jpg` 处理模板、抖音 `playwm`→`play` 并换域名、微博 `/mw2000/`→`/large/`
- **不依赖服务器**：解析全程在手机里跑（内置隐藏 WebView + dio 直连）
- **链接不外传**：没有服务端，链接没有任何地方可传
- **图片可多选**：图文作品默认全选，也能只挑几张，或预览时单独存一张
- **下载稳**：大文件支持断点续传；扩展名按**真实文件头**判定（服务器会谎报 content-type）

---

## 已知限制

**知乎回答页**（`zhihu.com/question/…/answer/…`）需要登录，本地打不开。
请用**专栏文章**链接（`zhuanlan.zhihu.com/p/…`）。App 内会直接提示。

**抖音图文偶尔失败一次**。这是抖音的风控 —— 短时间解析太频繁时，
它会悄悄返回一个「不渲染图片」的降级页面（页面能打开、不报错，就是没图）。
App 会自动重试一次。

**B站视频自带水印**，这是平台行为，无法去除。

---

## 更新机制（国内可用）

> 上面「更新机制」一节已经讲过了，这里只留服务器部署要点。

服务器上的目录结构：

```
/var/www/whale.kaogong.art/
├── index.html                        跳转到 /app/
└── app/
    ├── index.html                    下载页
    ├── icon.png                      下载页上的图标
    ├── version.json                  ★ 更新清单（App 主地址读这个）
    └── download/
        └── xiaojingyu-0.0.1-arm64-v8a.apk
```

Nginx 配置在 `/etc/nginx/sites-available/whale.kaogong.art`，
HTTPS 由 certbot 签发并自动续期。

**发版后要做的两步**：

```bash
# 1. 传 APK
scp 新包.apk xiaochen:/var/www/whale.kaogong.art/app/download/xiaojingyu-新版本-arm64-v8a.apk

# 2. 同步更新清单（两个地方都要改，保持一致）
#    · 服务器：/var/www/whale.kaogong.art/app/version.json
#    · 仓库：  server/version.json   （jsDelivr 备用地址读这份）
```

---

## 自行构建

```bash
# 环境：Flutter 3.35+ / JDK 17 / Android SDK 35
flutter pub get
flutter analyze          # 应当零问题
flutter test             # 单元测试
flutter build apk --release --split-per-abi
```

集成测试需要连着真机或模拟器：

```bash
flutter test integration_test/local_parse_test.dart -d <设备ID>
```

---

## 项目结构

```
lib/
├── config.dart              版本号、更新清单地址
├── local/                   ★ 本地解析引擎
│   ├── engine.dart          隐藏 WebView：注入钩子、拦截响应、特征伪装
│   ├── registry.dart        平台注册表（加平台只要在这加一行）
│   ├── types.dart           统一的结果模型
│   ├── douyin.dart          抖音（视频走手机分享页 / 图文抠 DOM）
│   ├── xiaohongshu.dart     小红书（HTTP 抓页面 + 无水印地址替换）
│   ├── bilibili.dart        B站（公开 API + wbi 签名）
│   ├── weibo.dart           微博（页面内同步 XHR 带 Cookie）
│   ├── kuaishou.dart        快手（手机分享页）
│   └── zhihu.dart           知乎（专栏页 DOM）
├── services/
│   ├── download_service.dart  下载：断点续传、按文件头定后缀
│   └── update_service.dart    检查更新
├── pages/                   首页 / 记录 / 我的
└── state/app_state.dart     全局状态

server/version.json          更新清单（jsDelivr 从这里读）
tools/release.ps1            一键发版
```

---

## 加一个平台要做什么

1. 在 `lib/local/` 下实现一个 `LocalPlatform` 子类（`key` / `name` / `hosts` / `referer` / `parse`）
2. 在 `lib/local/registry.dart` 的 `all` 列表里加一行
3. 在 `lib/data/platforms.dart` 的 `kPlatforms` 里加一行（**界面上那排标签**）

第 3 步容易漏 —— 漏了的话解析其实已经支持，但用户看不到，以为没做。
所以有一条单元测试专门断言这两个列表一一对应（`平台列表一致性`）。

---

## 免责声明

本工具仅供**个人学习与内容备份**使用。
请勿用于商业传播或二次分发他人作品，下载内容的版权均归原作者所有。
