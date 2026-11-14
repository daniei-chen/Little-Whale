# 更新日志

## v0.1.1 — 2026-11-15

> 签名与 v0.1.0 相同（都是 Android 调试证书）。**已装 v0.1.0 可直接覆盖安装**。
> 从 v0.0.9 及更早升级仍需先卸载（签名不同）。

### 修好了一个「假测试」

`integration_test/save_test.dart` 还是服务器模式时代的代码：它先请求
`http://10.0.2.2:8787` 的后端、断言媒体地址是带签名的 `/media?...` 代理地址。
而服务器模式早已整体移除 —— 这个文件**从来跑不过，也没人再跑**。
更糟的是它给了后来者一个错误印象：「保存链路有测试守着」。

现在重写成真实的产品路径：**本地解析 → 下载直链 → 写进系统相册 → 临时文件清理**，
并把「扩展名判定」这张表逐条钉住（MP4 / QuickTime / WebM / JPG / PNG / WebP / GIF + 认不出的情况）。
扩展名判定正是「提示保存成功、相册里却找不到」那个老问题的根源，值得单独守住。

### 通用适配器的标题不再拿广告语当标题

实测 12 个通用平台里有 4 个的「标题」其实是站点标语：

| 平台 | 改之前 | 改之后 |
|---|---|---|
| 优酷 | 高清完整正版视频在线观看-优酷 | 高清完整正版视频在线观看 |
| 虎牙 | 永劫无间赛事官方直播间-永劫无间-虎牙直播 | 永劫无间赛事官方直播间-永劫无间 |
| 今日头条 | （未提取到内容） | 在毕节吃啥？超全美食攻略来了！ |
| 爱奇艺 | 爱奇艺-在线视频网站-海量正版高清视频在 | 同左（`og:title` 本身就是这句，页面上没有内容标题可取） |

取值顺序改成：页面标题节点 → h1 → `og:title` → `description` → `document.title`，
每一步都检查「像不像站点标语」，像就继续往下找；最后统一去掉「- 站点名」后缀。
通用平台的渲染提取率同时从 **4/6 提到 5/6**。

### 文档：把「为什么不直接用现成解析库」写清楚

README 新增一节，记录对 yt-dlp / f2 / TikTokDownload / Douyin_TikTok_Download_API
的调研结论：它们都绕不开签名，且都要求用户自己提供 Cookie
（yt-dlp 源码里直接写着 `# TODO: Run verification challenge code to generate signature cookies`）。
小鲸鱼的选择是让平台页面自己去签名，用户零配置 —— 这是取舍，不是偶然。

---

## v0.1.0 — 2026-11-15

> 解析架构升级版。**这一版签名变了**（仓库里没有发布密钥，无法延续 v0.0.9 的签名），
> 从旧版升级需要**先卸载再装**，解析记录会清空。之后同签名可持续覆盖安装。

### 这次修的是「真的解析不出来」

抖音最近两次改版，把旧实现**唯一的两条路**同时堵了：

| 环节 | 旧实现 | v0.1.0 |
|---|---|---|
| **视频** | 只读 `<video>` 元素的 `src` | 优先读渲染后的 `_ROUTER_DATA.videoInfoRes.item_list[0]`（标题 / 作者 / 时长 / 封面 / `video_id` 一次拿全），DOM 只作兜底 |
| **图文** | 只认 `__pace_f` 里 `"images":[{"width"` **这一种前缀** | 按 `"images":` 定位 + 平衡括号抠完整数组 + `JSON.parse`，**字段顺序无关** |
| **动图** | 只认下划线 `play_addr` | 同时认驼峰 `playAddr` —— 实测动图作品页里 `play_addr` 出现 **0** 次、`playAddr` **3** 次 |
| **标题** | `__pace_f` 里取第一个 `"desc"` | 页面 title → `发布时间：` 前一行 → 标题节点。**绝不用 pace 里的 desc**：实测那 68 个 desc 全是推荐流热搜词（"王濛"、"三角洲行动"…） |
| **入口** | 一条路走到底 | 三入口自动降级：手机分享页 → 分享域 → PC 作品页；每个入口失败都有独立原因回传 |
| **播放地址** | 算一个出来直接用 | 生成候选列表（无水印 1080P/720P 两条 + 带水印兜底），**逐个 Range 请求 + `ftyp` 头校验**，用第一个真能取到字节的 |
| **UA** | 只切 User-Agent | UA 与浏览器指纹**同步切换**。手机 UA 配桌面指纹（1440×900、5 个 PDF 插件、`maxTouchPoints=0`）是最典型的风控特征 |
| **探测判定** | 一律当失败 | 三态：可用 / 明确失效 / 探测没做成。网络抖动不再被误判成「地址失效」 |

