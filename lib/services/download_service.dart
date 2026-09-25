import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// 一次下载的结果
class DownloadOutcome {
  final bool saved;
  final bool usedDirect;
  final String message;
  const DownloadOutcome({required this.saved, this.usedDirect = false, this.message = ''});
}

/// 媒体下载与保存
///
/// 两条路径：
///
/// 1. **走服务器代理**（默认，稳）
///    后端 `/media` 会带上正确的 Referer 转发，并做了 HMAC 签名。
///
/// 2. **直连平台 CDN**（可选，省服务器流量）
///    APP 与小程序最大的不同：**原生可以自由设置请求头**。
///    所以能自己带 Referer 去平台 CDN 取流，服务器只出解析那点流量。
///
///    两个必须注意的点：
///      · Referer 必须对，否则 CDN 直接 403（实测 B站不带 Referer 403、带上 200）
///      · **UA 必须是桌面 Chrome**。交接文档记录得很清楚：
///        B站 CDN 对 Android Chrome 的 UA 返回 403，对桌面 Chrome / iPhone Safari 返回 200。
///        这曾经被随机 UA 池伪装成「偶发网络抖动」，极难定位 —— 别在这里再踩一次。
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  /// 桌面 Chrome UA —— 与后端 `utils.DESKTOP_UA` 的取向一致
  static const desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static const desktopUaSafari =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Safari/605.1.15';

  /// 从后端签名的代理地址里拆出「原始直链 + Referer + 文件名」。
  ///
  /// 契约来自 `src/media.js`：GET /media?u=&e=&s=&r=&name=&dl=
  ///   u = 目标直链（base64url）
  ///   r = 平台 Referer（base64url，参与签名）
  /// 这两个参数是公开的查询参数，客户端解出来用于直连是合法的。
  static MediaTarget? parseProxyUrl(String proxyUrl) {
    final uri = Uri.tryParse(proxyUrl);
    if (uri == null) return null;
    final u = uri.queryParameters['u'];
    if (u == null || u.isEmpty) return null;

    String? decode(String? v) {
      if (v == null || v.isEmpty) return null;
      try {
        var s = v.replaceAll('-', '+').replaceAll('_', '/');
        while (s.length % 4 != 0) {
          s += '=';
        }
        return utf8.decode(base64.decode(s));
      } catch (_) {
        return null;
      }
    }

    final raw = decode(u);
    if (raw == null || !raw.startsWith('http')) return null;

    return MediaTarget(
      rawUrl: raw,
      referer: decode(uri.queryParameters['r']) ?? '',
      fileName: uri.queryParameters['name'] ?? '',
      proxyUrl: proxyUrl,
    );
  }

  /// 下载并保存到相册
  ///
  /// [proxyUrl] 媒体地址。两种形态都支持：
  ///   · 服务器模式：后端给的带签名 `/media` 代理地址
  ///   · 本地模式：平台原始直链（此时必须传 [referer]）
  /// [referer] 本地模式必填 —— 各平台 CDN 的 Referer 防盗链
  /// [preferDirect] 服务器模式下是否优先直连平台 CDN
  /// [album] 相册名
  /// [onProgress] 0.0 ~ 1.0
  Future<DownloadOutcome> fetchAndSave({
    required String proxyUrl,
    required bool isVideo,
    String referer = '',
    bool preferDirect = false,
    String album = '小鲸鱼',
    String? fileHint,
    void Function(double progress)? onProgress,
  }) async {
    if (proxyUrl.isEmpty) {
      return const DownloadOutcome(saved: false, message: '下载地址为空');
    }

    final target = parseProxyUrl(proxyUrl);
    var usedDirect = false;
    File? tmp;

    if (target == null) {
      // ---- 路径 0：本地解析模式 ----
      // 传进来的**就是平台原始直链**（不是 /media 代理地址），
      // 所以必须用调用方给的 Referer —— 各平台 CDN 都有防盗链，
      // 不带 Referer 会直接 403。
      try {
        tmp = await _download(proxyUrl, referer, fileHint, '', isVideo, onProgress);
      } catch (e) {
        return DownloadOutcome(saved: false, message: _friendlyError(e));
      }
    } else {
      // ---- 路径 1：直连平台 CDN（服务器模式下可选，省服务器流量）----
      if (preferDirect && target.rawUrl.startsWith('https://')) {
        try {
          tmp = await _download(target.rawUrl, target.referer, fileHint,
              target.fileName, isVideo, onProgress);
          usedDirect = true;
        } catch (_) {
          // 直连失败（防盗链、过期、CDN 变动…）→ 静默回退到代理，不让用户感知
          tmp = null;
        }
      }

      // ---- 路径 2：走服务器代理 ----
      if (tmp == null) {
        try {
          tmp = await _download(proxyUrl, '', fileHint, target.fileName, isVideo, onProgress);
        } catch (e) {
          return DownloadOutcome(saved: false, message: _friendlyError(e));
        }
      }
    }

    // ---- 存相册 ----
    try {
      if (isVideo) {
        await Gal.putVideo(tmp.path, album: album);
      } else {
        await Gal.putImage(tmp.path, album: album);
      }
      return DownloadOutcome(saved: true, usedDirect: usedDirect);
    } on GalException catch (e) {
      return DownloadOutcome(
        saved: false,
        usedDirect: usedDirect,
        message: _galMessage(e),
      );
    } catch (e) {
      return DownloadOutcome(saved: false, usedDirect: usedDirect, message: '保存失败：$e');
    } finally {
      // 相册已经拿到副本，临时文件立刻清掉，避免占用户存储
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<File> _download(
    String url,
    String referer,
    String? fileHint,
    String nameFromServer,
    bool isVideo,
    void Function(double)? onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(
      nameFromServer.isNotEmpty ? nameFromServer : (fileHint ?? 'flashsave'),
    );
    // 先下到一个中性名字的临时文件：**扩展名要等拿到响应头才能定**
    // （无水印直链本身没有后缀）
    final tmp = File('${dir.path}/$safeName.part');
    if (await tmp.exists()) await tmp.delete();

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      // 大文件要留足时间：小红书的无水印原图单张 1–2MB、
      // 原始视频能到 50MB，慢网下几分钟是常态
      receiveTimeout: const Duration(minutes: 10),
      headers: {
        'User-Agent': desktopUa,
        if (referer.isNotEmpty) 'Referer': referer,
        'Accept': '*/*',
      },
      followRedirects: true,
      validateStatus: (s) => s != null && s < 400,
    ));

    String contentType = '';

    // 最多试两次。大文件断流很常见，第二次会**从断点续传**，
    // 不必把已经下好的几十兆白扔掉。
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final have = await tmp.exists() ? await tmp.length() : 0;
        final resp = await dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              if (have > 0) 'Range': 'bytes=$have-',
            },
          ),
        );

        final body = resp.data;
        if (body == null) throw Exception('服务器没有返回内容');
        contentType = resp.headers.value('content-type') ?? contentType;

        final lenHeader =
            int.tryParse(resp.headers.value('content-length') ?? '') ?? 0;
        // 只有 206 才是续传，200 说明服务端忽略了 Range、从头发的
        final resuming = have > 0 && resp.statusCode == 206;
        final base = resuming ? have : 0;
        final total = base + lenHeader;

        final sink = tmp.openWrite(mode: resuming ? FileMode.append : FileMode.write);
        var got = base;
        try {
          await for (final chunk in body.stream) {
            sink.add(chunk);
            got += chunk.length;
            if (total > 0 && onProgress != null) {
              onProgress((got / total).clamp(0.0, 1.0));
            }
          }
        } finally {
          await sink.close();
        }

        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
        if (attempt == 0) {
          // 留一下再试，避开瞬时的网络抖动
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }

    if (lastErr != null) throw lastErr;

    final len = await tmp.length();
    if (len <= 0) throw Exception('下载到的文件是空的');

    // 后缀三级判断，优先级从高到低：
    //   1. 文件头 —— 最可靠（服务器会说谎，比如把 QuickTime 报成 video/mp4）
    //   2. 响应头的 content-type
    //   3. URL / 调用方给的类型
    final ext = (await _extFromMagic(tmp)) ??
        _extFromContentType(contentType) ??
        _guessExt(url, nameFromServer, isVideo);
    final finalPath = '${dir.path}/$safeName$ext';
    final out = File(finalPath);
    if (await out.exists()) await out.delete();
    return tmp.rename(finalPath);
  }

  /// 推断文件扩展名。
  ///
  /// 【为什么不能「找不到就返回 .mp4」】
  /// 各平台的**无水印直链往往是没有扩展名的**，例如小红书的
  ///   `https://sns-img-hw.xhscdn.com/notes_pre_post/1040g3k831tce…`
  /// 以前这里兜底返回 `.mp4`，于是**图片被存成了 .mp4 文件** ——
  /// 媒体库不认这个类型，表现就是「提示保存成功，但相册里找不到」。
  /// （带水印的老地址末尾有 `.jpg`，所以这个问题一直没暴露。）
  ///
  /// 现在两级判断：
  ///   1. 先看 URL / 服务端给的文件名里有没有明确后缀
  ///   2. 没有就**按调用方告诉我们的类型**兜底（图片 → .jpg，视频 → .mp4）
  /// 另外下载完成后还会用响应头的 content-type 再校正一次。
  String _guessExt(String url, String nameFromServer, bool isVideo) {
    for (final s in [nameFromServer, url]) {
      final m = RegExp(r'\.(mp4|mov|m4v|webm|jpg|jpeg|png|webp|gif|heic)(\?|$)',
              caseSensitive: false)
          .firstMatch(s);
      if (m != null) return '.${m.group(1)!.toLowerCase()}';
    }
    return isVideo ? '.mp4' : '.jpg';
  }

  /// 从**文件头**推断真实容器格式 —— 比信服务器靠谱。
  ///
  /// 【为什么必须看文件头】小红书视频的原始对象返回的
  /// `Content-Type: video/mp4`，但文件开头是
  ///   `00 00 00 14 66 74 79 70 71 74 20 20` = `ftypqt  `
  /// —— brand 是 **`qt  `，也就是 QuickTime（.mov）**，不是 MP4。
  ///
  /// 服务器撒谎的后果很具体：文件被存成 `.mp4`，而 Android 媒体库是按
  /// 扩展名挑解析器的，用 MP4 解析器去解 QuickTime 会拿不到元数据，
  /// 于是**不入库 → 相册里根本看不到**（文件管理器倒是能看到，
  /// 所以现象是「保存了但相册没有」）。
  Future<String?> _extFromMagic(File f) async {
    try {
      final raf = await f.open();
      final head = await raf.read(16);
      await raf.close();
      return extFromMagicBytes(head);
    } catch (_) {
      return null;
    }
  }

  /// 纯函数版（可单测，不依赖文件系统）
  @visibleForTesting
  static String? extFromMagicBytes(List<int> head) {
    if (head.length < 12) return null;

    String ascii(int start, int len) =>
        String.fromCharCodes(head.sublist(start, start + len));

    // ISO BMFF 系列（mp4 / mov / m4v）都以 ftyp box 开头
    if (ascii(4, 4) == 'ftyp') {
      final brand = ascii(8, 4);
      if (brand.startsWith('qt')) return '.mov';
      if (brand.startsWith('M4V')) return '.m4v';
      return '.mp4';
    }
    if (head[0] == 0x1A && head[1] == 0x45 && head[2] == 0xDF && head[3] == 0xA3) {
      return '.webm'; // 也覆盖 mkv
    }
    if (head[0] == 0xFF && head[1] == 0xD8) return '.jpg';
    if (head[0] == 0x89 && ascii(1, 3) == 'PNG') return '.png';
    if (ascii(0, 4) == 'RIFF' && ascii(8, 4) == 'WEBP') return '.webp';
    if (ascii(0, 3) == 'GIF') return '.gif';
    return null;
  }

  /// 从响应头的 content-type 推断后缀（拿不到文件头时的次选）
  String? _extFromContentType(String ct) {
    final c = ct.toLowerCase();
    if (c.contains('video/mp4')) return '.mp4';
    if (c.contains('video/webm')) return '.webm';
    if (c.contains('video/quicktime')) return '.mov';
    if (c.contains('image/jpeg')) return '.jpg';
    if (c.contains('image/png')) return '.png';
    if (c.contains('image/webp')) return '.webp';
    if (c.contains('image/gif')) return '.gif';
    if (c.contains('image/heic')) return '.heic';
    return null;
  }

  String _safeFileName(String raw) {
    var s = raw.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
    if (s.length > 60) s = s.substring(0, 60);
    if (s.toLowerCase().endsWith('.mp4') || s.toLowerCase().endsWith('.jpg')) {
      s = s.substring(0, s.lastIndexOf('.'));
    }
    return s.isEmpty ? 'flashsave_${DateTime.now().millisecondsSinceEpoch}' : s;
  }

  String _friendlyError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 403) return '下载被拒绝（403）。链接可能过期了，重新解析一次再试';
      if (code == 404) return '媒体文件不存在（404）';
      if (code != null) return '下载失败（HTTP $code）';
      return '下载失败，检查下网络';
    }
    return '下载失败：$e';
  }

  String _galMessage(GalException e) {
    switch (e.type) {
      case GalExceptionType.accessDenied:
        return '没有相册写入权限，去系统设置里开启后重试';
      case GalExceptionType.notEnoughSpace:
        return '手机存储空间不足';
      case GalExceptionType.notSupportedFormat:
        return '这个文件格式相册不支持';
      case GalExceptionType.unexpected:
        return '保存到相册失败，请重试';
    }
  }
}

/// 从代理地址里拆出来的原始媒体信息
class MediaTarget {
  final String rawUrl;
  final String referer;
  final String fileName;
  final String proxyUrl;

  const MediaTarget({
    required this.rawUrl,
    required this.referer,
    required this.fileName,
    required this.proxyUrl,
  });
}
