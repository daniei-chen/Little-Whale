/// 应用级配置 —— 版本号与更新检查地址。
///
/// 【为什么版本号写在这里而不是用 package_info_plus】
/// 少一个依赖就少一处构建风险。代价是可能和 pubspec.yaml 脱节 ——
/// 所以有一条单元测试专门比对两者。改了 pubspec 忘了改这里，测试会红。
library;

/// 展示给用户的版本号，必须与 pubspec.yaml 的 `version:` 前半段一致
const String kAppVersion = '0.0.9';

/// 构建号，必须与 pubspec.yaml 的 `version:` 后半段一致（`0.0.9+9` 里的 9）。
/// **更新判断只比这个数**，比字符串版本号可靠。
const int kAppBuild = 9;

/* ---------------------------------------------------------------------- */
/* 更新检查                                                                */
/* ---------------------------------------------------------------------- */
//
// 【地址仍然可以在构建时注入，但现在有默认兜底】
//
// 地址原则没变：能通过 --dart-define 注入，方便换成自己的服务器：
//   flutter build apk --release \
//     --dart-define=UPDATE_URL=https://<域名>/app/version.json \
//     --dart-define=UPDATE_URL_ALT=<备用清单> \
//     --dart-define=DOWNLOAD_PAGE=<下载页>
// 发版脚本会读 tools/build.config.ps1（不进仓库）自动带上这些参数。
//
// ★ 但 defaultValue 是必须的 —— 这是 v0.0.9 修的一个真实事故 ★
//
// 以前这里是纯 String.fromEnvironment('UPDATE_URL')：没注入就是空字符串，
// 而 UpdateService.check() 遇到空字符串**直接 return null**。于是
// 「构建时忘了配地址」不会报错、不会警告，只会静默地让整个更新检测失效。
// v0.0.6 ~ v0.0.8 就是这样：用户在 App 里永远等不到更新提示，
// 只能隔一段时间自己上 GitHub 看有没有新版。
//
// 现在默认值指向 jsDelivr（转发本仓库的 server/version.json），
// 所以**忘了注入也照样能检查更新**；要换自己的服务器再覆盖即可。
// 从仓库 clone 下来自己构建的人也会收到更新提醒 —— 这是有意为之：
// 与其静默失效，不如让人知道有新版。

/// 更新清单主地址（jsDelivr 转发仓库内的 server/version.json，国内可直连）
const String kUpdateManifestUrl = String.fromEnvironment(
  'UPDATE_URL',
  defaultValue:
      'https://cdn.jsdelivr.net/gh/daniei-chen/Little-Whale@main/server/version.json',
);

/// 更新清单备用地址（GitHub raw，无 CDN 缓存）。
/// 主地址是 jsDelivr，带 CDN 缓存，发版后可能短时间返回旧清单 ——
/// 主源没给出「有新版」时 UpdateService 会再问一次这里。
const String kUpdateManifestUrlAlt = String.fromEnvironment(
  'UPDATE_URL_ALT',
  defaultValue:
      'https://raw.githubusercontent.com/daniei-chen/Little-Whale/main/server/version.json',
);

/// 下载页地址。更新清单里带了 `url` 就用清单的，没带就用这个。
const String kDownloadPageUrl = String.fromEnvironment(
  'DOWNLOAD_PAGE',
  defaultValue: 'https://github.com/daniei-chen/Little-Whale/releases/latest',
);

/// 更新检查的冷却时间：同一个版本一天最多提醒一次。
const Duration kUpdateCheckInterval = Duration(hours: 24);