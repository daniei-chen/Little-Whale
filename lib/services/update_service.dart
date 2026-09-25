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

  const UpdateInfo({
    required this.build,
    required this.version,
    required this.url,
    this.notes = '',
    this.force = false,
  });

  /// 从服务器的 version.json 解析
  static UpdateInfo? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final build = (raw['build'] as num?)?.toInt() ?? 0;
    final url = (raw['url'] ?? '').toString();
    if (build <= 0 || url.isEmpty) return null;
    return UpdateInfo(
      build: build,
      version: (raw['version'] ?? '').toString(),
      url: url,
      notes: (raw['notes'] ?? '').toString(),
      force: raw['force'] == true,
    );
  }
}

/// 检查更新。
///
/// 【为什么不用 Google 的应用内更新】国内设备上 Google Play 服务大多不可用，
/// 那条路走不通。所以这里走最朴素也最可靠的方式：
/// 从**自己的服务器**拉一个 JSON，比构建号，比出来就提示 + 跳下载。
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
