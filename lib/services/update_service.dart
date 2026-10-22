import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// 一条更新信息
class UpdateInfo {
  final int build;
  final String version;
  final String url;
  final String notes;
  final bool force;

  /// 安装包大小（字节）。清单里没给就是 0。
  ///
  /// v0.0.6 起 App **不再下载安装包**，所以这个字段只用于在
  /// 「有新版」对话框里顺带告诉用户「大概多大」，不参与任何逻辑。
  final int size;

  const UpdateInfo({
    required this.build,
    required this.version,
    required this.url,
    this.notes = '',
    this.force = false,
    this.size = 0,
  });

  /// 从服务器的 version.json 解析
  static UpdateInfo? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final build = (raw['build'] as num?)?.toInt() ?? 0;
    final url = (raw['url'] ?? '').toString();

    // 【url 允许为空】备用清单里故意不写域名（避免公开仓库暴露服务器地址），
    // 这时用构建时注入的下载页兜底。
    // 但两个都拿不到，就等于「提示有新版、点了却打不开」—— 那还不如当成
    // 脏数据直接忽略，别去打扰用户。
    final target = url.isNotEmpty ? url : kDownloadPageUrl;
    if (build <= 0 || target.isEmpty) return null;

    return UpdateInfo(
      build: build,
      version: (raw['version'] ?? '').toString(),
      url: target,
      notes: (raw['notes'] ?? '').toString(),
      force: raw['force'] == true,
      size: (raw['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 检查更新。
///
/// 【为什么不用 Google 的应用内更新】国内设备上 Google Play 服务大多不可用，
/// 那条路走不通。所以这里走最朴素也最可靠的方式：
/// 从**自己的服务器**拉一个 JSON，比构建号，比出来就提示 + 跳下载页。
///
/// 【为什么只检查、不下载（v0.0.6 整改）】
/// v0.0.5 及以前是「App 内下载 APK → 拉起系统安装器」。功能上没问题，
/// 但静态扫描眼里这套组合是：
///     REQUEST_INSTALL_PACKAGES + 下载 .apk + ACTION_VIEW
///     + application/vnd.android.package-archive
/// 和推广/捆绑/自我更新的灰色软件特征完全重合 —— 这是包被判
/// a.gray.BulimiaTGen.f（进而被 MIUI 高危拦截、反诈中心来电核实）
/// 的最大单一原因。
///
/// 所以现在职责只剩一件事：**告诉用户有没有新版，并把下载页交出去**。
/// App 自身不再写入任何 .apk 文件、不再持有安装相关权限、不再请求安装。
/// 代价是更新少了个进度条，换来的是不再被当成高危应用 —— 这个交换值得。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _prefsKey = 'update_last_notified_build';

  /// 检查有没有新版本。没有新版本、没配置地址、网络失败都返回 null ——
  /// **更新检查永远不该打扰用户**，失败就静默跳过。
  Future<UpdateInfo?> check({bool ignoreCooldown = false}) async {
    if (kUpdateManifestUrl.isEmpty) return null;

    final info = await _fetch(kUpdateManifestUrl) ??
        await _fetch(kUpdateManifestUrlAlt); // 主节点不通就换备用节点
    if (info == null) return null;

    // 服务器上的构建号比本机大，才算有新版本
    if (info.build <= kAppBuild) return null;

    // 冷却：同一个新版本一天只提醒一次（强制更新不受限）
    if (!ignoreCooldown && !info.force) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getInt(_prefsKey) == info.build) return null;
      } catch (_) {}
    }
    return info;
  }

  Future<UpdateInfo?> _fetch(String url) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (s) => s != null && s < 400,
      ));
      // 加时间戳绕开 CDN 缓存，否则发版后可能还拿到旧清单
      final r = await dio.get<dynamic>(
        url,
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
      );
      return UpdateInfo.fromJson(r.data);
    } catch (_) {
      // 网络不通、JSON 格式不对……一律当「拿不到」
      return null;
    }
  }

  /// 记下「这个版本已经提醒过了」
  Future<void> markNotified(int build) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, build);
    } catch (_) {}
  }
}
