// 「HLS 播放列表」作为一种可解析对象 —— 让用户能直接粘贴 m3u8 链接。
//
// 【为什么需要这个】
// AcFun 这类站的作品页在 App 的隐藏 WebView 里拿不到 `<video>`：
// Manifest 里 `usesCleartextTraffic=false` + 全量禁止明文（这是安全整改的要求，
// 见 docs/SECURITY.md），而它们的播放器会去请求 http 子资源，被拦之后
// 播放器整个不初始化 —— 实测轮询 30 秒，`document.querySelectorAll('video').length`
// 始终是 0，而在桌面 Chrome 里同一个页面有 1 个 video 且挂着 m3u8。
//
// 既然如此，就把 **m3u8 直链**本身做成一等公民：
// 用户从别处拿到播放列表地址（浏览器 F12、别的工具、朋友给的），粘进来就能存。
// 这条路不依赖页面，也就绕开了明文限制。

import 'package:dio/dio.dart';

import 'types.dart';

class HlsLocalPlatform extends LocalPlatform {
  HlsLocalPlatform();

  @override
  String get key => 'hls';

  @override
  String get name => 'HLS 视频流';

  /// 【必须是空列表】它不是按域名识别的，而是按 `.m3u8` 后缀
  /// （见 LocalRegistry.detect），放在 hosts 里反而会误伤。
  @override
  List<String> get hosts => const [];

  @override
  String get referer => '';

  @override
  Future<LocalResult> parse(String url) async {
    final trimmed = url.trim();
    if (!trimmed.contains('.m3u8')) {
      throw const LocalParseError(
          '这不是 m3u8 播放列表地址。\n\n'
          'HLS 链接通常长这样：https://example.com/video/index.m3u8');
    }
    if (!trimmed.startsWith('http')) {
      throw const LocalParseError('m3u8 地址必须以 http(s):// 开头');
    }

    // 只做一个轻量校验：能不能取到、看起来是不是播放列表。
    // 真正的下载在保存时才做（分片可能上百个，解析阶段不该先下 160MB）。
    final probe = await _peek(trimmed);

    return LocalResult(
      platform: key,
      platformName: name,
      type: 'video',
      title: probe.title,
      author: '',
      videoUrl: trimmed,
      referer: '',
      // referer 取播放列表自己的 origin —— 多数 CDN 的防盗链只比对站点
      cover: '',
      images: const [],
      durationSec: probe.durationSec,
    );
  }

  Future<_Peek> _peek(String url) async {
    try {
      final dio = _dio();
      final r = await dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': '*/*'},
        ),
      );
      final text = r.data ?? '';
      if (!text.trimLeft().startsWith('#EXTM3U')) {
        throw const LocalParseError(
            '这个地址返回的不是 m3u8 播放列表。\n\n'
            '可能链接已过期，或者需要登录/Cookie 才能访问。');
      }
      // 从文件名里猜个标题（播放列表常叫 index.m3u8 / 1080p.m3u8，没什么信息量）
      final path = Uri.tryParse(url)?.pathSegments ?? const <String>[];
      final last = path.isEmpty ? '' : path.last;
      final base = last.replaceAll(RegExp(r'\.m3u8$', caseSensitive: false), '');
      final seconds = _sumExtinf(text);
      return _Peek(
        title: base.isEmpty || base == 'index' || base == 'playlist'
            ? 'HLS 视频'
            : base,
        durationSec: seconds,
      );
    } on LocalParseError {
      rethrow;
    } on DioException catch (e) {
      // 【这里不能用 DioException 的类型名糊弄用户】
      // 手机上真正会碰到的是 4xx/5xx 和超时，说清楚比抛栈有用
      if (e.response?.statusCode != null) {
        throw LocalParseError('播放列表返回 HTTP ${e.response!.statusCode}：'
            '可能链接已过期，或需要登录才能访问。');
      }
      throw LocalParseError('取不到播放列表：${e.type.name}。请检查网络或链接是否有效。');
    } catch (e) {
      throw LocalParseError('取不到播放列表：$e');
    }
  }

  /// 累加 `#EXTINF` 的秒数，用来在界面上显示时长（拿不到就是 0）
  static int _sumExtinf(String text) {
    var total = 0.0;
    for (final m in RegExp(r'#EXTINF:\s*([0-9.]+)').allMatches(text)) {
      total += double.tryParse(m.group(1) ?? '') ?? 0;
    }
    return total.round();
  }

  Dio _dio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (s) => s != null && s < 500,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        },
      ));
}

class _Peek {
  final String title;
  final int durationSec;
  const _Peek({required this.title, required this.durationSec});
}
