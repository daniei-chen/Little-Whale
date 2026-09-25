import 'dart:convert';

import 'package:dio/dio.dart';

import 'engine.dart';
import 'types.dart';

/// 微博 · 本地解析（不需要服务器）
///
/// 【为什么要借 WebView 发请求，而不是直接用 dio】
/// 微博的公开接口对**没有浏览器 Cookie** 的请求一律拒绝：
/// 实测纯 dio 打 `m.weibo.cn/api/container/getIndex` 返回 **432**（空 body），
/// 而在 WebView 里（天然带着访问过 m.weibo.cn 后的 Cookie）同一个接口返回 **200**。
///
/// 【怎么在 WebView 里「同步」拿到 JSON】
/// `runJavaScriptReturningResult` 不会等 Promise，所以不能用 fetch。
/// 用**同步 XHR**（`open(..., false)`）就能在页面里一次性拿到响应并直接返回 ——
/// 既带上了 Cookie，又不需要任何回调桥接。
class WeiboLocalPlatform extends LocalPlatform {
  @override
  String get key => 'weibo';

  @override
  String get name => '微博';

  @override
  List<String> get hosts => const ['weibo.com', 'weibo.cn', 't.cn'];

  @override
  String get referer => 'https://m.weibo.cn/';

  static final _detailId = RegExp(r'/(?:detail|status|statuses)/(\d{10,25})');
  static final _showId = RegExp(r'[?&]id=(\d{10,25})');
  /// weibo.com/{uid}/{bid} 里的 bid 是 base62 编码的中文微博 ID
  static final _bidInPath = RegExp(r'^https?://(?:www\.)?weibo\.com/\d+/([0-9A-Za-z]{8,12})');

  static const _alphabet =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /* ------------------------------------------------------------------ */

  @override
  Future<LocalResult> parse(String url) async {
    final finalUrl = await _resolve(url);
    final id = _extractId(finalUrl) ?? _extractId(url);
    if (id == null) {
      throw const LocalParseError(
          '没在链接里找到微博 ID。请用微博「复制链接」给出的地址。');
    }

    await _warmUp();

    final data = await _show(id);
    if (data == null) {
      throw const LocalParseError('微博没返回这条内容 —— 可能是删除了、仅粉丝可见，或需要登录。');
    }

    return _fromShow(data, url);
  }

  /* ------------------------------------------------------------------ */

  /// 先用页面里的同步 XHR 请求。
  ///
  /// **必须带 `X-Requested-With: XMLHttpRequest`** —— m.weibo.cn 的接口靠它
  /// 区分「页面 AJAX 调用」和「直接访问」，不带的话返回的是 HTML（前端页面），
  /// 不是 JSON，于是解析一直失败却看不出原因。
  static String _syncGet(String url) => '''
(function () {
  try {
    var x = new XMLHttpRequest();
    x.open('GET', ${jsonEncode(url)}, false);
    x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    x.setRequestHeader('Accept', 'application/json, text/plain, */*');
    x.send();
    return x.responseText || '';
  } catch (e) {
    return JSON.stringify({ __error: String(e) });
  }
})()
''';

  /// 打开 m.weibo.cn 拿 Cookie。接口没这个就返回 432。
  Future<void> _warmUp() async {
    try {
      await LocalEngine.instance.evaluate(
        'https://m.weibo.cn/',
        'String(document.title)',
        settle: const Duration(milliseconds: 1800),
      );
    } catch (_) {
      // 拿不到 Cookie 也继续试，接口说不定放行
    }
  }