### 实测数据（2026-11-15，Android 14 x86_64 模拟器 + 真实网络）

设备端到端跑完，**不是只看日志，是真的去取了字节**：

| 用例 | 结果 |
|---|---|
| 抖音视频短链 | 标题作者正确 · **1080P / 13s** · 直链抽查 **HTTP 206 · video/mp4** |
| 抖音图文（46 张） | 46 张全取到 · 标题「壁纸分享（1）…」作者「无理.」 · 抽 3 张全部 **206 · image/webp** |
| 抖音动图 | 1 项动图 · 标题作者正确 · 带音轨视频 **206 · video/mp4** · 封面 **206 · image/webp** |
| 无效短链 | 给出可读错误，不崩、不卡死 |
| 网络连通性 | 主站 200 · 播放接口 206（单独一条用例，用来区分「代码不会解析」和「设备连不上网」） |

### 顺带修好的工程问题

- **发版脚本会被 analyze 卡死**：Flutter 3.47 起 `package:flutter/material.dart` 被标记废弃，20 条 info 让 `flutter analyze` 返回非零退出码，而 `tools/release.ps1` 里 analyze 不过就拒绝发版。现在显式忽略这条（附迁移说明），让「analyze 通过」重新等价于「没有真问题」。
- **AGP 9.1.0 → 9.1.1**：Flutter 3.50 的最低要求，之前 `flutter build apk` 直接失败。
- **x86_64 模拟器跑不了集成测试**：项目只打包 arm64，模拟器装上就 `UnsatisfiedLinkError`。新增 `FLUTTER_TEST_X64=1` 开关，**发布包仍然是纯 arm64**。
- **内嵌 JS 没有语法检查**：探针脚本只在真机执行，写错一个字符就静默失效。新增 `audit/probe/check_inline_js.mjs`，把 Dart 里的 `r'''…'''` 片段抽出来做语法校验。
- **`shared_preferences_android` 把 jni 带进了 APK**：2.5.0 起改用 `dart_lang/jni`，产物里多出 `libdartjni.so` + 通用 JNI 反射桥（`JniPlugin`）。这跟 `path_provider_android` 那条 override 是同一个理由 —— 小鲸鱼只用最基础的键值读写，用不到 JNI，而「Flutter + 通用 JNI 反射桥 + 混淆后的 libapp.so」会给 `a.gray.*` 的启发式判定加分。已钉在 **2.4.28**（最后一个纯原生实现），重建后 APK 里 `libdartjni.so` 消失，`lib/` 下只剩 `libapp.so` / `libflutter.so`。

### 性能

同一条图文链接、同一台模拟器，**28.3s → 13.3s**：

- `__pace_f` 的文本收集改成**逐层取字符串元素**再拼接。原来是 `String(segs[i])`，遇到「数组套数组」的 RSC 分片会得到 `"1,1:I{…}"` 这种带序号的脏文本，深层结构甚至变成 `[object Object]` —— 数据明明在却提取不到，只能退回 DOM 抠到 8 张懒加载图。
- 导航静置 900ms → 1200ms：少走一轮「拿到骨架就去解析 → 失败 → 重来」。
- 图片可用性校验从「首/中/尾三张并发」改成「只验首图 + 5 秒封顶」。整批图是同一张签名，验一张就够；三张并发在慢网下会白等十几秒。
- 标题等待从 2.6s → 1.5s，补读重试从 4 次 → 2 次（`document.title` 在 WebView 里通常一次就拿不到，靠 `发布时间：` 前一行兜底）。

### 新增的测试

- `test/douyin_parse_test.dart` —— **23 条**，全部用真实页面数据（`test/fixtures/`：一份图文页的 `__pace_f` 约 640KB、一份动图页、一份分享页的 `_ROUTER_DATA`）
- `integration_test/douyin_real_test.dart` —— **6 条**设备端到端，含"地址真的能下"与"网络不通要如实标注"
- 总测试数：**46 → 69**

### 已知限制（不粉饰）

