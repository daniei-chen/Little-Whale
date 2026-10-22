# 更新日志

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
