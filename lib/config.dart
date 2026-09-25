/// 应用级配置 —— 版本号与更新检查地址。
///
/// 【为什么版本号写在这里而不是用 package_info_plus】
/// 少一个依赖就少一处构建风险。代价是可能和 pubspec.yaml 脱节 ——
/// 所以有一条单元测试专门比对两者。改了 pubspec 忘了改这里，测试会红。
library;

/// 展示给用户的版本号，必须与 pubspec.yaml 的 `version:` 前半段一致
const String kAppVersion = '0.0.4';

/// 构建号，必须与 pubspec.yaml 的 `version:` 后半段一致（`0.0.3+3` 里的 3）。
/// **更新判断只比这个数**，比字符串版本号可靠。
const int kAppBuild = 4;

/* ---------------------------------------------------------------------- */
/* 更新检查                                                                */
/* ---------------------------------------------------------------------- */
//
// 【地址为什么是构建时注入的，而不是写死在这里】
//
// 这些地址指向自己的服务器。源代码是公开的，写死就等于把服务器地址
// 印在 GitHub 上 —— 没必要对外暴露。
//
// 所以改成构建时通过 --dart-define 注入：
//   flutter build apk --release \
//     --dart-define=UPDATE_URL=https://<域名>/app/version.json \
//     --dart-define=UPDATE_URL_ALT=https://cdn.jsdelivr.net/gh/<用户>/<仓库>@main/server/version.json \
//     --dart-define=DOWNLOAD_PAGE=https://<域名>/app/
//
// 发版脚本 tools/release.ps1 会自动读 tools/build.config.ps1（不进仓库）
// 把这些参数带上。
//
// 留空的效果：**跳过更新检查**，App 其它功能完全正常。
// 也就是说从仓库 clone 下来直接构建是能跑的，只是没有更新提醒。

/// 更新清单主地址（自己的服务器，国内直连）
const String kUpdateManifestUrl = String.fromEnvironment('UPDATE_URL');

/// 更新清单备用地址（jsDelivr 转发 GitHub 上的副本，国内同样可直连）。
/// 主地址不通时会自动试这个 —— 单一渠道挂掉不影响用户收到更新。
const String kUpdateManifestUrlAlt = String.fromEnvironment('UPDATE_URL_ALT');

/// 下载页地址。更新清单里带了 `url` 就用清单的，没带就用这个。
const String kDownloadPageUrl = String.fromEnvironment('DOWNLOAD_PAGE');

/// 更新检查的冷却时间：同一个版本一天最多提醒一次。
const Duration kUpdateCheckInterval = Duration(hours: 24);