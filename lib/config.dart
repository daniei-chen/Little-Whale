/// 应用级配置 —— 版本号与更新检查地址。
///
/// 【为什么版本号写在这里而不是用 package_info_plus】
/// 少一个依赖就少一处构建风险。代价是可能和 pubspec.yaml 脱节 ——
/// 所以有一条单元测试专门比对两者（见 test/widget_test.dart 的
/// 「版本号必须和 pubspec 一致」）。改了 pubspec 忘了改这里，测试会红。
library;

/// 展示给用户的版本号，必须与 pubspec.yaml 的 `version:` 前半段一致
const String kAppVersion = '0.0.2';

/// 构建号，必须与 pubspec.yaml 的 `version:` 后半段一致（`1.0.0+1` 里的 1）。
/// **更新判断只比这个数**，比字符串版本号可靠。
const int kAppBuild = 2;

/// 更新清单地址。
///
/// 【主地址走自己的服务器】国内直连、可控、随时能改。
///
/// 【为什么不用 GitHub 原始地址】`raw.githubusercontent.com` 在国内**被墙**，
/// Release 附件走的 `objects.githubusercontent.com` 国内也基本连不上 ——
/// 用户不翻墙拿不到更新。
///
/// 备用地址用 **jsDelivr**（它把 GitHub 仓库的文件当 CDN 发，国内实测可直连）。
/// 两个地址任一可用就能检查到更新，单一渠道挂掉不影响。
const String kUpdateManifestUrl =
    'https://whale.kaogong.art/app/version.json';

/// 备用地址：jsDelivr 转发同一个仓库里的清单文件
const String kUpdateManifestUrlAlt =
    'https://cdn.jsdelivr.net/gh/daniei-chen/Little-Whale@main/server/version.json';

/// 检查更新的冷却时间：同一个版本一天最多提醒一次，
/// 免得每次启动都弹窗烦人。
const Duration kUpdateCheckInterval = Duration(hours: 24);
