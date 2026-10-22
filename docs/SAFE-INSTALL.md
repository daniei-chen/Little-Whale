# 安装与验签指南

> 面向第一次安装小鲸鱼、或安装时被手机拦截的用户。全程不需要 root，不需要开发者工具（核对签名那一步除外）。
>
> 如果你还没看过「为什么会报毒」，先读 [SECURITY.md](./SECURITY.md)，这里只讲**怎么做**。

> ⚠️ **v0.0.6 更换了签名证书：v0.0.5 及更早版本无法覆盖升级，必须先卸载旧版再装。**
> 卸载会清空解析记录，**已保存到相册的图片和视频不受影响**。新指纹见第三部分；**以前公布过的旧指纹全部作废**，拿旧指纹核对新包一定对不上。

---

## 一、从 Releases 下载正确的 APK

### 1. 打开发布页

<https://github.com/daniei-chen/Little-Whale/releases>

选最上面那个版本（标记为 `Latest`）。**不要**从 Issue、群聊、网盘、第三方下载站拿安装包。

### 2. 找到 Assets 区域

页面往下拉到 **Assets** 折叠区，里面会有若干文件。你要的是结尾为 `.apk` 的那一个：

| 文件 | 要不要 |
|---|---|
| `xiaojingyu-<版本>-arm64-v8a.apk` | ✅ **要这个** |
| `Source code (zip)` / `Source code (tar.gz)` | ❌ 这是源码，不是安装包 |
| `*.sha256` / `checksums.txt`（若存在） | ✅ 用来核对哈希 |
| 任何 `*.apk` 之外的压缩包 | ❌ 不是安装包 |

### 3. 确认 ABI 匹配

v0.0.6 只发布 **arm64-v8a**（64 位 ARM），`aapt2 dump badging` 的 `native-code` 行只有 `'arm64-v8a'`。覆盖基本所有 2016 年之后的 Android 手机。

> v0.0.5 曾声称支持三个 ABI，但 `lib/armeabi-v7a/`、`lib/x86_64/` 里缺 `libflutter.so` / `libapp.so`，32 位机与模拟器装上会直接崩溃。这个打包缺陷已在 v0.0.6 修复（不再「假装支持」）。

- 装的时候提示「解析包时出现问题」或「应用未安装」→ 大概率是 ABI 不匹配（极老的 32 位设备）
- 想知道自己的机型：设置 → 关于手机 → 处理器 / 内核架构，或直接试装

### 4. 下载并允许浏览器保存文件

用 Chrome / Edge 下载后，文件一般在 `Download` 目录。MIUI 可能提示「此类文件可能有害」——这是对所有 APK 的通用提示，不是你这一份的问题。

---

## 二、核对 APK 的 SHA-256

哈希的作用：确认你手上的文件和开发者发布的文件**逐字节相同**。哪怕只有一个字节被改，哈希就完全不同。

### 官方公布的哈希

| 版本 | 文件名 | SHA-256 |
|---|---|---|
| `v0.0.6`（当前） | `xiaojingyu-0.0.6-arm64-v8a.apk` | `ACDBD2D18A28EF8D9327ECD65941AC860B255121026D2383EACA22B9D538FB90` |
| `v0.0.5`（历史，已不再分发） | `xiaojingyu-0.0.5-arm64-v8a.apk` | `5b1d0b2ebb2128e220e4d0b0a660afafc16782e71b49b693cc7e5cba0154eafc` |

> 哈希比对**大小写不敏感**。`v0.0.6` 的哈希以 Release 页面最终上传件为准——如果修复构建又出了新包，我们会在 Release 说明里同步更新。

### 在电脑上算

**Windows（PowerShell）**

```powershell
Get-FileHash .\xiaojingyu-0.0.6-arm64-v8a.apk -Algorithm SHA256
```

**Windows（CMD）**

```cmd
certutil -hashfile xiaojingyu-0.0.6-arm64-v8a.apk SHA256
```

**macOS**

```bash
shasum -a 256 xiaojingyu-0.0.6-arm64-v8a.apk
```

**Linux**

```bash
sha256sum xiaojingyu-0.0.6-arm64-v8a.apk
```

输出是一串 64 位十六进制字符，与上表逐字符比对（大小写不敏感）。

### 在手机上算

装一个带校验和功能的文件管理器（如 MT 管理器），长按 APK → 属性 → 复制「SHA-256」比对；或者把文件传回电脑算。没有校验工具也不影响——签名核对同样能发现问题。