  /// 把 evalCurrent 的返回值安全地变成 Map。
  ///
  /// 【为什么要兼容两种形态】`_decodeJsResult` 会自动把 JSON 字符串解成
  /// Map/List。所以这里拿到的**可能已经是 Map**，也可能还是字符串
  /// （页面返回了非 JSON 内容时）。
  /// 曾经在这里踩过坑：对着已经是 Map 的返回值又 `toString()` 再 `jsonDecode` ——
  /// Dart 的 Map 打印出来是 `{ok: 1, data: {...}}`，那不是合法 JSON，
  /// 于是明明数据就在眼前却一直报「解析失败」。
  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.isNotEmpty) {
      try {
        final j = jsonDecode(v);
        if (j is Map) return Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> _show(String id) async {
    final raw = await LocalEngine.instance
        .evalCurrent(_syncGet('https://m.weibo.cn/statuses/show?id=$id'));
    final j = _asMap(raw);
    if (j == null) return null;

    // 【注意外层包装】m.weibo.cn 返回的是 `{ok: 1, data: {…真正的微博…}}`，
    // 正文数据在 `data` 里面，不在顶层。一开始在顶层找 `id` 一直找不到。
    final d = j['data'];
    if (d is Map && d['id'] != null) return Map<String, dynamic>.from(d);
    return null;
  }

  /// t.cn 短链还原
  Future<String> _resolve(String url) async {
    if (_extractId(url) != null) return url;
    try {
      final r = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        followRedirects: true,
        maxRedirects: 6,
        validateStatus: (s) => s != null && s < 400,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
        },
      )).get<String>(url, options: Options(responseType: ResponseType.plain));
      return r.realUri.toString();
    } catch (_) {
      return url;
    }
  }

  /// 从链接里取微博 ID。三种常见形态都要认：
  ///   · `m.weibo.cn/detail/{id}`        数字 ID
  ///   · `m.weibo.cn/statuses/show?id={id}`
  ///   · `weibo.com/{uid}/{bid}`         **bid 是 base62 编码的**，必须转回数字
  String? _extractId(String url) {
    final a = _detailId.firstMatch(url)?.group(1);
    if (a != null) return a;
    final b = _showId.firstMatch(url)?.group(1);
    if (b != null) return b;
    final bid = _bidInPath.firstMatch(url)?.group(1);
    if (bid != null) return _bidToMid(bid);
    return null;
  }

  /// base62 → 微博数字 ID。
  ///
  /// 微博把数字 ID 每 7 位一组、从低位开始，拼成一个大整数再做 base62。
  /// 反解：先还原整数，再从低位每 7 位切回来。
  static String? _bidToMid(String bid) {
    var num = BigInt.zero;
    for (var i = 0; i < bid.length; i++) {
      final idx = _alphabet.indexOf(bid[i]);
      if (idx < 0) return null;
      num = num * BigInt.from(62) + BigInt.from(idx);
    }
    final parts = <String>[];
    final div = BigInt.from(10000000);
    while (num > BigInt.zero) {
      final rem = num % div;
      num = num ~/ div;
      parts.insert(0, rem.toString().padLeft(7, '0'));
    }
    // 最高位那一组不补零
    if (parts.isNotEmpty) parts[0] = parts[0].replaceFirst(RegExp(r'^0+'), '');
    return parts.join();
  }

  /* ------------------------------------------------------------------ */
  /* 数据映射                                                            */
  /* ------------------------------------------------------------------ */

  LocalResult _fromShow(Map<String, dynamic> j, String sourceUrl) {
    final images = _images(j);
    final video = _video(j);

    final isVideo = video != null && video.isNotEmpty;
    if (images.isEmpty && !isVideo) {
      throw const LocalParseError('这条微博没有可下载的图片或视频。');
    }

    final user = j['user'];
    final author = user is Map
        ? (user['screen_name'] ?? user['name'] ?? '').toString()
        : '';

    // text 是 HTML，去掉标签当标题
    var title = j['text'] != null
        ? j['text']
            .toString()
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
        : '';
    if (title.length > 60) title = title.substring(0, 60);

    return LocalResult(
      platform: key,
      platformName: name,
      type: isVideo ? 'video' : 'images',
      title: title.isEmpty ? '微博' : title,
      author: author,
      cover: images.isNotEmpty
          ? images.first.url
          : ((j['page_info'] is Map &&
                  (j['page_info'] as Map)['page_pic'] is Map)
              ? (((j['page_info'] as Map)['page_pic'] as Map)['url'] ?? '')
                  .toString()
              : ''),
      publishTime: _formatDate(j['created_at']),
      videoUrl: video ?? '',
      referer: referer,
      images: images,
      sourceUrl: sourceUrl,
    );
  }

  /// 图片：换成**原图**。
  ///
  /// 接口返回的 `large.url` 名字叫 large，实际却是 `/mw2000/` 格式 ——
  /// 那是微博压缩过的版本。实测同一张图：
  ///   `/mw2000/`  1,265,517 字节（压缩）
  ///   `/large/`   2,443,297 字节（原始上传）
  /// 换成 `/large/` 画质明显更好，而且同样没有水印
  /// （`mw2000` 我也下载看过，是干净的，只是画质亏了）。
  List<LocalImage> _images(Map<String, dynamic> j) {
    final pics = j['pics'];
    if (pics is! List) return const [];

    final out = <LocalImage>[];
    for (final p in pics) {
      if (p is! Map) continue;
      final large = p['large'];
      var url = large is Map ? (large['url'] ?? '').toString() : '';
      if (url.isEmpty) url = (p['url'] ?? '').toString();
      if (url.isEmpty) continue;
      out.add(LocalImage(url: _toOriginal(_https(url))));
    }
    return out;
  }

  /// 把微博各种尺寸的地址统一换成 `/large/`（原图）
  String _toOriginal(String url) {
    for (final seg in ['/mw2000/', '/orj1080/', '/bmiddle/', '/thumbnail/', '/small/']) {
      if (url.contains(seg)) return url.replaceFirst(seg, '/large/');
    }
    return url;
  }

  /// 视频地址：从 `page_info.media_info` 里挑清晰度最高的一条。
  String? _video(Map<String, dynamic> j) {
    final pi = j['page_info'];
    if (pi is! Map) return null;
    if (pi['type'] != 'video') return null;

    final mi = pi['media_info'];
    if (mi is! Map) return null;

    for (final k in [
      'mp4_1080p_mp4',
      'mp4_720p_mp4',
      'mp4_hd_url',
      'mp4_sd_url',
      'stream_url',
    ]) {
      final u = (mi[k] ?? '').toString();
      if (u.isNotEmpty) return _https(u);
    }
    return null;
  }

  /// 微博给的是 http，必须转 https
  String _https(String u) {
    if (u.isEmpty) return u;
    return u.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://');
  }

  /// 微博的 created_at 形如 "Thu Sep 25 18:00:00 +0800 2026"
  String _formatDate(dynamic v) {
    final s = (v ?? '').toString();
    if (s.isEmpty) return '';
    final m = RegExp(r'(\d{4})$').firstMatch(s);
    final mon = RegExp(
            r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b')
        .firstMatch(s);
    final day = RegExp(r'\b(\d{1,2})\s+\d{2}:').firstMatch(s);
    if (m == null || mon == null || day == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final mi = months.indexOf(mon.group(1)!) + 1;
    final d = day.group(1)!.padLeft(2, '0');
    return '${m.group(1)}-${mi.toString().padLeft(2, '0')}-$d';
  }
}