- **模拟器所在的本地代理环境偶尔会让图片 CDN 的 TLS 握手失败**（`HandshakeException`），此时集成测试会打印 `[未验证]` 而不是假装通过；宿主机上同样的地址实测 **206 · image/webp**。真机网络下需要复验一次。
- 抖音的播放/图片地址都带 `x-expires` 签名，**解析完请尽快保存**；App 里已经在保存前做过抽样探测，过期会给出明确提示而不是存下一个坏文件。

---

## v0.0.9 — 2026-10-22

> 修复版。**签名与前几版相同**，可直接覆盖安装，记录和设置都会保留。

### 修复：更新检测一直是关着的

这是一个**静默失效**的严重问题，感谢反馈指出来。

v0.0.6 构建时为了走 GitHub Releases，把 `--dart-define` 的更新地址留空了。
而 `lib/config.dart` 里这三个常量当时是裸的 `String.fromEnvironment(...)`：
**没注入就是空字符串**。`UpdateService.check()` 第一行就是

```dart
if (kUpdateManifestUrl.isEmpty) return null;
```

于是整个更新检测被跳过 —— 不报错、不警告、界面上也看不出来，只是 App 永远
不会提示有新版本。v0.0.6 / v0.0.7 / v0.0.8 三版都是这个状态，用户只能自己
隔段时间上 GitHub 看。

**修了三层：**

1. **给地址加默认值兜底**（`lib/config.dart`）。三个地址都通过
   `String.fromEnvironment(..., defaultValue: ...)` 指向 jsDelivr 转发的
   `server/version.json`，以及 GitHub Releases 作为下载页。
   以后再忘注入也不会静默失效 —— 至少走默认源。
2. **不再依赖自建服务器**。原来的 `whale.kaogong.art` 已经不可用（SSL 握手失败），
   现在主源是 jsDelivr（转发本仓库文件，国内直连），备用源是 GitHub raw。
3. **加了回归测试**。一条断言三个地址都非空，一条拿真实的 `server/version.json`
   做解析验证（还顺带检查清单里的 build 号必须等于当前版本，防止忘记同步）。

另外把更新检查策略也改稳了一点：jsDelivr 有 CDN 缓存，发版后可能短时间返回
**旧清单**导致漏更新。现在主源没给出「有新版」时，会再问一次无缓存的
GitHub raw —— 正常情况不多花请求，缓存造成的漏更新能被兜住。

### 升级方式（这一版仍需手动）

因为 v0.0.8 及更早版本的更新检测是坏的，**它们收不到「有 v0.0.9」的提示**。
所以这一次还得手动下载安装。

**装完 v0.0.9 之后就好了** —— 从这版起 App 会自己检查更新，每个版本最多提醒一次。

### 验证

`flutter analyze` 零问题；测试 **46 项全过**（新增 2 项：地址非空的回归断言、
真实清单文件解析）。产物里确认三个更新地址都已编译进去
（`cdn.jsdelivr.net`、`raw.githubusercontent.com`、`releases/latest` 各命中 1 处），
旧的 `whale.kaogong.art` 零残留。

---

## v0.0.8 — 2026-10-22

> 功能版。**签名与 v0.0.6 / v0.0.7 相同**，已装旧版可直接覆盖安装，
> 解析记录和设置都会保留。

### 新增：动图可以「复原」成动态照片了

v0.0.7 加的 GIF 是**降级转换**（丢音轨、256 色、体积大）。这一版补上真正意义上的
**复原** —— 把动图重新封装成 Android 原生支持的**动态照片（Motion Photo）**。

新增第四档，设置位置：「我的 → 解析偏好 → 动图保存方式」：

| 档位 | 产出 | 特点 |
|---|---|---|
| 短视频（默认，行为不变） | `.mp4` | 动效 + 声音都在，相册归到「视频」 |
| **动态照片**（新） | `.jpg` 单文件 | 相册里是**照片**，长按会动、带原声；无损、体积≈原视频 |
| GIF 动图 | `.gif` | 相册归到「图片」，能当表情直接发微信；无声音、体积较大 |
| 静态封面 | `.jpg` | 只存第一帧，最省空间 |

**动态照片 vs GIF**：前者无损、有声、体积小、耗时短（字节拼接），但能否播放取决于
系统相册；后者画质有损、无声音、体积大，但任何相册都能看、微信能动。各取所需。

### 实现要点

