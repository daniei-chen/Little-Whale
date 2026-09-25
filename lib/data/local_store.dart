import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parse_result.dart';

/// 偏好设置
class AppSettings {
  /// 默认保存原片（无平台水印的版本）

  /// 进 App 自动读取剪贴板；识别到支持的平台后**直接开始解析**
  final bool autoPaste;

  /// 直连下载：绕过服务器代理，直接向平台 CDN 取流。
  /// 省服务器流量，但依赖平台反盗链策略，失败会自动回退到代理。
  final bool directDownload;

  /// 解析方式：
  ///   'local'  优先在手机里完成（内置 WebView），跑不通时**自动回退服务器**。默认。
  ///   'server' 只用服务器，不尝试本地
  final String parseMode;

  /// 解析服务地址（本地模式回退时也会用到）
  final String apiBase;

  const AppSettings({
    this.autoPaste = true,
    this.directDownload = false,
    this.parseMode = 'local',
    this.apiBase = kDefaultApiBase,
  });

  /// 默认指向 Android 模拟器访问宿主机的特殊地址。
  /// 正式使用请在「我的 → 解析服务」里改成你自己的域名。
  static const kDefaultApiBase = 'http://10.0.2.2:8787';

  AppSettings copyWith({
    bool? autoPaste,
    bool? directDownload,
    String? parseMode,
    String? apiBase,
  }) =>
      AppSettings(
        autoPaste: autoPaste ?? this.autoPaste,
        directDownload: directDownload ?? this.directDownload,
        parseMode: parseMode ?? this.parseMode,
        apiBase: apiBase ?? this.apiBase,
      );

  Map<String, dynamic> toJson() => {
        'autoPaste': autoPaste,
        'directDownload': directDownload,
        'parseMode': parseMode,
        'apiBase': apiBase,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        // 默认开：老版本存过 false 的用户会保留自己的选择，没存过的走新默认值
        autoPaste: j['autoPaste'] != false,
        directDownload: j['directDownload'] == true,
        parseMode: (j['parseMode'] as String?) == 'server' ? 'server' : 'local',
        apiBase: (j['apiBase'] as String?)?.trim().isNotEmpty == true
            ? (j['apiBase'] as String).trim()
            : kDefaultApiBase,
      );
}

/// 解析统计
class AppStat {
  final int total;
  final int today;
  final String date;

  const AppStat({this.total = 0, this.today = 0, this.date = ''});

  AppStat copyWith({int? total, int? today, String? date}) => AppStat(
        total: total ?? this.total,
        today: today ?? this.today,
        date: date ?? this.date,
      );

  Map<String, dynamic> toJson() => {'total': total, 'today': today, 'date': date};

  factory AppStat.fromJson(Map<String, dynamic> j) => AppStat(
        total: (j['total'] as num?)?.toInt() ?? 0,
        today: (j['today'] as num?)?.toInt() ?? 0,
        date: (j['date'] ?? '') as String,
      );
}

/// 本地存储：历史记录 / 统计 / 偏好。全部只存在本机，不上传。
class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  static const _kHistory = 'fs_history';
  static const _kStat = 'fs_stat';
  static const _kSettings = 'fs_settings';
  static const maxHistory = 100;

  SharedPreferences? _sp;

  /// 仅供测试：丢掉缓存的 SharedPreferences 实例。
  ///
  /// 测试里要反复用 `SharedPreferences.setMockInitialValues` 造数据，
  /// 而它**必须在第一次 getInstance 之前**调用才生效；
  /// 单例把实例缓存住了，所以需要这个钩子把缓存清掉。
  @visibleForTesting
  void resetCacheForTests() => _sp = null;

  Future<SharedPreferences> get _prefs async =>
      _sp ??= await SharedPreferences.getInstance();

  /* ---------------- 历史记录 ---------------- */

  Future<List<ParseResult>> getHistory() async {
    final sp = await _prefs;
    final raw = sp.getStringList(_kHistory) ?? const [];
    final out = <ParseResult>[];
    for (final s in raw) {
      try {
        out.add(ParseResult.decode(s));
      } catch (_) {
        // 单条损坏不影响整体
      }
    }
    return out;
  }

  Future<List<ParseResult>> addHistory(ParseResult item) async {
    final list = await getHistory();
    list.removeWhere((e) => e.id == item.id);
    list.insert(0, item);
    final trimmed = list.take(maxHistory).toList();
    await _writeHistory(trimmed);
    return trimmed;
  }

  Future<List<ParseResult>> removeHistory(String id) async {
    final list = await getHistory();
    list.removeWhere((e) => e.id == id);
    await _writeHistory(list);
    return list;
  }

  Future<void> clearHistory() async {
    final sp = await _prefs;
    await sp.remove(_kHistory);
  }

  Future<void> _writeHistory(List<ParseResult> list) async {
    final sp = await _prefs;
    await sp.setStringList(_kHistory, list.map((e) => e.encode()).toList());
  }

  /* ---------------- 统计 ---------------- */

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<AppStat> getStat() async {
    final sp = await _prefs;
    var stat = const AppStat();
    final s = sp.getString(_kStat);
    if (s != null) {
      try {
        stat = AppStat.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    if (stat.date != _today()) {
      stat = stat.copyWith(today: 0, date: _today());
      await sp.setString(_kStat, jsonEncode(stat.toJson()));
    }
    return stat;
  }

  Future<AppStat> bumpStat() async {
    final stat = await getStat();
    final next = stat.copyWith(total: stat.total + 1, today: stat.today + 1, date: _today());
    final sp = await _prefs;
    await sp.setString(_kStat, jsonEncode(next.toJson()));
    return next;
  }

  Future<void> resetStat() async {
    final sp = await _prefs;
    await sp.remove(_kStat);
  }

  /* ---------------- 偏好 ---------------- */

  Future<AppSettings> getSettings() async {
    final sp = await _prefs;
    final s = sp.getString(_kSettings);
    if (s == null) return const AppSettings();
    try {
      return AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<AppSettings> saveSettings(AppSettings v) async {
    final sp = await _prefs;
    await sp.setString(_kSettings, jsonEncode(v.toJson()));
    return v;
  }

  /// 本地数据体积（KB）—— 用于「清空本地数据」那一项
  Future<int> cacheSizeKb() async {
    final sp = await _prefs;
    var bytes = 0;
    for (final k in sp.getKeys()) {
      final v = sp.get(k);
      if (v is String) bytes += v.length;
      if (v is List) {
        for (final e in v) {
          if (e is String) bytes += e.length;
        }
      }
    }
    return (bytes / 1024).ceil();
  }
}

/// 时间戳 → 刚刚 / 5 分钟前 / 昨天 12:30 / 09-20 12:30 / 2026-09-20
String formatRelative(int ts, {DateTime? now}) {
  if (ts <= 0) return '';
  final n = now ?? DateTime.now();
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final diff = n.difference(d);

  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';

  final yesterday = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
  final sameDay = d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
  String two(int v) => v.toString().padLeft(2, '0');

  if (sameDay) return '昨天 ${two(d.hour)}:${two(d.minute)}';
  if (diff.inDays < 7) return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
