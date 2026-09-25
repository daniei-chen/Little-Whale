import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// 一条更新信息
class UpdateInfo {
  final int build;
  final String version;
  final String url;
  final String notes;
  final bool force;

  /// 安装包大小（字节）。清单里没给就是 0 ——
  /// 用来判断「上次是不是已经下完了」，以及显示进度。
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
  /* ------------------------------------------------------------------ */
  /* 应用内下载新版本                                                     */
  /* ------------------------------------------------------------------ */

  /// 把新版本 APK 下到应用缓存目录，返回文件路径。
  ///
  /// 【为什么要下到缓存目录而不是相册】
  /// 更新包是临时的，不该出现在用户的相册里。放 cache/apk/ 下：
  /// 系统空间紧张时能自动回收，也不会污染用户的照片。
  /// FileProvider 的白名单里只暴露了这个目录（见 res/xml/file_paths.xml）。
  Future<String> downloadApk(
    UpdateInfo info, {
    void Function(double progress, int received, int total)? onProgress,
  }) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/apk');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // 文件名带版本和构建号，避免和上一版混淆（也便于续传时识别）
    final file = File('${dir.path}/xiaojingyu-${info.version}-${info.build}.apk');

    // 已经下好且大小对得上，直接复用 —— 用户可能点了取消又想装
    if (await file.exists() && info.size > 0 && await file.length() == info.size) {
      onProgress?.call(1, info.size, info.size);
      return file.path;
    }

    final done = file.existsSync() ? await file.length() : 0;
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 30),
      validateStatus: (s) => s != null && s < 400,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      },
    ));

    await dio.download(
      info.url,
      file.path,
      // 断点续传：上次下到一半就接着下
      options: Options(headers: done > 0 ? {'Range': 'bytes=$done-'} : null),
      deleteOnError: false,
      onReceiveProgress: (received, total) {
        final full = total > 0 ? total + done : (info.size > 0 ? info.size : 0);
        final got = received + done;
        onProgress?.call(full > 0 ? (got / full).clamp(0, 1) : 0, got, full);
      },
    );

    return file.path;
  }
}