- **本质是字节拼接，不是转码**。一个动态照片文件就是
  `[完整 JPEG ... EOI]` + `[原封不动的 MP4]`，再用 JPEG 的 APP1 段里一段 XMP
  标明「从文件末尾倒数 N 字节是视频」。所以不需要抽帧，也没有画质损失。
- **新旧两套 XMP 标准同时写**：旧标准 `GCamera:MicroVideo` + `MicroVideoOffset`，
  新标准 `GCamera:MotionPhoto` + `Container:Directory`。两套语义重叠、互不冲突，
  一起写以提高被不同厂商相册识别的概率。
- **XMP 插在 SOI + 可能的 JFIF APP0 之后**（不破坏「APP0 必须紧跟 SOI」的约定）。
- **封面不是 JPEG 时自动重编码**（平台常给 webp/heic）；XMP 声明的是 `image/jpeg`，
  容器里就必须真的是 JPEG。
- **没有引入任何原生库**，权限也没增加（仍是 `INTERNET` / `ACCESS_NETWORK_STATE` /
  `WRITE_EXTERNAL_STORAGE` maxSdk=29 三条）。Dart 侧多下了一次封面图，合成本身在原生
  侧是纯字节操作。

### 验证

- `flutter analyze` 零问题；测试 **44 项全过**（新增 3 项：动态照片档位映射与历史别名、
  四档标签不重复、默认档位不被悄悄改动）。
- **额外做了一次离线格式验证**：用 Python 按与 Kotlin 完全相同的字节逻辑生成一个动态
  照片文件，再用解析方式反验 15 项断言全部通过 —— PIL 能解出完整图片、APP1 长度字段
  自洽、`MicroVideoOffset` 反推的位置正好落在 `ftyp`、JPEG 以 `FFD9` 干净结尾、
  内嵌视频可原样切出。**格式设计本身是对的**。
- 产物 `native-code` 仍只有 `arm64-v8a`；DEX 内可检出 `ns.google.com/photos/1.0/camera/`、
  `GCamera:MotionPhoto`、`GCamera:MicroVideo` 等常量，确认新旧两套 XMP 都已打包。

### 已知限制（重要）

- **动态照片能否播放取决于系统相册**。据公开实测，小米 **HyperOS 3** 用标准 XMP
  即可识别第三方生成的动态照片；**更老的 MIUI 和其他品牌可能需要厂商私有元数据**，
  那种情况下相册只会显示静态封面（文件本身没问题，不会损坏）。
- 因此**默认档位仍然是「短视频」**，动态照片需要自己去设置里选 —— 选完建议先存一张
  试试，确认你的相册认不认。
- 动态照片**在微信里发送会退化成静态图**（微信不认这个容器）。要发朋友圈动图请用 GIF 档。
- 只支持 Android。

---

## v0.0.7 — 2026-10-22

> 功能版。**签名与 v0.0.6 相同**，已装 v0.0.6 的用户可以直接覆盖安装，
> 解析记录和设置都会保留。

### 新增：动图可以存成 GIF 了

以前「动图」（Live Photo）只有两个选择：存成小视频（有声音，但相册归到视频），
或者不存（丢掉动效）。现在多一档 —— **直接把动图变成图片格式的 GIF**。

设置位置：「我的 → 解析偏好 → 动图保存方式」，三选一：

| 档位 | 产出 | 特点 |
|---|---|---|
| 短视频（默认，行为不变） | `.mp4` | 动效 + 声音都在，相册归到「视频」 |
| **GIF 动图** | `.gif` | 相册归到「图片」，能当表情直接发微信；无声音，体积约 2~5 MB |
| 静态封面 | `.jpg` | 只存第一帧，最省空间 |

老用户升级是**无损迁移**：原来开关开着 → 保持「短视频」；原来关着 → 「静态封面」。
不会因为升级就被悄悄改成新默认值。

### 技术要点（都是踩过的坑）

- **抽帧必须用 `OPTION_CLOSEST`**。`OPTION_CLOSEST_SYNC` 只返回关键帧，而这类动图视频
  只有 2~3 秒、关键帧间隔 1~2 秒 —— 抽 20 帧会得到 2~3 张重复图，GIF 会"卡住不动"。
  pub.dev 上几个现成的视频转 GIF 插件都踩了这个坑，所以这次**没有用第三方插件**，
  而是自己写了抽帧 + 内置编码器。