### 什么时候该停下

| 情况 | 判断 |
|---|---|
| 哈希与官方一致 | ✅ 文件没被改过，继续 |
| 哈希不一致，但签名证书一致 | ⚠️ 可能是官方重新构建过同一版本（极少见），先问开发者 |
| **哈希不一致，签名也不一致** | ❌ **绝对不要安装**，说明包被人重新签名替换过 |
| Release 里根本没公布哈希 | ⚠️ 退一步做签名核对（第三部分），并联系开发者补上 |

---

## 三、核对签名指纹

哈希能证明「文件没被改」，签名能证明「这个包是谁做的」。两者一起看才完整。

### 官方签名证书

| 项目 | 值 |
|---|---|
| 证书主体（DN） | `CN=Little Whale, OU=Mobile, O=Little Whale Studio, L=Shenzhen, ST=Guangdong, C=CN` |
| 证书 SHA-256 | `f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827` |
| 证书 SHA-1 | `df6253483028ec3968ffe613fcf3890126aaa866` |
| 证书 MD5 | `f48343deccb0bfba6a4fbcc7ad1e9820` |
| 公钥 | RSA 2048 |

> 以上为 `v0.0.6` 发布包的实测值（**当前证书**）。v0.0.5 及更早版本用的是上一代证书，指纹与上表不同——所以从旧版升级必须先卸载，见文首提示。

### 在电脑上核对（推荐）

需要 Android SDK 的 build-tools（任意 30.0.0 以上版本）。

```bash
# Windows 路径示例（Git Bash / PowerShell 均可）
"%ANDROID_HOME%\build-tools\35.0.0\apksigner.bat" verify --print-certs --verbose xiaojingyu-0.0.6-arm64-v8a.apk
```

预期输出中关键几行：

```text
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Number of signers: 1
Signer #1 certificate DN: CN=Little Whale, OU=Mobile, O=Little Whale Studio, L=Shenzhen, ST=Guangdong, C=CN
Signer #1 certificate SHA-256 digest: f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827
Signer #1 key algorithm: RSA
Signer #1 key size (bits): 2048
```

**怎样算通过**：摘要与上表完全一致、`Number of signers: 1`、且出现 `Verifies`（文件在签名后未被篡改）。

### ⚠️ 一个常见的坑：`keytool` 会报错

网上很多教程让你用：

```bash
keytool -printcert -jarfile app.apk
```

对小鲸鱼**会失败**，报「不是已签名的 jar 文件」——因为我们的包**没有启用 v1（JAR）签名**，用的是 v2 + v3。v1 签名会在 APK 里生成 `META-INF/CERT.RSA`，而我们的包里没有这个文件。

这种情况下必须用 `apksigner verify --print-certs`（它会解析 v2/v3 签名块）。这不是包有问题，是工具选错了。

### 在手机上核对

手机上没有 `apksigner`，可选的替代方案：

- **MT 管理器**：长按 APK → 「APK 签名」/「查看签名」，可看到证书 DN 与 SHA-256
- 任何展示「证书指纹」的签名校验类小工具

只要主体里出现 `CN=Little Whale` 且 SHA-256 前缀为 `f2c266e8`，就是当前官方证书。如果显示 `CN=Android Debug`，说明这是**从源码自己构建的调试包**（也能用，但不是官方发布版，更新会失败）。

### 判断表

| 签名 SHA-256 | 结论 |
|---|---|
| `f2c266e8...3827` | ✅ 官方发布版（v0.0.6 及以后） |
| `CN=Android Debug`（自行构建） | ⚠️ 不是官方包，功能正常但**无法接收官方更新**（签名不同，装新版必须先卸载） |
| 其他任何值 | ❌ 不是官方包，**不要安装**。注意：v0.0.5 时代的旧证书指纹也已作废，如果你手上是旧版包，建议直接卸载改装 v0.0.6 |

---

## 四、MIUI 拦截时的逐屏操作

前提：**你已经在第二、三部分核对过哈希与签名**。没核对过的，先回去核对。

不同 MIUI / HyperOS 版本文案略有差异，下表按常见顺序排列：

