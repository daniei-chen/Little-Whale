# 腾讯安全引擎误报申诉材料 —— 小鲸鱼（cn.flashsave.flashsave）

> **用途**：本文件可直接复制粘贴到「腾讯手机管家 · 软件误报申诉」入口，或随样本一起提交到腾讯哈勃分析系统（<https://habo.qq.com/>）的人工复核工单。
>
> **对象**：被 MIUI 安全中心报为 `【高风险】包含病毒：a.gray.BulimiaTGen.f` 的安装包。
>
> **2026-10-25 增补**：整改后的 v0.0.8 在用户设备上被同一规则再次报出（本文首发的 v0.0.5 申诉结论继续有效）。本文新增「[当前被报样本](#当前被报样本2026-10-25-增补)」一节，给出 v0.0.8（被报样本）与 v0.0.9（现行最新版）的实测取证数据，申诉时请引用这一节。
>
> **声明**：本文所有技术结论均来自对已发布 APK 的实际静态取证，命令见文末「附：自查用的命令」，可逐条复现。凡未实测的字段一律标注为占位符，不填写推测值。

---

## 一句话诉求

> **申请对包名 `cn.flashsave.flashsave` 的 `a.gray.BulimiaTGen.f` 检出结果进行人工复核，并在复核确认无害后将该应用（含使用同一签名证书的后续版本）移出灰色软件库、加入白名单。**

可一并粘贴的补充说明：

> 我们已按照「具备自我更新能力 = 灰色软件高危画像」这一判定逻辑，在 v0.0.6 中**彻底移除**应用内 APK 下载与安装能力：`REQUEST_INSTALL_PACKAGES` 权限、`FileProvider`、安装器原生通道与对应 Dart 封装全部删除，更新改为打开浏览器下载页。源码全部开源，可公开复核。

---

## 应用基本信息

| 项目 | 值 |
|---|---|
| 应用名称 | 小鲸鱼（Little Whale） |
| 包名 | `cn.flashsave.flashsave` |
| 被报样本版本 | `0.0.5`，versionCode `5`，versionName `0.0.5` |
| 被报 APK 文件名 | `xiaojingyu-0.0.5-arm64-v8a.apk` |
| 被报 APK 大小 | 21,540,917 字节（约 20.5 MiB） |
| 被报 APK SHA-256 | `5b1d0b2ebb2128e220e4d0b0a660afafc16782e71b49b693cc7e5cba0154eafc` |
| 整改版本 | `0.0.6`，versionCode `6`，versionName `0.0.6`（`pubspec.yaml` 中 `version: 0.0.6+6`） |
| 整改 APK 文件名 | `xiaojingyu-0.0.6-arm64-v8a.apk` |
| 整改 APK SHA-256 | `ACDBD2D18A28EF8D9327ECD65941AC860B255121026D2383EACA22B9D538FB90`（**以 Release 页面最终上传件为准**；若因修复构建再产出新包，哈希会同步更新） |
| 整改 APK 大小 | 21,014,208 字节（约 20.0 MiB，仅含 `arm64-v8a`） |
| 签名证书主体 | `CN=Little Whale, OU=Mobile, O=Little Whale Studio, L=Shenzhen, ST=Guangdong, C=CN` |
| 签名证书 SHA-256 | `f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827` |
| 签名证书 SHA-1 | `df6253483028ec3968ffe613fcf3890126aaa866` |
| 签名证书 MD5 | `f48343deccb0bfba6a4fbcc7ad1e9820` |
| 证书密钥 | RSA 2048 |
| 签名方案 | v0.0.6：APK Signature Scheme **v2 + v3**（v1 关闭）；被报样本 v0.0.5：仅 v2 |
| minSdk / targetSdk | 24（Android 7.0）/ 36 |
| 检出名称 | `a.gray.BulimiaTGen.f`（MIUI 提示：「发现风险：安装该应用存在高风险，请谨慎安装！」） |
| 开源仓库 | <https://github.com/daniei-chen/Little-Whale> |
| 发布渠道 | 仅 GitHub Releases；**未上架任何应用商店**，无推广联盟、无联运、无广告 |
| 构建方式 | `flutter build apk --release --target-platform android-arm64`（Flutter 3.35+ / JDK 17 / Android SDK 36），CI 见仓库 `.github/workflows/ci.yml` |
| 开发者性质 | 个人 / 小团队，自签名证书，非企业主体 |
| 联系方式 | `{{待填：开发者联系邮箱或 QQ 号，建议填 QQ 邮箱}}` |
| 提交日期 | `{{待填：提交申诉的日期}}` |

> 指纹实测来源：`apksigner verify --print-certs xiaojingyu-0.0.6-arm64-v8a.apk`。
> **签名世代说明**：v0.0.6 起启用新的发布证书（原证书私钥已不可用，无法继续签发新版本）。上表指纹属于**当前证书**，即 v0.0.6 及以后各版本；v0.0.5 及更早版本由上一代证书签发，其指纹与上表不同——那是同一开发者的历史版本，不是他人仿冒。

---

<a id="当前被报样本2026-10-25-增补"></a>

## 当前被报样本（2026-10-25 增补）

v0.0.6 整改后，用户设备上的 **v0.0.8** 仍被同一规则 `a.gray.BulimiaTGen.f` 报出。下表是被报样本与现行最新版的对照数据，均可逐条复现（命令见文末附录）：

| 项目 | v0.0.8（本次被报样本） | v0.0.9（现行最新版，已实测） |
|---|---|---|
| versionCode / versionName | 8 / 0.0.8 | 9 / 0.0.9 |
| APK 文件名 | `xiaojingyu-0.0.8-arm64-v8a.apk` | `xiaojingyu-0.0.9-arm64-v8a.apk` |
| APK SHA-256 | `253E11E8BCA65904B2436B76C680A4DB344CEF34AC69139D8514F16A6FDDBF46`（发布于 Release v0.0.8 说明） | `FEE113769F958A9AB66200E3D723E56536F3CCE6902F662A8A535B33C0C61FA3`（2026-10-25 实算，与 Release 说明一致） |
| 签名证书 | 与 v0.0.6 起同一张：SHA-256 `f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827` | 同左（`apksigner verify --print-certs` 实测一致） |
| 签名方案 | v2 + v3 | v2 + v3（实测 `Verified using v2 scheme: true` / `v3: true` / `v1: false`） |
| 声明权限 | 同 v0.0.6 最小集（见下） | 实测：`INTERNET`、`ACCESS_NETWORK_STATE`、`WRITE_EXTERNAL_STORAGE`（maxSdk 29）+ 1 条 androidx.core 自动注入的自定义签名级权限；`aapt2 dump badging` 另列一条**由 WRITE 推导的隐含** `READ_EXTERNAL_STORAGE`（maxSdk 29），非声明权限 |
| native-code | `arm64-v8a` | `arm64-v8a`（实测） |
| `debuggable` / kernel_blob | 未声明 / 无（release AOT） | 同左（实测 `assets/flutter_assets/` 下无 `kernel_blob.bin`） |

### v0.0.9 实测取证（2026-10-25，`aapt2` 36.0.0 + `apksigner`）

| 取证项 | 结果 |
|---|---|
| `DexClassLoader` / `PathClassLoader` / `InMemoryDexClassLoader` / `ProcessBuilder` / `dalvik/system/*` | **0 命中** |
| 广告 / 统计 / 加固 SDK（umeng、gdt、bytedance/pangle、sigmob、mintegral、appsflyer、bugly、jiagu 等） | **0 命中** |
| `lib/arm64-v8a/` 清单 | `libflutter.so`、`libapp.so`、`libdatastore_shared_counter.so`（共 3 个） |
| 声明 `REQUEST_INSTALL_PACKAGES` | 无（v0.0.6 已删除，此后未恢复） |

### 关于 `libdatastore_shared_counter.so` 的说明（与 v0.0.6 取证表的差异）

v0.0.6 取证时该文件不存在；v0.0.9 中重新出现。原因：`shared_preferences_android` 自 2.4.x 起把内部实现迁移到了 androidx **DataStore**（构建脚本 `implementation("androidx.datastore:datastore:1.1.7")`），随 `shared_preferences` 2.5.x 传递引入。这是 Google 官方 androidx 组件、海量主流应用的标配依赖，**与 v0.0.6 移除的「通用 JNI 反射桥」（`com/github/dart_lang/jni` + `libdartjni.so`）不是同一类东西**——后者提供「加载任意类、调用任意方法」的反射能力，前者只是键值存储实现，不新增任何可疑能力。特此说明以免复核时对不上。

---

## 签名变更与升级须知（重要）

> ⚠️ **v0.0.6 更换了发布证书，v0.0.5 及更早版本无法覆盖升级，必须先卸载旧版再安装 v0.0.6。**
>
> | 项目 | 说明 |
> |---|---|
> | 变更原因 | 原发布证书的私钥已不可用，无法继续签发新版本，只能启用新证书 |
> | 直接影响 | Android 不允许用不同证书覆盖安装同一包名，直接升级会提示「应用未安装」 |
> | 代价 | 卸载会清空**解析记录**（一份「解析过哪些链接」的本地列表） |
> | 不受影响 | **已保存到相册的图片和视频**，以及手动导出的错误日志 |
> | 与本次申诉的关系 | 换证书只解决「能否继续发版」的签发问题，**不代表包的行为发生了变化**；行为层面的整改见下一节 |

---

## v0.0.6 与上一版的行为差异（摘要）

如果贵方只关心「这一版和我们上一条工单里的样本有何不同」，可直接看这三条：

1. **不再具备安装任何 APK 的能力**：`REQUEST_INSTALL_PACKAGES` 权限、`FileProvider`、安装器原生通道全部删除，更新只跳浏览器。
2. **不再包含通用 JNI 反射桥**：`com/github/dart_lang/*`（含 `JniPlugin`）共 12 个类，与 `libdartjni.so` 已从产物中消失。
3. **ABI 收口为 arm64-v8a**：v0.0.5 对外声称支持三个 ABI，但 32 位与 x86_64 目录里缺 Flutter 引擎库，属于打包缺陷，已修复。

完整清单见「v0.0.6 已完成的整改」。

---

## 这个标记为什么是误报

### 1. `a.gray.*` 是「灰色软件」启发式家族，不是具体木马家族

命名结构可以直接拆开看：

| 片段 | 含义 |
|---|---|
| `a` | Android 平台 |
| `gray` | grayware，即「灰色软件」——**不属于病毒/木马/后门**，指行为合规性存疑、但未发现明确恶意的软件类别 |
| `BulimiaTGen` | 该类检出的家族聚类名 |
| `.f` | 同一聚类下的变体编号 |

这类名称由安全厂商的**启发式规则 + 特征聚类**产生，随病毒库分发给各手机厂商的安全组件（小米 / OPPO / vivo / 华为等手机管家均使用同一来源的病毒库）。它的判定依据不是「发现了某段恶意代码」，而是「这个包的多项特征与已知灰色软件样本聚在一起」。

因此同一个名称会同时命中大量互不相关的应用。它们的共同点通常只是：

- 个人或小团队开发，使用自签名证书，证书在云端没有历史信誉
- 未上架正规应用商店，缺少商店渠道的白名单背书
- 功能面较宽，且具备「联网下载可执行文件 / 请求安装」这类高权重能力
- 安装量小、样本量少，厂商侧没有足够的良性样本积累

「聚成一类」不等于「做同一件事」。这就是我们把本次检出定性为启发式误判的依据。

### 2. 对被报样本的静态取证：能力面与恶意软件不重合

我们完整解包了被报 APK 并做了只读静态分析（不修改、不重打包）。结果：

| 取证项 | 方法 | 结果 |
|---|---|---|
| 动态加载 / 命令执行 | 解包 DEX 后对类名、方法引用、字符串常量做全文检索 | **0 命中**：无 `DexClassLoader`、`PathClassLoader`、`InMemoryDexClassLoader`、`ProcessBuilder`、`dalvik.system.*`；`exec` 相关字符串全部属于 `execute` / `Executor` / `ExecutionException` 家族，无 `Runtime.exec` |
| 广告 / 统计 / 推送 SDK | 类名与字符串检索 | **0 命中**：无友盟（umeng）、广点通（gdt）、穿山甲（pangle/bytedance）、Sigmob、Mintegral、AppsFlyer、Bugly 等任何商业 SDK 特征 |
| 加固壳 / 壳外加载 | 清点 `lib/` 与 `assets/` | 无加固壳（无 libjiagu / libshell 类），`assets/` 下无加密 DEX |
| 是否可调试 | 二进制 AndroidManifest + 产物结构 | 未声明 `android:debuggable`（默认即 `false`）；APK 内**无** `kernel_blob.bin`，确认为 release AOT 构建，不是调试包 |
| 原生库清单 | 按 ABI 清点 `lib/` | `arm64-v8a`：`libflutter.so`（Flutter 引擎）、`libapp.so`（Dart AOT 业务代码）、`libdartjni.so`、`libdatastore_shared_counter.so`；`armeabi-v7a` / `x86_64`：**只有插件库，缺 `libflutter.so` / `libapp.so`**（ELF 头实测，属打包缺陷而非安全项，v0.0.6 已收口为单一 ABI） |
| 应用自身原生类 | DEX 类表 | **仅 1 个**：`cn.flashsave.flashsave.MainActivity` |

DEX 类分布（被报样本，只解包 `classes.dex`）。全部 `class_defs` 共 **1152** 个，其中带可读包名的只有 **156** 个，其余全部是 R8 生成的短名类（`a`、`b`、`t0` 之类）——这本身就是 v0.0.5 已启用 R8 代码收缩与混淆的直接证据（资源名同样被缩短，如 `res/0K.xml`）：

| 类名前缀 | 类数 | 来源 |
|---|---:|---|
| `org/chromium/*` | 58 | AndroidX WebView 支持库（本应用依赖内置 WebView 完成解析） |
| `androidx/*` | 45 | AndroidX 基础库 |
| `io/flutter/*` | 34 | Flutter 引擎 |
| `com/github/dart_lang/*` | 12 | `path_provider` 插件带入的通用 JNI 桥（v0.0.6 已移除，见整改第 5 条） |
| `android/*` | 6 | Android Framework 引用 |
| `cn/flashsave/*` | 1 | 应用自身唯一的原生类：`MainActivity` |
| **class_defs 合计** | **1152** | 上表之外均为 R8 短名类，不含包名、无法按包归类 |

**结论**：这个安装包的能力面只有四项——联网（HTTPS）、内置 WebView 渲染平台页面、下载媒体文件、把媒体写入系统相册。它不具备下列任何一项能力：

- 下载并执行外部代码 / 加载外部 DEX
- 执行 shell 命令、提权、读取其他应用私有数据
- 后台常驻、开机自启、静默推送、锁屏唤醒
- 采集设备标识、通讯录、短信、通话记录、应用列表
- 静默安装其他应用（Android 本身也不允许）

### 3. 数据处理方式：不收集、不上传、无服务端

| 问题 | 回答 |
|---|---|
| 有没有后端服务器解析链接？ | 没有。18 个平台的链接解析全部在手机本地完成：内置隐藏 WebView 执行平台页面 JS，再读取渲染后的 DOM / 页面数据流 |
| 会不会上传用户粘贴的链接？ | 不会。没有任何上报接口，链接只在本机内存里流转 |
| 有没有账号 / 登录 / 设备指纹？ | 没有。不收集任何用户数据，也没有可收集的字段 |
| 有没有埋点、崩溃上报、灰度实验？ | 没有。错误日志只写入本机文件，不上传 |
| 有没有广告位、推广入口、第三方支付？ | 没有 |
| 会联网访问哪些域名？ | 只有两类：① 平台自身的域名（解析与下载媒体）；② 一个静态 JSON 更新清单（只有版本号与下载页地址，不含任何上报字段） |

### 4. 唯一与「高危画像」重合的成分，是应用内自我更新（已于 v0.0.6 移除）

被报版本中存在这条能力链：

```
REQUEST_INSTALL_PACKAGES 权限
  + 应用内下载 .apk
  + FileProvider（authority: cn.flashsave.flashsave.fileprovider）
  + ACTION_VIEW + application/vnd.android.package-archive 拉起系统安装器
```

我们完全理解：这套组合在静态扫描视角下，与「推广 / 捆绑 / 自我更新」类灰色软件**无法区分**。这是我们认定本次检出的真实成因，也是我们主动整改的原因。

需要说明的两点事实：

1. 该能力从未被用于静默安装。Android 不允许静默安装，用户必须在系统弹出的安装确认框中手动确认。
2. 该能力在 v0.0.6 中已被**完整删除**，不是隐藏、不是关闭开关，而是权限、组件、原生代码、Dart 封装全部移除。

---

## v0.0.6 已完成的整改

| # | 整改项 | 具体做法 | 效果 |
|---|---|---|---|
| 1 | 移除应用内 APK 下载与安装 | 删除 `REQUEST_INSTALL_PACKAGES` 权限、`FileProvider` 声明、`res/xml/file_paths.xml`、`xiaojingyu/installer` 原生 MethodChannel 及其 Dart 封装 | 安装包不再具备「请求安装其他 APK」的能力 |
| 2 | 更新机制改为「检查 → 打开浏览器下载页」 | 只比对版本号并提示，点击更新后交给浏览器 / 系统下载器与系统安装流程 | 应用自身不再写入任何 `.apk` 文件 |
| 3 | 禁止明文流量 | `android:usesCleartextTraffic="false"` + `network_security_config` 中 `cleartextTrafficPermitted="false"`（v0.0.5 为全量放行 HTTP） | 消除「任意 HTTP 回退」这一稳定可疑特征，同时关闭中间人注入面 |
| 4 | `allowBackup` 改为 `false` | 解析历史不参与云备份 | 用户数据不出本机 |
| 5 | 移除通用 JNI 反射桥 | 把 `path_provider_android` 固定在仍使用原生实现的版本（2.2.21）。v0.0.5 因该插件 2.3.x 引入 `jni` / `jni_flutter`，DEX 里带 `com/github/dart_lang/*` 共 12 个类（含通用桥 `JniPlugin`，可加载任意 Java 类、调用任意静态/实例方法），3 个 ABI 下还有 `libdartjni.so`；本项目只用 `getTemporaryDirectory()` 一个 API，不需要 JNI | DEX 中这些类与 `libdartjni.so` 均已消失，去掉一条通用反射桥 |
| 6 | ABI 收口到 arm64-v8a | 构建时加 `ndk { abiFilters += "arm64-v8a" }`。v0.0.5 的 `lib/armeabi-v7a/`、`lib/x86_64/` 目录里只有插件库、没有 `libflutter.so` / `libapp.so`（ELF 头实测），但 badging 仍声称支持三个 ABI，32 位与模拟器设备装上即 `UnsatisfiedLinkError` 崩溃 | v0.0.6 的 `native-code` 只剩 `arm64-v8a`，与实际内容一致，不再对不支持的设备「假装可装」 |
| 7 | 收敛权限并移除安装权限 | 仅保留 `INTERNET`、`ACCESS_NETWORK_STATE`、`WRITE_EXTERNAL_STORAGE`（`maxSdkVersion="29"`，仅 Android 9 及以下写相册）；另有 1 条 `cn.flashsave.flashsave.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` 由 androidx.core 清单合并自动注入（非手写） | 声明权限由 5 条降为 4 条，其中 0 条高敏感权限 |
| 8 | 更换发布证书 + 签名升级为 v2 + v3 | 原因：原证书私钥已不可用，无法继续签发新版本，只能生成新 keystore。构建脚本固定 `enableV1Signing=false`、`enableV2Signing=true`、`enableV3Signing=true` | 发版可持续；签名符合当前最佳实践（v0.0.5 实测仅 v2）。**代价：v0.0.5 及更早版本无法覆盖升级，必须先卸载** |

> 关于混淆：R8 代码混淆与资源压缩在 v0.0.5 中就已由 Flutter 工具链默认启用（1152 个 `class_defs` 中仅 156 个带可读包名，资源名被缩短为 `res/0K.xml` 之类），**v0.0.6 未对此作任何改动**，因此不列为整改项。

整改后的权限清单（合并后 Manifest 实测）：

| 权限 | v0.0.5 | v0.0.6 | 用途 / 说明 |
|---|:---:|:---:|---|
| `INTERNET` | ✅ | ✅ | 解析与下载媒体文件 |
| `ACCESS_NETWORK_STATE` | ✅ | ✅ | 判断网络可用性，失败时给出提示 |
| `WRITE_EXTERNAL_STORAGE`（maxSdk 29） | ✅ | ✅ | 仅 Android 9 及以下写相册；Android 10+ 走 MediaStore，不需要权限 |
| `REQUEST_INSTALL_PACKAGES` | ✅ | ❌ **已删除** | 应用内更新安装（v0.0.6 起更新只跳浏览器） |
| `cn.flashsave.flashsave.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | ✅ | ✅ | 由 `androidx.core` 清单合并**自动注入**的自定义签名级权限，仅用于约束本应用内部广播接收器，不授予任何系统能力 |

> 说明 1（避免误读）：`aapt2 dump badging` 在 v0.0.5 上还会多输出一条 `uses-implied-permission: READ_EXTERNAL_STORAGE`。这是工具根据「已声明 `WRITE_EXTERNAL_STORAGE`」**推导**出来的隐含权限，**合并后的 `AndroidManifest.xml` 里并没有声明 `READ_EXTERNAL_STORAGE`**——用 `aapt2 dump permissions` 核对即可确认。
> 说明 2：v0.0.6 的更新检查仍会访问一个静态 JSON 清单，用途仅为版本比对，清单中不含任何设备信息或上报字段。

---

## 可供核验的证据清单

| 证据 | 地址 / 内容 |
|---|---|
| 完整源码 | <https://github.com/daniei-chen/Little-Whale> |
| 发布页（含每个 APK） | <https://github.com/daniei-chen/Little-Whale/releases> |
| 本次被报样本 | Release `v0.0.5` 附件 `xiaojingyu-0.0.5-arm64-v8a.apk`，SHA-256 见上文基本信息表 |
| 2026-10 被报样本 | Release `v0.0.8` 附件 `xiaojingyu-0.0.8-arm64-v8a.apk`，SHA-256 见「当前被报样本」一节 |
| 现行最新版（建议复核样本） | Release `v0.0.9` 附件 `xiaojingyu-0.0.9-arm64-v8a.apk`，SHA-256 `FEE113769F958A9AB66200E3D723E56536F3CCE6902F662A8A535B33C0C61FA3`，取证数据见「当前被报样本」一节 |
| 本次整改版本 | Release `v0.0.6` 附件 `xiaojingyu-0.0.6-arm64-v8a.apk`，SHA-256 见上文基本信息表（以 Release 页面最终上传件为准） |
| ABI 清单 | `aapt2 dump badging` 的 `native-code` 行：v0.0.6 应为 `'arm64-v8a'`（v0.0.5 曾声称三 ABI） |
| 签名变更记录 | Release `v0.0.6` 说明中的「请先卸载旧版」提示，与本文「签名变更与升级须知」一致 |
| 可复现构建 | 仓库 README「自行构建」；不依赖任何私有 Maven 仓库或私有依赖 |
| CI | 仓库 `.github/workflows/ci.yml`（静态检查 + 单元测试） |
| 权限清单对比 | 仓库 `android/app/src/main/AndroidManifest.xml`（v0.0.6 已删除安装权限） |
| 明文流量配置 | 仓库 `android/app/src/main/res/xml/network_security_config.xml`（`cleartextTrafficPermitted="false"`） |
| 历史版本记录 | Release 说明与 git 提交历史，可核对整改前后的实际差异 |
| 报毒截图 | `{{待填：附上 MIUI 拦截弹窗截图文件名或链接}}` |

补充说明：仓库公开、提交历史完整，**不存在「发布包与源码不一致」的可能性**——所有构建参数都在 README 中给出，任何人都能本地复现同一份代码的构建。

---

## 附：自查用的命令

以下命令在 Windows PowerShell / Linux / macOS 上均可执行（`build-tools` 取 Android SDK 中的实际版本号，此处以 `35.0.0` 为例）。

### 1. 核对包名、版本与权限清单

```bash
# Windows: %ANDROID_HOME%\build-tools\35.0.0\aapt2.exe
aapt2 dump badging xiaojingyu-0.0.6-arm64-v8a.apk
aapt2 dump permissions xiaojingyu-0.0.6-arm64-v8a.apk
```

预期输出（v0.0.6；v0.0.5 的差异只有版本号与多一条安装权限）：

```text
package: name='cn.flashsave.flashsave' versionCode='6' versionName='0.0.6'
minSdkVersion:'24'
targetSdkVersion:'36'
native-code: 'arm64-v8a'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE' maxSdkVersion='29'
uses-permission: name='cn.flashsave.flashsave.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

> `dump badging` 对 v0.0.5 会额外打印 `uses-implied-permission: 'READ_EXTERNAL_STORAGE'`，那是根据 WRITE 推导的隐含项，并非声明权限；以 `dump permissions` 的输出为准。

### 2. 核对签名证书

```bash
apksigner verify --print-certs --verbose xiaojingyu-0.0.6-arm64-v8a.apk
```

预期看到 `Signer #1 certificate DN: CN=Little Whale, OU=Mobile, O=Little Whale Studio, ...`
与 `Signer #1 certificate SHA-256 digest: f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827`，
以及 `Verified using v2 scheme: true`、`Verified using v3 scheme: true`。

> 注意：v0.0.6 未启用 v1 签名，因此 `keytool -printcert -jarfile` 会报错，必须用 `apksigner`。

### 3. 核对 DEX 中是否存在动态加载 / 命令执行

```bash
# 解包（只读，不执行）
unzip -o xiaojingyu-0.0.6-arm64-v8a.apk -d unz

# 打印类表（v0.0.5 为 1152 个 class_defs；v0.0.6 因移除 JNI 桥会略少）
dexdump -l plain unz/classes.dex | grep -E "DexClassLoader|PathClassLoader|ProcessBuilder|dalvik/system"

# 字符串常量里查广告 / 统计 / 加固 SDK 特征
dexdump -l plain unz/classes.dex | grep -iE "umeng|gdt|pangle|bytedance|sigmob|mintegral|appsflyer|bugly|jiagu"
```

上述两条命令在 v0.0.5 与 v0.0.6 上均为**零输出**。

### 4. 核对是否为 release 构建

```bash
unzip -l xiaojingyu-0.0.6-arm64-v8a.apk | grep -E "kernel_blob|flutter_assets"
```

`assets/flutter_assets/` 下**没有** `kernel_blob.bin`，说明是 AOT 编译的 release 包（调试包才会包含该文件）。

### 5. 核对文件哈希

```powershell
# Windows：应输出 ACDBD2D18A28EF8D9327ECD65941AC860B255121026D2383EACA22B9D538FB90（大小写不敏感）
Get-FileHash .\xiaojingyu-0.0.6-arm64-v8a.apk -Algorithm SHA256
```

```bash
# Linux / macOS
sha256sum xiaojingyu-0.0.6-arm64-v8a.apk
```

> 以上命令对 v0.0.5 同样适用：把文件名换成 `xiaojingyu-0.0.5-arm64-v8a.apk`，其 SHA-256 为 `5b1d0b2ebb2128e220e4d0b0a660afafc16782e71b49b693cc7e5cba0154eafc`（历史样本，已不再分发）。

---

## 我们请求的处理

1. **人工复核样本**（被报样本 v0.0.5 与整改版 v0.0.6，SHA-256 见上表），确认其中不存在恶意代码与恶意行为链。
2. 如复核结论为无害，请将样本移出 `a.gray.BulimiaTGen.f`，并将证书 SHA-256 `f2c266e8...3827` 对应的版本（v0.0.6 及以后）加入白名单。
3. 若贵方认为仍需进一步收敛某些特征，请告知具体规则指向（权限、组件、行为或渠道），我们愿意继续整改并同步发布。
4. 我们不会要求「无条件免检」。我们要的是一次基于实际取证的复核，以及一份可对照整改的结论。

> **我们明确不作如下承诺**：本次整改不保证「以后永不再被任何引擎报毒」。代码层整改可以消除已确认的高权重特征，最终判定仍取决于各厂商病毒库的规则与样本积累。这也是我们主动提交复核、并计划逐步上架正规应用商店的原因。

---

*本文档随版本更新。取证方法与数据以 `docs/SECURITY.md` 及仓库 Release 页公布的文件哈希为准。*