- **不用 `Bitmap.createScaledBitmap`，改用 Canvas 重绘**。两个原因：目标尺寸等于原尺寸时
  `createScaledBitmap` 会直接返回原对象，回收责任分不清，容易 double recycle 崩溃；
  而且个别 ROM 下 `getFrameAtTime` 会返回 `Config.HARDWARE` 位图，硬件位图不支持
  `getPixels()`，而 GIF 编码正靠它读像素。
- **没有引入任何 native `.so`**。GIF 编码器是内置的纯 Java 实现（源自 Glide 的
  `gif_encoder`），并修掉了它 `getImagePixels()` 里把 Canvas 画到临时空位图上的 bug。
- 原生侧用**单线程队列**：转 GIF 是 CPU + 内存密集型（每帧都要做 NeuQuant 256 色量化），
  一次保存十几张动图时并行会把内存打爆。

### 验证

`flutter analyze` 零问题；单元 / Widget 测试 **41 项全过**（新增 5 项覆盖三档模型、
老字段迁移、脏数据兜底）。产物权限没有增加，仍是 `INTERNET` /
`ACCESS_NETWORK_STATE` / `WRITE_EXTERNAL_STORAGE`(maxSdk=29) 三条。

### 已知限制

- GIF **没有声音**（格式本身不支持音轨）。要声音就选「短视频」档。
- GIF 体积明显大于视频（256 色 + 无帧间压缩），2~3 秒的动图约 2~5 MB。
- 转换需要 2~4 秒，期间进度条显示「正在转 GIF…」。
- 只支持 Android；等真的有 iOS 版本时再用 AVAssetImageGenerator + ImageIO 补。

---

## v0.0.6 — 2026-10-22

> **这一版是安全整改版。功能上没有删减，但底层行为有取舍，请先读「升级须知」。**

### ⚠️ 升级须知（**装之前必读**）

1. **必须卸载旧版再安装本版。**
   v0.0.6 换了新的签名证书（原私钥已无法找回），直接覆盖安装会提示「应用未安装」。
2. **卸载会清空解析记录**，「我的」页的昵称/头像也会重置。
   **已保存到相册的图片和视频不受影响。**
3. 本版**不再有应用内下载安装包**的功能。检查到新版后点「立即更新」会打开浏览器
   下载页，由系统下载器和系统安装流程接管。

### 背景：为什么这一版要动安全

v0.0.5 在小米等国产机型上被手机管家拦截，提示
`发现风险 · 【高风险】包含病毒：a.gray.BulimiaTGen.f`。

经静态取证（详见 [`docs/SECURITY.md`](docs/SECURITY.md) 与
[`docs/COMPLAINT-TENCENT.md`](docs/COMPLAINT-TENCENT.md)）：**这个标记不是扫到了恶意代码**，
而是腾讯病毒库的启发式聚类 —— 由「个人自签证书 + 未上架商店 + 具备下载并安装可执行
文件的能力 + 功能面较宽」等特征共同触发。v0.0.5 已经换过一次签名试图规避，一个月后
病毒库更新，同一规则再次命中 —— 证明**换签名不是解法**。

所以 v0.0.6 的做法是：**把能被静态度量的风险特征真正去掉**，而不是继续换皮。

### 移除（改动最大，也最关键）

- **彻底移除应用内安装 APK 的能力**。删掉的东西：
  - `AndroidManifest.xml` 的 `REQUEST_INSTALL_PACKAGES` 权限
  - `FileProvider` 声明与 `res/xml/file_paths.xml`（暴露 `apk/` 缓存目录的那份白名单）
  - `MainActivity.kt` 里整个 `xiaojingyu/installer` MethodChannel
    （`canInstall` / `requestInstall` / `install`，含 `ACTION_VIEW` +
    `application/vnd.android.package-archive`）
  - `lib/services/installer.dart`
  - `UpdateService.downloadApk()` 与 `mine_page.dart` 的 `_downloadAndInstall()`

  > 这套「联网下载 .apk → FileProvider → 拉起系统安装器」是 v0.0.5 被判高危的
  > **最大单一原因**：它在静态特征上和推广/捆绑类灰色软件无法区分。

- **移除通用 JNI 反射桥**。`path_provider_android` 从 2.3.0 起改用 `dart_lang/jni` 实现，
  会往 APK 里塞进 `com.github.dart_lang.jni.JniPlugin`（能加载任意 Java 类并调用其方法
  的通用桥）以及 `lib/*/libdartjni.so`。本项目只用了 `getTemporaryDirectory()` 一个 API，
  完全不需要 JNI。用 `dependency_overrides` 钉回 `2.2.21`，DEX 里该类与对应 `.so` 均已消失。