| # | 屏幕上出现什么 | 你要点哪里 |
|---|---|---|
| 1 | 「禁止安装未知来源应用」/「出于安全考虑，您的手机不允许安装此来源的应用」 | 点「设置」→ 打开「允许安装未知应用」→ 返回继续（详见第五节） |
| 2 | 「应用未经安全检测」/「未知来源应用」 | 点「继续安装」或「仍然安装」 |
| 3 | **「发现风险：安装该应用存在高风险，请谨慎安装！」** | 点弹窗底部「继续安装」；若没有该按钮，看右上角「更多」→「仍要安装」；部分版本需要先点「忽略风险」 |
| 4 | 二次确认页（常见「我已了解该应用存在风险」勾选框） | 勾选后点「仍然安装」 |
| 5 | 系统安装器（显示应用名、权限列表） | 确认应用名是「小鲸鱼」、权限只有联网/网络状态/存储三项 → 点「安装」 |
| 6 | 装完后手机管家「病毒扫描」把它列为风险项 | 单项点「忽略」或「加入信任」；不要点「清除」，那会卸载 |
| 7 | 反复弹窗、每次打开都提示 | 手机管家 → 右上角设置 → 关闭「安装监控」或把本应用加入信任名单 |

### 如果按钮是灰的、点不动

通常是这两种保护机制之一在生效：

| 机制 | 位置（路径随版本变化） | 处理 |
|---|---|---|
| **纯净模式 / 增强防护** | 设置 → 应用设置 → 纯净模式；或设置 → 安全 → 纯净模式 | 退出/关闭纯净模式（可能需要登录小米账号）。**这是全局开关，关掉会降低对未知来源应用的防护，装完建议开回来** |
| **安装未知应用未授权** | 见第五节 | 给「下载该 APK 的那个应用」授权 |

### 装完之后

- 首次启动若弹「是否允许联网」之类提示，正常允许即可（App 需要联网才能解析）
- 如果手机管家持续后台提示，可在「病毒扫描 → 设置」里把该应用加入白名单
- 想彻底避开弹窗：只能等我们上架正规应用商店（正在计划中），或者自行从源码构建

---

## 五、开启「安装未知来源应用」

从 Android 8.0 起，这个权限是**按来源应用授权**的——你用什么下载的 APK，就要给谁授权。

### 路径（Android 8.0 以上 / MIUI）

```
设置 → 应用设置 → 应用管理 → 找到「Chrome」（或你用的浏览器 / 文件管理器）
→ 打开「安装未知应用」/「安装其他应用」开关 → 允许
```

或者从安装失败弹窗里点「设置」，系统会**直接跳到对应应用的授权页**——这是最快的路径。

其他机型可走「设置 → 隐私保护 → 特殊权限设置 → 安装未知应用 → 选择来源应用 → 允许」（部分机型为「设置 → 应用 → 特殊应用权限」）。

> 只给你实际用来下载的那个应用授权（通常是浏览器），不要批量全开；装完之后可以把这个开关关掉，不影响已安装应用的运行。

---

## 六、怎样判断你装的是不是官方包

装之前核对文件，装之后核对运行表现。两个都过，基本不会有问题。

### 装之前（文件层面）

| 检查项 | 官方值 |
|---|---|
| 包名 | `cn.flashsave.flashsave` |
| 应用名 | 小鲸鱼 |
| 签名证书 SHA-256 | `f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827` |
| 签名主体 | `CN=Little Whale, O=Little Whale Studio` |
| 版本号 | 与 Release 标签一致（v0.0.6：versionName `0.0.6` / versionCode `6`） |
| 文件 SHA-256 | 与 Release 说明一致 |
| 大小 | v0.0.6 为 **21,014,208 字节**（约 20.0 MiB）；以 Release 页面显示为准 |

查看包名与权限（电脑上）：

```bash
aapt2 dump badging xiaojingyu-0.0.6-arm64-v8a.apk
aapt2 dump permissions xiaojingyu-0.0.6-arm64-v8a.apk
```

v0.0.6 的权限应该**只有三条系统权限 + 一条自定义注入项**（v0.0.5 多一条安装权限）：

```text
INTERNET
ACCESS_NETWORK_STATE
WRITE_EXTERNAL_STORAGE (maxSdkVersion=29)
cn.flashsave.flashsave.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION  ← androidx 清单合并自动注入

（v0.0.5 另有 REQUEST_INSTALL_PACKAGES，v0.0.6 已删除）
```

> **别被 `dump badging` 误导**：它会对声明了 `WRITE_EXTERNAL_STORAGE` 的包额外打印一条 `uses-implied-permission: 'READ_EXTERNAL_STORAGE'`，那是工具**推导**出来的，`AndroidManifest.xml` 里并没有声明读权限——以 `dump permissions` 为准。

### 装之后（行为层面）

