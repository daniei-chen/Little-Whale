/// 应用级配置 —— 版本号与更新检查地址。
///
/// 【为什么版本号写在这里而不是用 package_info_plus】
/// 少一个依赖就少一处构建风险。代价是可能和 pubspec.yaml 脱节 ——
/// 所以有一条单元测试专门比对两者（见 test/widget_test.dart 的
/// 「版本号必须和 pubspec 一致」）。改了 pubspec 忘了改这里，测试会红。
library;

/// 展示给用户的版本号，必须与 pubspec.yaml 的 `version:` 前半段一致
const String kAppVersion = '0.0.1';

/// 构建号，必须与 pubspec.yaml 的 `version:` 后半段一致（`1.0.0+1` 里的 1）。
/// **更新判断只比这个数**，比字符串版本号可靠。
const int kAppBuild = 1;

/// 更新清单地址。
///
/// 【为什么走 jsDelivr 而不是 GitHub 原始地址】
/// `raw.githubusercontent.com` 在国内**被墙**，`github.com` 的 Release 下载
/// 走 `objects.githubusercontent.com`，国内也基本连不上 ——
/// 用户不翻墙就拿不到更新。
///
/// 而 **jsDelivr 在国内可以直连**（实测 `cdn.jsdelivr.net` / `fastly.jsdelivr.net`
/// 都是通的，后者 0.4 秒左右）。它能把 GitHub 仓库里的文件当 CDN 分发，
/// 所以：**版本文件放 GitHub，更新检测走 jsDelivr，用户完全不需要翻墙，也不用服务器。**
///
/// 格式：`https://cdn.jsdelivr.net/gh/{用户}/{仓库}@{分支}/{路径}`
///
/// 留空则跳过更新检查。
const String kUpdateManifestUrl =
    'https://cdn.jsdelivr.net/gh/daniei-chen/Little-Whale@main/server/version.json';

/// 更新检测的备用地址（jsDelivr 主站不通时用这个节点）
const String kUpdateManifestUrlAlt =
    'https://fastly.jsdelivr.net/gh/daniei-chen/Little-Whale@main/server/version.json';

/// 检查更新的冷却时间：同一个版本一天最多提醒一次，
/// 免得每次启动都弹窗烦人。
const Duration kUpdateCheckInterval = Duration(hours: 24);
