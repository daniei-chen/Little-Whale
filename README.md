<div align="center">

<img src="https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/docs/icon.png" width="120" alt="小鲸鱼">

# 小鲸鱼

**粘贴分享链接，保存无水印原片**

<sub>抖音 · 小红书 · 哔哩哔哩 · 微博 · 快手 · 知乎 等 18 个平台</sub><br>
<sub>全程在手机本地解析 · 不上传链接 · 不需要服务器</sub>

<a href="https://github.com/daniei-chen/Little-Whale/actions/workflows/ci.yml">
  <img src="https://github.com/daniei-chen/Little-Whale/actions/workflows/ci.yml/badge.svg" alt="CI">
</a>

</div>

---

<div align="center">
  <img src="https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/docs/screenshot-home.png" width="270" alt="首页">
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/docs/screenshot-result.png" width="270" alt="解析结果">
  <br>
  <sub>左：首页 &nbsp;·&nbsp; 右：图文作品解析后逐张勾选</sub>
</div>

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [支持平台](#支持平台)
- [核心功能](#核心功能)
- [技术原理](#技术原理)
- [已知限制](#已知限制)
- [版本更新](#版本更新)
- [自行构建](#自行构建)
- [项目结构](#项目结构)
- [开发笔记](#开发笔记)
- [免责声明](#免责声明)

---

## 它解决什么问题

抖音、小红书这些平台，直接在 App 里点「保存到相册」，拿到的是**带水印**的版本，有的还会压缩画质。
网上那些「去水印」工具又大多要你把链接发给**别人的服务器**。

小鲸鱼把解析**放回你自己的手机里**：

- **不经过任何服务器** —— 链接没有任何地方可传，隐私上更放心
- **无水印原片** —— 走各平台的原始资源，不是压缩过的展示版
- **不依赖网络服务** —— 没有后端要维护，服务器挂了也能用
- **图文可多选** —— 默认全选，也能只挑几张，或预览时单独存一张
- **支持动图** —— 抖音 / 小红书的 Live Photo 可以存成带动效和音效的短视频

---

## 支持平台

一共 **18 个**，分两层。

### 核心平台（6 个）—— 平台专用适配器

每个都单独逆推过：**能拿无水印原片、能识别动图、速度快**。

| 平台 | 视频 | 图文 | 动图 | 实现方式 |
|:---:|:---:|:---:|:---:|---|
| **抖音** | ✅ | ✅ | ✅ | 视频走**手机分享页**取 `<video>` 直链；图文/动图从页面数据流 `__pace_f` 提取 |
| **小红书** | ✅ | ✅ | ✅ | 抓页面解析内嵌数据；图片换公开 CDN 节点去水印；动图取 `stream.h264` |
| **哔哩哔哩** | ✅ | ✅ | — | 视频走公开 API + wbi 签名；图文走专栏接口与图文动态（opus） |
| **微博** | ✅ | ✅ | ⚠️ | 借内置 WebView 的 Cookie 调接口；动图做了字段探测，未拿到实例验证 |
| **快手** | ✅ | ✅ | — | 手机分享页取 `<video>` 直链 |
| **知乎** | 需登录 | ✅ | — | 专栏页 DOM 提取 |

### 其他主流平台（12 个）—— 通用适配器

> 西瓜视频 · 今日头条 · 好看视频 · 微视 · 豆瓣 · 百度贴吧 · 腾讯视频 · 爱奇艺 · 优酷 · 芒果TV · 虎牙 · 斗鱼

**为什么单独一组**：实测这些平台的网页**全是 SPA** ——
首页 HTML 只有几 KB 的空壳，一个视频地址、一张内容图都没有，数据全靠 JS 渲染。
直接 HTTP 抓页面完全走不通。

而这个 App 内置了一个隐藏 WebView —— 让页面**真的跑起来**，再读渲染后的 DOM 就有内容了。
**加平台因此变成填配置**：

```dart
GenericLocalPlatform(
  key: 'ixigua',
  name: '西瓜视频',
  hosts: ['ixigua.com'],
  referer: 'https://www.ixigua.com/',
),
```

<details>
<summary><b>通用适配器的边界（点开）</b></summary>

- **拿不到无水印原图** —— 平台页面上给的就是带水印的流
- **识别不了动图**

**实测结果**（用真实内容页验证）：

| 平台 | 结果 |
|---|---|
| 好看视频 | ✅ 提取到视频地址 + 标题 |
| 虎牙 | ✅ 提取到内容图 |
| 优酷 | ✅ 提取到相关推荐图（正片取不到） |
| 百度贴吧 | ✅ 提取到内容图（**Node 直连 403，WebView 能过**） |
| 豆瓣 | ❌ 反爬拦截，连真实浏览器指纹的 WebView 也被挡 |
| 其余 | 尚未拿到真实分享链接，只验证了「识别 + 渲染机制」 |

**长视频平台取不到正片**：优酷 / 爱奇艺 / 腾讯视频 / 芒果TV 的视频是 **DRM 加密流**，
页面里根本没有可下载直链 —— 这是平台的内容保护，不是适配器的问题。

</details>

---

## 核心功能

### 无水印：各平台的具体处理

| 平台 | 水印 / 压缩从哪来 | 怎么去掉 |
|---|---|---|
| 小红书 | 图片地址末尾的 `!h5_1080jpg` 处理模板 | 去掉模板 + 换到公开 CDN 节点（31 KB 带水印 → 62 KB 原图） |
| 抖音 | `playwm`（带水印）vs `play`（无水印） | 换路径**并换域名**（`m.douyin.com` 上没有 `play` 口子） |
| 微博 | 接口返回的 `large.url` 其实是 `/mw2000/` 压缩版 | 换成 `/large/`（1.2 MB → 2.4 MB） |
| B站图片 | 图床地址带 `@1080w.webp` 这类处理后缀 | 去掉 `@` 之后的部分即为原图 |
| B站视频 | **平台自带水印，无法去除** | — |

### 动图（Live Photo）

只有**抖音**和**小红书**公开返回这种结构；哔哩哔哩 / 快手 / 知乎的数据里没有对应字段。

```jsonc
// 抖音：playAddr 是数组，字段名是 src
{
  "clipType": 5,
  "urlList": ["...douyinpic.com/...webp"],
  "video": {
    "duration": 2934,
    "playAddr": [{ "src": "https://...douyinvod.com/....mp4" }]
  }
}

// 小红书：stream.h264[0].masterUrl
{
  "livePhoto": true,
  "url": ".../notes_pre_post/xxx",
  "stream": {
    "h264": [{ "masterUrl": "https://...xhscdn.com/....mp4", "videoDuration": 2933 }]
  }
}
```

**保存方式四选一**（「我的 → 解析偏好 → 动图保存方式」）：

| 档位 | 产出 | 特点 |
|---|---|---|
| 短视频（默认） | `.mp4` | 保真：动效和声音都在，相册归到「视频」 |
| **动态照片**（v0.0.8 新增） | `.jpg`（单文件，内嵌原视频） | 相册里是**照片**，长按会动、带原声；**最接近平台原版动图**，但能否播放取决于系统相册 |
| **GIF 动图**（v0.0.7 新增） | `.gif` | 相册归到「图片」，能当表情直接发微信；**没有声音**、体积约 2~5 MB |
| 静态封面 | `.jpg` | 只存第一帧，最省空间 |

### 动态照片（Motion Photo）：怎么"复原"动图

动态照片不是新格式，就是把「静态封面」和「带音轨短视频」**重新装进一个文件**：

```
[ JPEG 图片数据 ... EOI ] [ 直接追加的 MP4 视频（含音轨） ]
                         ↑
  由 JPEG 的 APP1 段里一段 XMP 标明「从文件末尾倒数 N 字节开始是视频」
```

不支持的相册里它就是一张普通 jpg，支持的相册里长按才播放。**不需要抽帧、不需要转码**，
纯粹是字节拼接，所以体积 ≈ 原视频大小、画质无损、耗时秒级。

原生实现见 `android/app/src/main/kotlin/.../motionphoto/MotionPhotoWriter.kt`，要点：

- **新旧两套 XMP 字段同时写**。Android 动态照片有两套并行标准：
  - 旧标准 `GCamera:MicroVideo` + `MicroVideoOffset`（MIUI 等）
  - 新标准 `GCamera:MotionPhoto` + `Container:Directory`（三星、Pixel、HyperOS 3 起）
  两套语义重叠、互不冲突，一起写能最大化命中率。
- **XMP 插在 SOI + 可能的 JFIF APP0 之后**。JFIF 规范要求 APP0 紧跟 SOI，
  虽然多数解析器容忍 XMP 插在前面，但没必要冒险。
- **封面不是 JPEG 时自动重编码**（平台常给 webp/heic）。XMP 里声明的
  `Item:Mime` 是 `image/jpeg`，容器里就必须真的是 JPEG。
- `MicroVideoOffset` 与 `Container:Item[2]:Length` 都填**视频字节数** ——
  因为视频追加在末尾，从末尾倒数这么多字节正好是它的起点。

> **兼容性必须说清楚**：这是四档里**最依赖机型**的一档。据公开实测，
> 小米 HyperOS 3 用标准 XMP 就能识别第三方生成的动态照片；更老的 MIUI 和
> 其他品牌可能需要厂商私有元数据，可能只显示静态封面（不会坏，只是不动）。
> 所以默认档位仍是「短视频」，动态照片需要自己去设置里选，选完先试一张。

GIF 是**本地合成**的，三道工序都在手机上完成：

```
MediaMetadataRetriever 抽帧（8fps，OPTION_CLOSEST）
  → Canvas 等比缩放到 400 宽（强制 ARGB_8888）
  → NeuQuant 256 色量化 + LZW 编码 → .gif
```

> **抽帧必须用 `OPTION_CLOSEST`，不能用 `OPTION_CLOSEST_SYNC`。** 后者只返回关键帧，
> 而这类动图视频只有 2~3 秒、关键帧间隔 1~2 秒 —— 抽 20 帧会得到 2~3 张图重复 20 次，
> GIF 看起来"卡住不动"。pub.dev 上几个现成的「视频转 GIF」插件都踩了这个坑。
>
> 编码器是**内置的纯 Java 实现**（源自 Glide 的 `gif_encoder`，已本地修正一处
> Canvas 绘制对象写错的 bug），**没有引入任何 native `.so`**。

**为什么不做动图 WebP**：Android 的 `Bitmap.compress` 只能编静态 WebP，动图 WebP 必须
内置 libwebp 原生库。v0.0.6 刚为误报问题清理过原生库（见「关于安全扫描」），
不值得为一个动图功能再把 `.so` 引回来。GIF 是唯一零原生依赖、且所有相册和微信
都能直接播的格式。

### 老机型兼容：HEIC → JPEG

动图笔记的封面 CDN 返回 `image/heic`。Android 10+ 能解，但本 App 支持到 **Android 7**，
老设备解不了 —— 表现是「存进相册了却看不见」。

同一条地址加 `?imageView2/format/jpg` 就能拿到**等分辨率**的 JPEG
（实测 175 KB → 173 KB，只是换容器，不是压缩）。App 会自动判断并转换。

### 下载可靠性

- **断点续传** —— 大文件下一半断了能接着下
- **按文件头判定扩展名** —— 服务器会谎报 content-type。实测小红书视频返回 `video/mp4`，
  但文件头是 `ftypqt`（QuickTime），必须存成 `.mov` 才会出现在相册里
- **并发保存** —— 最多 3 张同时下（再高会被平台 CDN 限速，反而更慢）
- **缩略图按显示尺寸解码** —— 抖音原图宽 1440px，列表只显示 150px，不限制的话一张占约 8MB 内存

---

## 技术原理

核心是**在 App 里内置一个隐藏 WebView**，让平台自己的 JS 正常跑，
我们只在旁边拦截它发出的请求。

```
┌─ App ────────────────────────────────────────────────────┐
│                                                          │
│  普通平台 ──► dio 直连公开 API ──► 拿到媒体直链           │
│  (B站 / 小红书)                                           │
│                                                          │
│  难缠平台 ──► 隐藏 WebView ──► 执行页面 JS                │
│  (抖音 / 快手 / 微博 / 知乎 / 通用 12 个平台)              │
│                        │                                 │
│                        ├─ 注入钩子拦截 fetch / XHR        │
│                        ├─ 特征伪装（补桌面 Chrome 特征）   │
│                        └─ 读 DOM / 页面数据流              │
│                                                          │
│  下载 ──► 直连 CDN（带 Referer 过防盗链）                  │
│          断点续传 · 按文件头判定扩展名                      │
└──────────────────────────────────────────────────────────┘
                          ↓
                    保存到系统相册
```

### 隐藏 WebView 的几个关键点

**为什么需要特征伪装**：抖音会检测 `window.chrome`、插件列表、`navigator.userAgentData` 等
一堆只有真浏览器才有的东西。不补的话页面直接降级 —— 能打开、不报错，但一个数据都不给。

**为什么用 `runJavaScriptReturningResult` 而不是 `evaluateJavascript`**：
前者会等返回值，后者不等。而它**不会等 Promise** —— 所以获取数据用的是**页面内的同步 XHR**。

**导航竞态**：`loadRequest` 返回时页面**还没加载完**。只用固定等待的话，连着解析两条链接时
第二条会读到第一条的残留数据（实测踩过：解析抖音动图，出来的是上一条的 46 张图）。
现在的做法是导航前在当前文档打标记，等标记在新文档里消失才开始读。

---

## 已知限制

> 下面几条都是**平台策略**，不是没做。与其含糊地报「失败」，App 会给出**具体怎么办**的提示。

| 限制 | 说明 |
|---|---|
| **知乎回答页 / 视频** | 未登录打不开。实测首页 SSR 里 `zvideo` 全是空的 store 命名空间，接口清一色 401。知乎上不需要登录的只有**专栏文章** |
| **B站限流** | `-509` / `-352` 是 IP 级的，被拦时**网页也返回 1.3 KB 拦截页**（正常 50 KB）。App 已带 `buvid` 设备指纹 + 指数退避 2/4/8/16 秒 |
| **抖音图文偶发失败** | 风控会返回「不渲染图片」的降级页面。App 会自动重试一次 |
| **B站未登录最高 720P** | 要更高画质需要登录 |
| **长视频平台取不到正片** | 优酷 / 爱奇艺 / 腾讯视频 / 芒果TV 是 DRM 加密流 |

**遇到问题怎么办**：「我的 → 错误日志」里有本地记录，截图即可定位。
日志**只存在手机里，不会上传** —— 和这个 App 的隐私承诺一致。

---

## 版本更新

App 内建自动检查，**不需要用户翻墙、也不需要自建服务器**：

```
主清单  https://cdn.jsdelivr.net/gh/daniei-chen/Little-Whale@main/server/version.json
备用    https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/server/version.json
下载页  https://github.com/daniei-chen/Little-Whale/releases/latest
```

清单就是本仓库里的 [`server/version.json`](server/version.json)，经 jsDelivr 转发
（国内可直连）。**每次发版只要更新这个文件并推到 `main`，所有用户的 App 就会收到提示。**

三个地址在 `lib/config.dart` 里都有 `defaultValue`，可以用 `--dart-define` 覆盖成
自己的服务器，但**即使不覆盖也能正常工作**。

> **这条默认值是踩坑换来的**：v0.0.6 ~ v0.0.8 用的是裸 `String.fromEnvironment(...)`，
> 没注入就是空字符串，而 `UpdateService.check()` 遇到空地址**直接 return null** ——
> 于是「构建时忘了配地址」不报错也不警告，整个更新检测静默失效，用户永远等不到提示。
> 现在带了默认兜底，并且有一条回归测试专门盯着这件事。

两个清单源互补：

- **主源 jsDelivr** 国内可直连，但它有 CDN 缓存，发版后可能短时间返回旧清单
- **备用源 GitHub raw** 没有缓存，但国内时通时断

所以 `UpdateService` 的策略是：主源没给出「有新版」时，再问一次备用源 ——
正常情况不多花任何请求，缓存导致的漏更新也能被兜住。

发版后如果想让 jsDelivr 立刻更新，可以主动清一次缓存：

```bash
curl "https://purge.jsdelivr.net/gh/daniei-chen/Little-Whale@main/server/version.json"
```

- 启动 3 秒后静默检查，只有真有新版才弹窗
- 同一个版本 **24 小时内只提醒一次**
- 网络失败**静默跳过** —— 更新检查永远不打扰用户
- 点「立即更新」→ **打开浏览器下载页**，由系统下载器和系统安装流程接管

> **v0.0.6 起 App 不再自己下载安装包。**
> v0.0.5 及以前是「App 内下载 APK → FileProvider → 拉起系统安装器」，体验更好
> （带进度条、可续传）。但那需要 `REQUEST_INSTALL_PACKAGES` 权限 + FileProvider +
> `application/vnd.android.package-archive`，这套特征在国产安全引擎里和「推广/捆绑/
> 自我更新」类灰色软件完全重合 —— 它正是本项目被判 `a.gray.BulimiaTGen.f` 的
> 最大单一原因（见下方「关于安全扫描」）。代价只是少一次跳转，换整包脱离高危画像。

**为什么不用 GitHub 原始地址**：`raw.githubusercontent.com` 在国内被墙，
Release 附件走的 `objects.githubusercontent.com` 国内也基本连不上。

**为什么不用 Google 应用内更新**：国内设备大多没有 Google Play 服务。

### 签名说明

发布签名由 `android/key.properties` + `android/keystore/xiaojingyu.jks` 提供，
**两者都不进仓库**（已写入 `.gitignore`，含 `**/*.jks` 兜底）。

当前使用（v0.0.6 起）的证书：

| 项 | 值 |
|---|---|
| Subject | `CN=Little Whale, OU=Mobile, O=Little Whale Studio, L=Shenzhen, ST=Guangdong, C=CN` |
| 算法 | RSA 2048 / SHA256withRSA |
| 证书 SHA-256 | `f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827` |
| 签名方案 | APK Signature Scheme **v2 + v3**（minSdk 24，不需要 v1） |

签名历史与代价：

| 版本 | 签名 | 说明 |
|---|---|---|
| v0.0.1 ~ v0.0.3 | Android 调试证书（`CN=Android Debug`） | 被安全中心判高风险，必须换 |
| v0.0.5 | 正式证书（私钥已丢失） | 曾以为换签名就能解决报毒 —— **这个判断是错的**，一个月后病毒库更新，同一规则再次命中 |
| v0.0.6 起 | 上表的新证书 | 原私钥已无法找回，只能重新生成 |

> ⚠️ **三条必须记住的事**
>
> 1. **换签名 = 老用户必须卸载重装。** 已装 v0.0.5 及更早版本的设备无法覆盖升级，
>    会提示「应用未安装」。卸载会清空解析记录，**已保存到相册的图片/视频不受影响**。
> 2. **换签名并不能根治报毒。** 只是让新包进入一段观察期。真正的解法是
>    [误报申诉](docs/COMPLAINT-TENCENT.md) 加白 + 上架正规应用商店，详见
>    [安全说明](docs/SECURITY.md)。
> 3. **`android/keystore/xiaojingyu.jks` 必须离线备份。** 再丢一次，所有已装用户
>    都只能卸载重装，且无法挽回。

### 关于安全扫描（为什么会被判成"高危病毒"）

如果你是从 Releases 下载安装的，手机管家可能弹出红色警告：

```
发现风险：安装该应用存在高风险
【高风险】包含病毒：a.gray.BulimiaTGen.f
```

**这不是病毒。** 结论和完整证据见：

- **[docs/SECURITY.md](docs/SECURITY.md)** —— 面向用户：为什么会被报、能不能放心装、被拦截怎么办
- **[docs/SAFE-INSTALL.md](docs/SAFE-INSTALL.md)** —— 怎么核对哈希与签名、MIUI 拦截弹窗逐屏处理
- **[docs/COMPLAINT-TENCENT.md](docs/COMPLAINT-TENCENT.md)** —— 可直接提交给腾讯的误报申诉材料

一句话版本：`a.gray.*` 是腾讯移动安全实验室的**启发式灰色软件家族**，随病毒库分发给
小米/OPPO/vivo/华为的手机管家。它由「个人自签证书 + 未上架商店 + 具备下载并安装可执行
文件的能力 + 功能面较宽」这类**特征聚类**触发，不是扫到了恶意代码。

`docs/` 里有逐条可复现的自查命令。你也可以自己验证：本仓库全部源码开放，反编译 DEX
检索 `DexClassLoader` / `Runtime.exec` / 广告 SDK，都会是 0 命中。

**v0.0.6 针对这个判定做了 7 项整改**（详见 [CHANGELOG.md](CHANGELOG.md)），其中影响最大的是
彻底移除应用内安装 APK 的能力。但请理解：**整改能大幅降低命中概率，不等于 100% 不再报。**
最终判定权在厂商病毒库，根治要靠申诉加白或上架正规商店。

---

## 自行构建

```bash
# 环境：Flutter 3.35+ / JDK 17 / Android SDK 35+（minSdk 24 = Android 7.0）
git clone https://github.com/daniei-chen/Little-Whale.git
cd Little-Whale
flutter pub get

flutter analyze          # 应当零问题
flutter test             # 单元测试

# 直接构建：能跑，但**不带更新检查**
flutter build apk --release --target-platform android-arm64

# 要带更新检查，把地址通过 --dart-define 注入：
flutter build apk --release --target-platform android-arm64 \
  --dart-define=UPDATE_URL=https://<你的域名>/app/version.json \
  --dart-define=UPDATE_URL_ALT=https://cdn.jsdelivr.net/gh/<用户>/<仓库>@main/server/version.json \
  --dart-define=DOWNLOAD_PAGE=https://<你的域名>/app/
```

> 更新地址是**构建时注入**的，不写死在源码里 —— 因为源码公开，
> 写死等于把服务器地址印在网上。详见 `lib/config.dart` 的注释。

集成测试要连着真机或模拟器（WebView 是必需的）：

```bash
flutter test integration_test/local_parse_test.dart -d <设备ID>
```

---

## 项目结构

```
lib/
├── config.dart                版本号 + 更新地址（构建时注入）
├── data/
│   ├── platforms.dart         界面展示的平台元信息
│   └── local_store.dart       本地存储（历史 / 设置 / 统计）
├── local/                     ★ 本地解析引擎
│   ├── engine.dart            隐藏 WebView：钩子注入、响应拦截、特征伪装、导航竞态
│   ├── registry.dart          平台注册表（专用 6 + 通用 12）
│   ├── generic.dart           通用适配器（WebView 渲染 SPA 后提取）
│   ├── types.dart             统一结果模型
│   ├── douyin.dart            抖音（视频 / 图文 / 动图）
│   ├── xiaohongshu.dart       小红书（含 HEIC→JPEG）
│   ├── bilibili.dart          B站（视频 / 专栏 / 图文动态，含 wbi 签名）
│   ├── weibo.dart             微博
│   ├── kuaishou.dart          快手
│   └── zhihu.dart             知乎
├── services/
│   ├── download_service.dart  下载：断点续传、按文件头定后缀、动图转 GIF/动态照片
│   ├── gif_service.dart       动图视频 → GIF（走原生通道，纯本地）
│   ├── motion_photo_service.dart  封面+视频 → 动态照片（走原生通道，纯本地）
│   ├── update_service.dart    检查更新（只提示 + 开浏览器，不下载安装包）
│   └── crash_log.dart         本地错误日志
├── models/
│   ├── parse_result.dart      解析结果模型
│   └── motion_mode.dart       动图保存方式四档（短视频/动态照片/GIF/静态封面）
├── widgets/
│   ├── net_image.dart         带 Referer 的图片（列表一律用它）
│   └── image_viewer.dart      全屏预览
├── pages/                     首页 / 记录 / 我的
└── state/app_state.dart       全局状态

android/app/src/main/kotlin/.../MainActivity.kt   媒体转换的 MethodChannel
android/app/src/main/kotlin/.../gif/VideoToGif.kt 抽帧 + 缩放（OPTION_CLOSEST）
android/app/src/main/java/.../gif/                内置 GIF 编码器（纯 Java，源自 Glide）
android/app/src/main/kotlin/.../motionphoto/      动态照片封装（XMP 注入 + MP4 追加）
server/version.json                                更新清单（备用副本）
tools/
├── build.ps1                                        构建（只出 arm64-v8a）
├── release.ps1                                      一键发版
└── check.ps1                                        本地验证
docs/                                                README 用的图标与截图
```

---

## 开发笔记

这些是实际踩过的坑，记下来免得以后重犯。

<details>
<summary><b>平台相关的坑（点开）</b></summary>

**小红书未登录会跳登录墙** —— 但真实地址藏在 `redirectPath` 参数里，解出来再请求就行。
另外必须用**手机 UA**，桌面 UA 会被直接推到登录页。

**抖音视频要换入口** —— PC 页面上详情接口会被取消、拿不到数据。
换成**手机 UA** 打开同一链接，会跳到 `m.douyin.com/share/video/{id}`，
那里 `<video>` 标签直接挂着可下载的 mp4，而且 `playwm` 换成 `play` 就是无水印版。

**抖音图文不能用 DOM 抠** —— 轮播是懒加载的，而且**动图的视频地址根本不在 DOM 里**。
要读页面的 `__pace_f`（RSC 数据流），一次就带完整的 `images` 数组。

**抖音视频封面不能只取 `<video>.poster`** —— 手机分享页上那个属性是空的，
表现为「只有播放按钮、没有封面」。要按 `og:image → poster → 页面大图` 三级兜底。

**快手的 `playAddr` 是数组** —— 字段名是 `src` 不是 `urlList`。
一开始按对象处理，结果明明数据就在眼前却永远是 0 条。

**微博接口要带 `X-Requested-With`** —— 不带的话返回的是 HTML 不是 JSON，
解析一直失败却看不出原因。

**B站图文有两种形态** —— 专栏（`/read/cv{id}`）用 `x/article/view` 抠正文 `<img>`；
图文动态（`/opus/{id}`）要 **wbi 签名**，图片在 `major.draw.items[].src` 或 `major.opus.pics[].url`。

</details>

<details>
<summary><b>测试相关的坑（点开）</b></summary>

**「假通过」比崩溃更危险** —— 踩过两次：

- 快手视频退化成图集，但断言写的是「视频非空 **或** 图 > 0」，照样绿
- 微博测试翻不到带图微博就 `if` 跳过，图文路径**根本没被测**

现在的做法：断言收紧（必须 `type == 'video'`），并且给固定兜底 ID，**找不到就失败**。

**硬编码的测试 ID 会过期** —— 微博内容被删后，兜底 ID 失效导致测试一直红。
现在测试优先从热榜翻当时的微博，兜底 ID 只作备用。

**模拟器会杀进程** —— 内存紧张时 App 被 SIGKILL（logcat 里是 `signal 9`），
表现为「did not complete」。这是环境问题不是代码问题（同一测试单独跑 3/3 全过）。
稳定性脚本里加了「被杀自动重跑」，但**会记录重跑次数**，不让它掩盖真实的偶发 bug。

</details>

---

## 加一个平台要做什么

**走通用适配器**（大多数情况）：

在 `lib/local/registry.dart` 的 `all` 列表里加一条配置就行 —— 填域名和 referer。

**做专用适配器**（需要无水印或动图时）：

1. 在 `lib/local/` 实现一个 `LocalPlatform` 子类
   （`key` / `name` / `hosts` / `referer` / `parse`）
2. 在 `lib/local/registry.dart` 的 `all` 列表加一行
3. 在 `lib/data/platforms.dart` 的 `kPlatforms` 加一行（**界面上的平台标签**）

> 第 3 步最容易漏 —— 漏了的话解析其实已经支持，但界面上看不到，
> 用户会以为没做。所以有一条单元测试专门断言这两个列表一一对应。

---

## 免责声明

本工具仅供**个人学习与内容备份**使用。

请勿用于商业传播或二次分发他人作品。下载内容的版权均归原作者所有，请尊重创作者。