| 应该出现 | 不该出现 |
|---|---|
| 打开就是解析首页，没有开屏广告 | 开屏广告、悬浮广告、推广卡片 |
| 权限只有联网/网络状态/存储 | 索要短信、通讯录、位置、应用列表、通知使用权、无障碍服务 |
| 「我的 → 关于/版本」显示与下载版本一致 | 版本显示为 `0.0.1` 之类明显不符的值 |
| 点「检查更新」会跳到浏览器 | App 内直接下载 APK 并拉起安装器（v0.0.6 起已无此能力） |
| 错误日志只在本机可导出 | 任何「上传日志」「同步到云端」的入口 |

任何一项不符，**立刻卸载**，并把截图发到仓库 Issues。

---

## 七、常见问题

### 装的时候提示「应用未安装」

按概率排序：

1. **签名冲突**：机器上已有不同签名的同包名应用（例如旧版调试签名包）。先卸载旧版再装。卸载不会删除已保存到相册的文件。
2. **ABI 不匹配**：极老的 32 位设备装不了 arm64 包。
3. **下载不完整**：文件大小和官方不一致，重新下载。
4. **存储空间不足**：需要约 60 MB 余量（安装包 + 解压）。

### 从旧版升级失败

证书换过两次：v0.0.5 由调试证书换为正式证书，v0.0.6 又换了一次（原私钥丢失，无法继续签发）。所以 **v0.0.3 及更早、以及 v0.0.5 都无法覆盖升级**，必须先卸载重装。卸载只清解析记录，**相册里的图片和视频不受影响**；从 v0.0.6 起使用当前证书，之后可正常覆盖升级。

### 哈希对不上但签名对得上

极少见，通常是官方重新构建了同名版本。这种情况以 **Release 说明中的哈希**为准；说明里没有的话，到 Issues 问一声再装。

### 装完仍然被识别成病毒

v0.0.6 删掉了全部安装相关能力，但如果病毒库还没更新，**仍可能报同一个名字**。这是库的滞后，不是包变了。处理方式：按第四节加入信任，或按 [SECURITY.md](./SECURITY.md) 第三节提交误报申诉。

### 被反诈中心打电话

属例行核实。安装非应用商店渠道的高危包后系统可能上报风险事件，反诈中心会来电提醒不要被骗——**不代表你涉案**。如实说明来源（GitHub 开源项目、个人开发者、功能是保存视频）即可。详见 [SECURITY.md](./SECURITY.md) 的说明。

---

## 附：一段脚本核完所有项目（Windows PowerShell）

把 APK 放在当前目录，改一下文件名后运行：

```powershell
$apk = "xiaojingyu-0.0.6-arm64-v8a.apk"
$expectedHash = "acdbd2d18a28ef8d9327ecd65941ac860b255121026d2383eaca22b9d538fb90"
$expectedSigner = "f2c266e8fc8bacdc7aaab93eb14638222d2f2f95d03d174fe503b49c55823827"

# 1. 大小
$len = (Get-Item $apk).Length
Write-Host "大小: $len 字节"

# 2. 哈希
$hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
if ($hash -eq $expectedHash) { Write-Host "哈希: 一致 ✓" -ForegroundColor Green }
else { Write-Host "哈希: 不一致 ✗  实际=$hash" -ForegroundColor Red }

# 3. 签名（需要 apksigner，路径按自己的 SDK 改）
$apksigner = "$env:ANDROID_HOME\build-tools\35.0.0\apksigner.bat"
if (Test-Path $apksigner) {
    $out = & $apksigner verify --print-certs $apk 2>&1 | Out-String
    if ($out -match [regex]::Escape($expectedSigner)) { Write-Host "签名: 一致 ✓" -ForegroundColor Green }
    else { Write-Host "签名: 不一致 ✗" -ForegroundColor Red; Write-Host $out }
}
```

---

## 相关文档

| 文档 | 内容 |
|---|---|
| [SECURITY.md](./SECURITY.md) | 为什么会被报毒、`a.gray.BulimiaTGen.f` 是什么、我们做了什么整改 |
| [COMPLAINT-TENCENT.md](./COMPLAINT-TENCENT.md) | 误报申诉材料（可直接提交，含取证与命令） |
| [README](../README.md) | 功能说明、支持平台、自行构建 |

---

*本文档中的哈希与签名指纹均为实测值。若你发现官方发布包与本文不符，请立刻在仓库提 Issue —— 那意味着发布流程出了问题，需要第一时间处理。*
