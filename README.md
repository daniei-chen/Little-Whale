<div align="center">
  <img src="https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/docs/icon.png" width="118" alt="小鲸鱼">
  <h1>小鲸鱼</h1>
  <p><b>粘贴分享链接，保存无水印原片</b></p>
  <p>
    <sub>抖音 · 小红书 · 哔哩哔哩 · 微博 · 快手 · 知乎</sub><br>
    <sub>全程在手机本地解析 · 不上传链接 · 不需要服务器</sub>
  </p>
  <p>
    <a href="https://github.com/daniei-chen/Little-Whale/actions/workflows/ci.yml"><img src="https://github.com/daniei-chen/Little-Whale/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  </p>
</div>

---

<div align="center">
  <img src="https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/docs/screenshot-home.png" width="280" alt="首页">
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/docs/screenshot-result.png" width="280" alt="解析结果">
  <br>
  <sub>左：首页 &nbsp;|&nbsp; 右：图文作品解析后逐张勾选</sub>
</div>

---

## 下载

**从本仓库的 [Releases](https://github.com/daniei-chen/Little-Whale/releases) 页面下载最新版 APK。**

> 国内直连 GitHub 的下载域名不稳定，如果下不动，请走 App 内的更新提示，
> 或联系分发者获取直连地址。

---

## 它解决什么问题

抖音、小红书这些平台，直接在 App 里「保存到相册」拿到的是**带水印**的版本，
有的还会压缩画质。网上那些"去水印"工具又大多要你把链接发给**别人的服务器**。

小鲸鱼把解析**放回你自己的手机里**：

- 🚫 **不经过任何服务器** —— 链接没有任何地方可传
- 🎬 **无水印原片** —— 走各平台的原始资源，不是压缩过的展示版
- 📵 **不依赖网络服务** —— 没有后端要维护
- 🖼️ **图文可多选** —— 默认全选，也能只挑几张，或预览时单独存一张
- 🎞️ **动图支持** —— 抖音的动图作品可以存成**带动效和音效的短视频**

---

## 支持平台

| 平台 | 视频 | 图文 | 动图 | 怎么做到的 |
|:---:|:---:|:---:|:---:|---|
| **抖音** | ✅ | ✅ | ✅ | 视频走**手机分享页**取 `<video>` 直链；图文/动图从页面数据流 `__pace_f` 提取 |
| **小红书** | ✅ | ✅ | ✅ | 抓页面解析内嵌数据；图片换公开 CDN 节点去水印；动图取 `stream.h264` |
| **哔哩哔哩** | ✅ | ✅ | — | 视频走公开 API + wbi 签名；图文走专栏接口与图文动态（opus） |
| **微博** | ✅ | ✅ | ⚠️ | 借内置 WebView 的 Cookie 调接口；动图做了字段探测，未拿到实例验证 |
| **快手** | ✅ | ✅ | — | 手机分享页取 `<video>` 直链 |
| **知乎** | 需登录 | ✅ | — | 专栏页 DOM 提取（**回答页与视频都要登录**，见下） |

> **关于「动图」** = Live Photo（静态封面 + 一段带音轨的短视频）。
> 实测只有**抖音**和**小红书**公开返回这种结构；哔哩哔哩 / 快手 / 知乎的数据里
> 没有对应字段，所以标 `—` —— **不是没做，是平台没有**。
> 微博标 ⚠️ 是因为做了通用字段探测（有就支持、没有就照旧），
> 但手上没有真实动图微博可供验证。

### 关于水印：各平台的具体处理

| 平台 | 水印/压缩从哪来 | 怎么去掉 |
|---|---|---|
| 小红书 | 图片地址末尾的 `!h5_1080jpg` 处理模板 | 去掉模板 + 换到公开 CDN 节点（31 KB 带水印 → 62 KB 原图） |
| 抖音 | `playwm`（带水印）vs `play`（无水印） | 换路径**并换域名**（`m.douyin.com` 上没有 `play` 口子） |
| 微博 | 接口返回的 `large.url` 其实是 `/mw2000/` 压缩版 | 换成 `/large/`（1.2 MB → 2.4 MB） |
| B站图片 | 图床地址带 `@1080w.webp` 这类处理后缀 | 去掉 `@` 之后的部分即为原图 |
| B站视频 | **平台自带水印，无法去除** | — |

### 小红书动图还多一步：HEIC → JPEG

动图笔记的封面 CDN 返回 `image/heic`。Android 10+ 能解，但本 App 支持到
**Android 7**，老设备解不了 —— 表现是「存进相册了却看不见」。
同一条地址加 `?imageView2/format/jpg` 就能拿到**等分辨率**的 JPEG
（实测 175 KB → 173 KB，只是换容器，不是压缩）。App 会自动判断并转换。

---

## 已知限制

> 下面几条都是**平台策略**，不是没做。与其含糊地报「失败」，
> App 里会根据情况给出**具体怎么办**的提示。

**知乎需要登录的两类内容**
- **回答页**（`zhihu.com/question/…/answer/…`）—— 未登录打不开
- **知乎视频**（`zhihu.com/zvideo/…`）—— 未登录时知乎**不返回任何视频内容**
  （实测：首页 SSR 里 `zvideo` 全是空的 store 命名空间，相关接口清一色 401）

知乎上不需要登录的只有**专栏文章**（`zhuanlan.zhihu.com/p/…`）。
App 内遇到这两类链接会直接告诉用户换专栏链接。

**B站限流会自动重试**
B站对专栏/动态接口有频率风控（`-509`），连着解析几篇就会撞上。
App 会指数退避重试（1.5s → 3s → 6s），专栏还会**自动改走网页 SSR**。

**抖音图文偶尔失败一次**
抖音的风控会悄悄返回「不渲染图片」的降级页面。App 会自动重试一次。

**B站未登录最高 720P**，要更高画质需要登录 —— 本地解析不做这件事。

**遇到问题怎么办**
「我的 → 错误日志」里有本地记录，截图即可定位。日志只存在手机里，不会上传。

---

## 技术实现

核心是**在 App 里内置一个隐藏的 WebView**，让平台自己的 JS 正常跑，
我们只在旁边拦截它发出的请求 —— 服务端方案是同一套思路，只是把浏览器
从服务器搬进了手机。

```
┌─ App ────────────────────────────────────────────────┐
│                                                      │
│  普通平台 ──► dio 直连公开 API ──► 拿到媒体直链       │
│  (B站/小红书)                                         │
│                                                      │
│  难缠平台 ──► 隐藏 WebView ──► 执行页面 JS            │
│  (抖音/快手/微博/知乎)   │                            │
│                          ├─ 注入钩子拦截 fetch / XHR  │
│                          ├─ 特征伪装（补桌面 Chrome 特征）│
│                          └─ 读 DOM / 页面数据流        │
│                                                      │
│  下载 ──► 直连 CDN（带 Referer 过防盗链）              │
│          断点续传 · 按文件头判定扩展名                  │
└──────────────────────────────────────────────────────┘
                    ↓
              保存到系统相册
```

### 几个踩过的坑

- **抖音图文**要读页面的 `__pace_f` 数据流，而不是抠 DOM —— DOM 是懒加载的，
  而且**动图的视频地址根本不在 DOM 里**
- **抖音动图**的视频在 `video.playAddr`，它是**数组**且字段叫 `src`（不是 `urlList`）
- **界面上的图片要带 Referer**，否则平台 CDN 403，表现是「解析成功但封面空白」
- **快手**偶发返回降级页（没有 `<video>`），只拿到图时要重试一次
- **扩展名要按文件头判定** —— 小红书视频服务器谎报 `video/mp4`，实际是 QuickTime

---

## 自行构建

```bash
# 环境：Flutter 3.35+ / JDK 17 / Android SDK 35+（minSdk 24）
git clone https://github.com/daniei-chen/Little-Whale.git
cd Little-Whale
flutter pub get

flutter analyze          # 应当零问题
flutter test             # 单元测试

# 直接构建：能跑，但不带更新检查
flutter build apk --release --split-per-abi

# 要带更新检查，把地址通过 --dart-define 注入：
flutter build apk --release \
  --dart-define=UPDATE_URL=https://<你的域名>/app/version.json \
  --dart-define=DOWNLOAD_PAGE=https://<你的域名>/app/
```

> 更新地址是**构建时注入**的，不写死在源码里 —— 因为源码公开，
> 写死等于把服务器地址印在网上。详见 `lib/config.dart` 的注释。

集成测试要连着真机或模拟器（WebView 是必需的）：

```bash
flutter test integration_test/local_parse_test.dart -d <设备ID>
```

<details>
<summary><b>项目结构</b>（点开）</summary>

```
lib/
├── config.dart                版本号 + 更新地址（构建时注入）
├── local/                     ★ 本地解析引擎
│   ├── engine.dart            隐藏 WebView：注入钩子、拦截响应、特征伪装
│   ├── registry.dart          平台注册表
│   ├── types.dart             统一结果模型
│   ├── douyin.dart            抖音（视频 / 图文 / 动图）
│   ├── xiaohongshu.dart       小红书
│   ├── bilibili.dart          B站
│   ├── weibo.dart             微博
│   ├── kuaishou.dart          快手
│   └── zhihu.dart             知乎
├── services/
│   ├── download_service.dart  下载：断点续传、按文件头定后缀
│   ├── update_service.dart    检查更新
│   └── crash_log.dart         本地错误日志
├── widgets/
│   └── net_image.dart         带 Referer 的图片（列表一律用它）
├── pages/                     首页 / 记录 / 我的
└── state/app_state.dart       全局状态

server/version.json            更新清单（备用副本，经 jsDelivr 分发）
tools/
├── release.ps1                一键发版
├── check.ps1                  本地验证
└── build.config.example.ps1   构建配置示例
```

</details>

---

## 加一个平台要做什么

1. 在 `lib/local/` 实现一个 `LocalPlatform` 子类
   （`key` / `name` / `hosts` / `referer` / `parse`）
2. 在 `lib/local/registry.dart` 的 `all` 列表加一行
3. 在 `lib/data/platforms.dart` 的 `kPlatforms` 加一行（**界面上的平台标签**）

> 第 3 步最容易漏 —— 漏了的话解析其实已经支持，但界面上看不到，
> 用户会以为没做。所以有一条单元测试专门断言这两个列表一一对应。

---

## 免责声明

本工具仅供**个人学习与内容备份**使用。

请勿用于商业传播或二次分发他人作品。下载内容的版权均归原作者所有，
请尊重创作者。
