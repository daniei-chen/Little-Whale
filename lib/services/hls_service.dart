// HLS 下载 + 转封装：把 m3u8 变成能存进相册的 MP4。
//
// 流程（每一步都有明确失败原因，不猜）：
//   1. 下载播放列表 → parseHlsPlaylist 解析（纯函数，见 lib/local/hls.dart）
//   2. 如果是主播放列表 → 选带宽最高的子流，重新下载
//   3. 顺序下载分片，**边下边追加**到临时 .ts（不在内存里攒，41 片能到 160MB）
//   4. 调原生 TsRemuxer 换容器（不重编码）
//   5. 删除临时文件
//
// 【为什么顺序下载而不是全并发】
// 分片必须按顺序拼接，并发下载要么全部放内存（160MB，低端机会被杀），
// 要么写一堆临时文件再合并（多一次全量 IO）。顺序下载 + 追加写最省，
// 代价是多花一点时间 —— 实测 AcFun 的 41 片在模拟器上约 40 秒。

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../local/hls.dart';

/// HLS 下载结果
class HlsFetchResult {
  /// 转封装后的 MP4 路径（成功后才有）
  final String mp4Path;

  /// 时长（毫秒）
  final int durationMs;

  /// 分片数
  final int segments;

  final int bytes;

  const HlsFetchResult({
    required this.mp4Path,
    required this.durationMs,
    required this.segments,
    required this.bytes,
  });
}

/// HLS 相关错误 —— 每条都带「用户能看懂的原因」
class HlsException implements Exception {
  final String message;
  const HlsException(this.message);
  @override
  String toString() => message;
}

class HlsService {
  static const MethodChannel _ch = MethodChannel('xiaojingyu/media');

  /// 分片下载的并发度。顺序写、但可以预取：这里先用最简单的顺序下载。
  static const int _maxSegments = 600; // 兜底：超过 50 分钟的片就不下了

  /// 单条播放列表最多重定向/子流层数
  static const int _maxDepth = 3;

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    // 分片动辄几 MB，用流式下载更稳
    responseType: ResponseType.bytes,
    validateStatus: (s) => s != null && s < 400,
    headers: const {
      // 有些 CDN 会校验 UA；Android 的默认 UA 会被拒
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
    },
  ));

  /// 下载并转封装。
  ///
  /// [m3u8Url] 播放列表地址；[referer] 防盗链；[onProgress] 0..1 进度。
  static Future<HlsFetchResult> fetch({
    required String m3u8Url,
    required String referer,
    void Function(double progress, String note)? onProgress,
  }) async {
    if (!m3u8Url.startsWith('http')) {
      throw const HlsException('播放列表地址不对（不是 http 链接）');
    }

    final workDir = await Directory.systemTemp.createTemp('hls_');
    final tsPath = '${workDir.path}/joined.ts';
    final mp4Path = '${workDir.path}/remuxed.mp4';

    try {
      // ---- 1) 解析播放列表（可能要先跟一层子流）----
      var playlist = await _loadPlaylist(m3u8Url, referer);
      var url = m3u8Url;
      for (var depth = 0; depth < _maxDepth && playlist.isMaster; depth++) {
        final sub = pickBestVariant(playlist);
        if (sub == null) throw const HlsException('这是主播放列表，但里面没有子流');
        onProgress?.call(0.02, '选择清晰度…');
        url = sub;
        playlist = await _loadPlaylist(url, referer);
      }

      if (playlist.isMaster) {
        throw const HlsException('播放列表嵌套太深，放弃（可能是直播流）');
      }
      if (!playlist.downloadable) {
        throw HlsException(playlist.unsupportedReason);
      }
      if (playlist.segments.length > _maxSegments) {
        throw HlsException(
            '这条流有 ${playlist.segments.length} 个分片，超过上限 $_maxSegments。'
            '可能是直播或超长视频，暂不支持。');
      }

      // ---- 2) 顺序下载 + 追加写 ----
      final total = playlist.segments.length;
      final sink = File(tsPath).openWrite();
      var downloaded = 0;
      try {
        for (var i = 0; i < total; i++) {
          final bytes = await _fetchSegment(playlist.segments[i], referer);
          if (bytes.isEmpty) {
            throw HlsException('第 ${i + 1}/$total 个分片是空的，这条流可能已过期');
          }
          sink.add(bytes);
          downloaded++;
          onProgress?.call(
            0.05 + 0.75 * downloaded / total,
            '下载分片 $downloaded/$total',
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      final tsSize = await File(tsPath).length();
      if (tsSize < 100 * 1024) {
        throw HlsException('拼接出来的文件只有 ${tsSize ~/ 1024}KB，不像有效视频');
      }

      // ---- 3) 原生转封装 ----
      onProgress?.call(0.82, '转封装为 MP4…');
      final Map<dynamic, dynamic>? r;
      try {
        r = await _ch.invokeMethod<Map<dynamic, dynamic>>('remuxTs', {
          'tsPath': tsPath,
          'outPath': mp4Path,
        });
      } on PlatformException catch (e) {
        throw HlsException('转封装失败：${e.message ?? e.code}');
      } on MissingPluginException {
        throw const HlsException('这台设备不支持 HLS 转封装（缺少原生模块）');
      }
      if (r == null) throw const HlsException('转封装没有返回结果');

      final bytes = (r['bytes'] as num?)?.toInt() ?? 0;
      final durationMs = (r['durationMs'] as num?)?.toInt() ?? 0;
      if (bytes <= 0) throw const HlsException('转出来的 MP4 是空的');

      onProgress?.call(1.0, '完成');
      if (kDebugMode) {
        debugPrint('[HLS] 完成：$total 片 / TS ${tsSize ~/ 1024}KB → '
            'MP4 ${bytes ~/ 1024}KB / ${durationMs}ms');
      }
      return HlsFetchResult(
        mp4Path: mp4Path,
        durationMs: durationMs,
        segments: total,
        bytes: bytes,
      );
    } catch (e) {
      // 失败时清掉半成品（成功时 mp4 还要被上层取走，这里不动）
      try {
        if (await File(tsPath).exists()) await File(tsPath).delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// 下载并解析一条播放列表
  static Future<HlsPlaylist> _loadPlaylist(String url, String referer) async {
    final String text;
    try {
      final r = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {if (referer.isNotEmpty) 'Referer': referer},
        ),
      );
      text = r.data ?? '';
    } on DioException catch (e) {
      throw HlsException('播放列表下载失败：${_dioReason(e)}');
    }
    if (text.trim().isEmpty) {
      throw const HlsException('播放列表是空的（链接可能已过期）');
    }
    final p = parseHlsPlaylist(text, url);
    if (p == null) {
      throw const HlsException('返回的内容不是 m3u8 播放列表');
    }
    return p;
  }

  /// 下载一个分片（失败重试一次 —— 分片多了总会碰到一两个抽风的）
  static Future<List<int>> _fetchSegment(String url, String referer) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await _dio.get<List<int>>(
          url,
          options: Options(headers: {if (referer.isNotEmpty) 'Referer': referer}),
        );
        final data = r.data;
        if (data != null && data.isNotEmpty) return data;
      } on DioException catch (e) {
        lastErr = e;
        if (kDebugMode) debugPrint('[HLS] 分片失败(${attempt + 1}/2)：${_dioReason(e)}');
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw HlsException('分片下载失败：${lastErr == null ? '空响应' : _dioReason(lastErr)}');
  }

  static String _dioReason(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code != null) return 'HTTP $code';
      return '${e.type}';
    }
    return e.toString();
  }
}
