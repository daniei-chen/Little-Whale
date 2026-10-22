import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一次动态照片合成的结果
class MotionPhotoResult {
  final bool ok;

  /// 合成后整个 .jpg 文件大小（含内嵌视频）
  final int bytes;

  /// 内嵌视频大小 —— 这个值会写进 XMP 的 MicroVideoOffset / Item:Length
  final int videoBytes;

  /// 封面原本不是 JPEG（webp/heic），被重编码过
  final bool coverRecoded;

  final String message;

  const MotionPhotoResult({
    required this.ok,
    this.bytes = 0,
    this.videoBytes = 0,
    this.coverRecoded = false,
    this.message = '',
  });

  double get mb => bytes / 1024 / 1024;
}

/// 把「静态封面 + 短视频」封装成 Android **动态照片（Motion Photo）**。
///
/// 【产出是什么】一个 `.jpg` 文件。相册里显示为一张照片；支持的机型上长按
/// （或点开）会播放内嵌的短视频和原声。不支持的相册就只显示静态封面 ——
/// 不会损坏，只是不动。
///
/// 【为什么需要原生】要在 JPEG 的 APP1 段里塞 XMP、再把 MP4 拼到文件末尾，
/// 纯 Dart 做二进制段操作既慢又容易出错。原生实现见
/// `android/app/src/main/kotlin/cn/flashsave/flashsave/motionphoto/MotionPhotoWriter.kt`。
///
/// 【兼容性真相，别抱不切实际的期望】
/// Android 动态照片有新旧两套并行标准（MicroVideo / MotionPhoto），且各厂商
/// 可能要求自家私有元数据。原生侧已经**同时写入两套字段**以最大化命中率：
///   · 小米 HyperOS 3 起：标准 XMP 即可识别（公开实测）
///   · 更老的 MIUI、其他品牌：可能需要私有字段，可能只显示静态封面
/// 所以这个档位是「最还原」的选项，但也是**最依赖机型**的选项。
class MotionPhotoService {
  MotionPhotoService._();

  static const MethodChannel _ch = MethodChannel('xiaojingyu/media');

  /// 合成动态照片。
  ///
  /// 三个路径都必须是本地文件；[outPath] 必须以 `.jpg` 结尾
  /// （相册是按扩展名归类的，扩展名错了会被当成视频/文件而不是照片）。
  static Future<MotionPhotoResult> make({
    required String coverPath,
    required String videoPath,
    required String outPath,
    int quality = 95,
  }) async {
    if (!Platform.isAndroid) {
      return const MotionPhotoResult(ok: false, message: '当前平台暂不支持动态照片');
    }
    for (final p in [coverPath, videoPath]) {
      if (!await File(p).exists()) {
        return const MotionPhotoResult(ok: false, message: '临时文件不存在');
      }
    }

    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('makeMotionPhoto', {
        'coverPath': coverPath,
        'videoPath': videoPath,
        'outPath': outPath,
        'quality': quality,
      });
      if (r == null) {
        return const MotionPhotoResult(ok: false, message: '合成没有返回结果');
      }
      final out = MotionPhotoResult(
        ok: true,
        bytes: (r['bytes'] as num?)?.toInt() ?? 0,
        videoBytes: (r['videoBytes'] as num?)?.toInt() ?? 0,
        coverRecoded: r['coverRecoded'] == true,
      );
      debugPrint(
        '[MotionPhoto] ok ${out.mb.toStringAsFixed(2)}MB '
        '(video ${(out.videoBytes / 1024).toStringAsFixed(0)}KB'
        '${out.coverRecoded ? ', cover recoded' : ''})',
      );
      return out;
    } on PlatformException catch (e) {
      debugPrint('[MotionPhoto] PlatformException ${e.code}: ${e.message}');
      return MotionPhotoResult(ok: false, message: e.message ?? '合成失败');
    } on MissingPluginException {
      return const MotionPhotoResult(ok: false, message: '原生模块未加载，请重新安装 App');
    } catch (e) {
      debugPrint('[MotionPhoto] error: $e');
      return MotionPhotoResult(ok: false, message: '合成失败：$e');
    }
  }
}
