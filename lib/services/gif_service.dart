import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次转换的结果
class GifResult {
  final bool ok;

  /// 实际写入的帧数（少于请求值说明视频比预期短，属正常）
  final int frames;
  final int width;
  final int height;

  /// GIF 文件大小（字节）
  final int bytes;
  final String message;

  const GifResult({
    required this.ok,
    this.frames = 0,
    this.width = 0,
    this.height = 0,
    this.bytes = 0,
    this.message = '',
  });

  double get kb => bytes / 1024;
  double get mb => bytes / 1024 / 1024;
}

/// 动图视频 → GIF。
///
/// 【为什么需要原生代码】
/// 视频解码（MediaMetadataRetriever）和 GIF 编码（NeuQuant 量化 + LZW）
/// 在纯 Dart 里都做不了 / 做得很慢，只能落到原生。原生实现见
/// `android/app/src/main/kotlin/cn/flashsave/flashsave/gif/VideoToGif.kt`。
///
/// 【为什么只支持 Android】
/// 小鲸鱼目前只发布 Android。iOS 侧对应的是 AVAssetImageGenerator + ImageIO，
/// 等项目真上 iOS 再补。非 Android 平台这里直接返回失败，由上层回退到「存视频」。
class GifService {
  GifService._();

  static const MethodChannel _ch = MethodChannel('xiaojingyu/gif');

  /// 目标宽度上限。动图源多为竖屏，400 宽在手机上看够清晰；
  /// 再高 GIF 体积涨得极快（GIF 无帧间压缩）。
  static const int defaultMaxWidth = 400;

  /// 帧率。GIF 不适合高帧率，8 帧/秒配 100ms 帧延迟观感最自然。
  static const int defaultFps = 8;

  /// 帧数上限。24 帧 = 3 秒，再长的动图 GIF 会到 5MB 以上。
  static const int defaultMaxFrames = 24;

  /// 把本地短视频转成 GIF，返回 GIF 路径。失败抛异常。
  ///
  /// [gifPath] 由调用方决定（一般和视频同目录、同基名换扩展名）。
  static Future<GifResult> videoToGif({
    required String videoPath,
    required String gifPath,
    int maxWidth = defaultMaxWidth,
    int fps = defaultFps,
    int maxFrames = defaultMaxFrames,
  }) async {
    if (!Platform.isAndroid) {
      return const GifResult(ok: false, message: '当前平台暂不支持转 GIF');
    }
    final src = File(videoPath);
    if (!await src.exists()) {
      return const GifResult(ok: false, message: '视频文件不存在');
    }

    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('videoToGif', {
        'videoPath': videoPath,
        'gifPath': gifPath,
        'maxWidth': maxWidth,
        'fps': fps,
        'maxFrames': maxFrames,
      });
      if (r == null) {
        return const GifResult(ok: false, message: '转换没有返回结果');
      }
      final out = GifResult(
        ok: true,
        frames: (r['frames'] as num?)?.toInt() ?? 0,
        width: (r['width'] as num?)?.toInt() ?? 0,
        height: (r['height'] as num?)?.toInt() ?? 0,
        bytes: (r['bytes'] as num?)?.toInt() ?? 0,
      );
      debugPrint(
        '[GifService] ok ${out.width}x${out.height} '
        '${out.frames}f ${out.kb.toStringAsFixed(0)}KB',
      );
      return out;
    } on PlatformException catch (e) {
      debugPrint('[GifService] PlatformException ${e.code}: ${e.message}');
      return GifResult(ok: false, message: e.message ?? '转换失败');
    } on MissingPluginException {
      // 只会在「改了 Dart 却没重新编原生」时出现，给个能看懂的提示
      return const GifResult(ok: false, message: '原生模块未加载，请重新安装 App');
    } catch (e) {
      debugPrint('[GifService] error: $e');
      return GifResult(ok: false, message: '转换失败：$e');
    }
  }
}