- **移除全量明文 HTTP 放行**。`usesCleartextTraffic` 与 `network_security_config` 双双改为
  禁止明文。原先是为了「调试时连 `http://10.0.2.2:8787`」留的口子，却被带进了发布包 ——
  而小鲸鱼访问的接口、CDN、更新清单**全部是 HTTPS**，没有任何一处需要明文回退。

### 修复

- **ABI 虚标导致 32 位/模拟器设备一启动就崩溃**。
  v0.0.5 的 `lib/armeabi-v7a/` 和 `lib/x86_64/` 里只有插件的原生库、**没有** `libflutter.so`
  与 `libapp.so`（ELF 头实测确认），但 APK 对外声称支持三个 ABI —— 这类设备能装上，
  一打开就 `UnsatisfiedLinkError: couldn't find "libflutter.so"`。
  根因是 `--target-platform android-arm64` 只剔 Flutter 引擎库、不剔插件 AAR 的 jniLibs。
  本版用 `packaging.jniLibs.excludes` 收口，`native-code` 现在只声明 `arm64-v8a`。
  （试过 `ndk.abiFilters`，实测对 AAR 预编译库无效，产物逐字节不变。）

- **`android/settings.gradle.kts` 在中文路径下无法构建**。
  Flutter tools 用 UTF-8 写 `local.properties`，而 Java 的 `Properties.load(InputStream)`
  固定按 ISO-8859-1 解码 —— 一旦 Flutter SDK 装在含中文的目录，`flutter.sdk` 会变成乱码，
  Gradle 报一句完全不提编码的 `Included build '...' does not exist`。
  改为显式用 `InputStreamReader(UTF_8)` 读取，并补了 `FLUTTER_ROOT` 环境变量兜底。

### 收紧

- `android:allowBackup="false"` —— 解析历史只留在本机，不参与系统云备份。
- `<queries>` 保持只有 Flutter 引擎需要的那一条 `PROCESS_TEXT`；不申请
  `QUERY_ALL_PACKAGES`，小鲸鱼不需要知道用户装了什么。
- 签名升级为 **v2 + v3 双方案**（v0.0.5 只有 v2）。minSdk 24 用不到 v1，已关闭。
- 权限收敛到最小集：`INTERNET`、`ACCESS_NETWORK_STATE`、`WRITE_EXTERNAL_STORAGE`
  （`maxSdkVersion=29`，仅 Android 9 及以下写相册用）。

### 新增文档

- [`docs/SECURITY.md`](docs/SECURITY.md) —— 面向用户：为什么会报毒、能不能放心装、
  被拦截了怎么办
- [`docs/SAFE-INSTALL.md`](docs/SAFE-INSTALL.md) —— 安装与验签指南、MIUI 拦截逐屏处理
- [`docs/COMPLAINT-TENCENT.md`](docs/COMPLAINT-TENCENT.md) —— 可直接提交的误报申诉材料

### 未改变的功能

解析引擎、18 个平台的适配、动图支持、HEIC→JPEG、断点续传、按文件头定后缀、
相册保存（Android 10+ 走 MediaStore，不要存储权限）—— 全部保持原样。

### 仍然存在的风险（说清楚，不粉饰）

- **代码层整改能降低命中概率，但不保证 100% 不再被标记。** 最终判定权在厂商病毒库。
- 换签名只是让新包进入一段观察期，**不是根治**。
- 根治路径只有两条：向腾讯提交误报申诉加白，或上架正规应用商店。
- 本版**未上架任何应用商店**，仍属侧载安装，被 MIUI / 反诈提示关注的可能性依然存在。

---

## v0.0.5 — 2026-09-26

- **换了正式签名**（从 Android 调试证书换成正规章书）
- 首页精简：去掉平台标签、「三步搞定」、「使用须知」
- 「我的」页支持改昵称、换头像
- 修复抖音视频封面空白：按 `og:image → poster → 页面大图` 三级兜底
- 更新改成应用内下载（带进度条、可断点续传）

## v0.0.3 — 2026-09-25

- 稳定性修复与体验打磨

## v0.0.2 — 2026-09-25

- 平台适配扩充

## v0.0.1 — 2026-09-25

- 首个版本：本地解析、无水印保存
