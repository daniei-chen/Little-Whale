import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'types.dart';

/// 哔哩哔哩 · 本地解析（纯 HTTP，不需要服务器）
///
/// B站是这几家里最「正派」的：有**公开 API**，不需要浏览器、不需要登录，
/// 唯一的门槛是 2023 年起 Web 接口要求 `w_rid` 签名（wbi）。
/// 这里把服务端 `src/adapters/bilibili.js` 的签名实现原样搬到 Dart。
///
/// 未登录最高 720P —— B站对未登录账号就是这么限制的，不是我们拿不到。
class BilibiliLocalPlatform extends LocalPlatform {
  @override
  String get key => 'bilibili';

  @override
  String get name => '哔哩哔哩';

  @override
  List<String> get hosts => const ['bilibili.com', 'b23.tv', 'acg.tv'];

  /// B站直链有 Referer 校验，下载必须带
  @override
  String get referer => 'https://www.bilibili.com';

  static const _apiHeaders = {
    'Referer': 'https://www.bilibili.com',
    'Origin': 'https://www.bilibili.com',
    'Accept': 'application/json, text/plain, */*',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  };

  static final _bvidRe = RegExp(r'(BV[0-9A-Za-z]{10})');

  /// 专栏：`bilibili.com/read/cv27142128`
  static final _cvRe = RegExp(r'/read/cv(\d+)', caseSensitive: false);

  /// 图文动态：`bilibili.com/opus/123456` 或 `t.bilibili.com/123456`
  static final _opusRe = RegExp(r'(?:/opus/|t\.bilibili\.com/)(\d{6,})');
  static final _aidRe = RegExp(r'/video/av(\d+)', caseSensitive: false);

  /// wbi 重排表。官方就是拿这张表打乱 img_key + sub_key 取前 32 位。
  static const _mixinKeyEncTab = <int>[
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  static const _qualityMap = <int, String>{
    127: '8K', 126: '杜比视界', 125: 'HDR', 120: '4K',
    116: '1080P60', 112: '1080P+', 80: '1080P',
    74: '720P60', 64: '720P', 32: '480P', 16: '360P', 6: '240P',
  };

  /// wbi 密钥缓存。B站每 30 分钟轮换一次，缓存起来省一次请求。
  static String _wbiKey = '';
  static int _wbiExpireAt = 0;

  Dio get _dio => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        followRedirects: true,
        maxRedirects: 6,
        validateStatus: (s) => s != null && s < 500,
        headers: _apiHeaders,
      ));

  /* ------------------------------------------------------------------ */

  @override
  Future<LocalResult> parse(String url) async {
    var finalUrl = url;
    if (url.contains('b23.tv') || url.contains('acg.tv')) {
      finalUrl = await _resolveShort(url);
    }

    // ---- 先判断是哪一种内容 ----
    // B站现在有三种链接形态，接口完全不同：
    //   /video/BV...      视频
    //   /read/cv123       专栏文章
    //   /opus/123         图文动态
    // 短链解析后也要再判一次，因为 b23.tv 后面可能是任意一种。
    final cv = _first(finalUrl, _cvRe) ?? _first(url, _cvRe);
    if (cv != null) return _parseArticle(cv, url);

    final opus = _first(finalUrl, _opusRe) ?? _first(url, _opusRe);
    if (opus != null) return _parseOpus(opus, url);

    final bvid = _first(finalUrl, _bvidRe) ?? _first(url, _bvidRe);
    final aid = _first(finalUrl, _aidRe) ?? _first(url, _aidRe);
    if (bvid == null && aid == null) {
      throw const LocalParseError(
          '没在链接里找到 B站的内容。支持视频（BV 号）、专栏（cv 号）、图文动态（opus）。');
    }

    return _parseVideo(bvid, aid, url);
  }

  /// 视频
  Future<LocalResult> _parseVideo(String? bvid, String? aid, String url) async {
    final info = await _view(bvid ?? 'av$aid');
    final v = info;
    final cid = (v['cid'] as num?)?.toInt();
    if (cid == null) {
      throw const LocalParseError('B站没返回视频信息，可能视频已被删除。');
    }

    final play = await _playUrl((v['bvid'] ?? bvid ?? '').toString(), cid);
    if (play == null) {
      throw const LocalParseError(
          '拿到了视频信息，但取播放地址被拒。通常是清晰度权限问题（未登录只能拿 720P 及以下）。');
    }

    // fnval=1 返回 durl（MP4 直链）；分段视频会有多段，这里取第一段
    final durl = play['durl'];
    if (durl is! List || durl.isEmpty) {
      throw const LocalParseError('没拿到可播放的视频地址。');
    }
    final first = durl.first;
    if (first is! Map || first['url'] == null) {
      throw const LocalParseError('没拿到可播放的视频地址。');
    }

    final quality = (play['quality'] as num?)?.toInt();
    final owner = v['owner'];
    final dim = v['dimension'];

    return LocalResult(
      platform: key,
      platformName: name,
      type: 'video',
      title: (v['title'] ?? '').toString(),
      author: (owner is Map ? (owner['name'] ?? '') : '').toString(),
      cover: (v['pic'] ?? '').toString(),
      durationSec: (v['duration'] as num?)?.toInt() ?? 0,
      resolution: _qualityMap[quality] ??
          (dim is Map ? '${dim['width']}x${dim['height']}' : ''),
      size: _formatSize((first['size'] as num?)?.toInt() ?? 0),
      publishTime: _formatDate(v['pubdate']),
      videoUrl: first['url'].toString(),
      referer: referer,
      sourceUrl: url,
    );
  }

  /* ------------------------------------------------------------------ */
  /* 专栏文章                                                             */
  /* ------------------------------------------------------------------ */

  /// 专栏（`bilibili.com/read/cv{id}`）。
  ///
  /// 用 `x/article/view` 接口拿 `content`（HTML），再从中抠 `<img src>`。
  /// 【为什么不用页面 SSR】页面上的 `__INITIAL_STATE__.detail` 结构已经改成
  /// opus 那套（`modules` 是按序号排列的段落对象），解析起来比这个 HTML
  /// 麻烦得多，而且那个结构还在变。接口返回的 HTML 反而稳定。
  ///
  /// 图片地址形如 `//i0.hdslb.com/bfs/article/{hash}.jpg` —— **没有 `@` 后缀**，
  /// 那就是原图；带 `@` 的（如 `@1080w.webp`）是处理过的展示版。
  Future<LocalResult> _parseArticle(String cvId, String url) async {
    // 【为什么要重试】B站对专栏接口有频率风控，短时间内多打几次就返回
    // `-509 请求过于频繁`。这不是「内容有问题」，等几秒就好 ——
    // 用户连续解析几篇时很容易撞上，直接报错体验很差。
    Map<String, dynamic> body = const {};
    for (var attempt = 0; attempt < 4; attempt++) {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://api.bilibili.com/x/article/view',
        queryParameters: {'id': cvId},
      );
      body = r.data ?? const {};
      final code = (body['code'] as num?)?.toInt() ?? -1;
      if (code == 0) break;

      final msg = (body['message'] ?? '').toString();
      final busy = msg.contains('频繁') || code == -509 || code == -412;
      if (busy && attempt < 2) {
        await Future.delayed(Duration(milliseconds: 1500 * (attempt + 1)));
        continue;
      }

      if (busy) {
        throw const LocalParseError('B站暂时限制了访问频率，等十几秒再试一次。');
      }
      throw LocalParseError('B站没返回这篇专栏（$msg）。可能已被删除或仅粉丝可见。');
    }

    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw const LocalParseError('B站暂时限制了访问频率，等十几秒再试一次。');
    }

    final d = body['data'];
    if (d is! Map) throw const LocalParseError('B站专栏数据格式变了。');

    final content = (d['content'] ?? '').toString();
    final images = <LocalImage>[];

    // 从 HTML 里抠所有图片
    for (final m in RegExp(r'<img[^>]+src="([^"]+)"').allMatches(content)) {
      final raw = m.group(1) ?? '';
      final u = _cleanImageUrl(raw);
      if (u.isEmpty) continue;
      if (images.any((e) => e.url == u)) continue;
      images.add(LocalImage(url: u));
    }

    // 封面兜底：正文里一张图都没有时用 banner
    if (images.isEmpty) {
      final banner = _cleanImageUrl((d['banner_url'] ?? '').toString());
      if (banner.isNotEmpty) images.add(LocalImage(url: banner));
    }

    if (images.isEmpty) {
      throw const LocalParseError('这篇专栏里没有可下载的图片。');
    }

    return LocalResult(
      platform: key,
      platformName: name,
      type: 'images',
      title: (d['title'] ?? '').toString(),
      author: (d['author_name'] ?? '').toString(),
      cover: images.first.url,
      publishTime: _formatDate(d['publish_time'] ?? d['ctime']),
      referer: referer,
      images: images,
      sourceUrl: url,
    );
  }

  /* ------------------------------------------------------------------ */
  /* 图文动态（opus）                                                     */
  /* ------------------------------------------------------------------ */

  /// 图文动态（`bilibili.com/opus/{id}`）。
  ///
  /// 【必须 wbi 签名】`x/polymer/web-dynamic/v1/detail` 不带签名直接返回 -352。
  /// 签名逻辑已经复用在视频那边（`_signedQuery`），这里直接用。
  ///
  /// 图片在 `data.item.modules.module_dynamic.major.draw.items[].src`，
  /// 新版也有 `major.opus.pics[].url` —— 两种都兼容。
  Future<LocalResult> _parseOpus(String dynId, String url) async {
    final q = await _signedQuery({'id': dynId, 'timezone_offset': '-480'});
    final r = await _dio.get<Map<String, dynamic>>(
      'https://api.bilibili.com/x/polymer/web-dynamic/v1/detail?$q',
    );
    final body = r.data ?? const {};
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw LocalParseError(
          'B站没返回这条动态（${body['message'] ?? code}）。可能已被删除，或需要登录。');
    }

    final data = body['data'];
    final item = (data is Map ? data['item'] : null);
    if (item is! Map) throw const LocalParseError('B站动态数据格式变了。');

    final images = <LocalImage>[];
    final mods = item['modules'];
    final md = (mods is Map ? mods['module_dynamic'] : null);
    final major = (md is Map ? md['major'] : null);

    if (major is Map) {
      // 老版：draw.items[].src
      final draw = major['draw'];
      final items = (draw is Map ? draw['items'] : null);
      if (items is List) {
        for (final it in items) {
          if (it is! Map) continue;
          final u = _cleanImageUrl((it['src'] ?? '').toString());
          if (u.isEmpty) continue;
          images.add(LocalImage(
            url: u,
            width: (it['width'] as num?)?.toInt() ?? 0,
            height: (it['height'] as num?)?.toInt() ?? 0,
          ));
        }
      }
      // 新版：opus.pics[].url
      final opus = major['opus'];
      final pics = (opus is Map ? opus['pics'] : null);
      if (images.isEmpty && pics is List) {
        for (final it in pics) {
          if (it is! Map) continue;
          final u = _cleanImageUrl((it['url'] ?? '').toString());
          if (u.isEmpty) continue;
          images.add(LocalImage(
            url: u,
            width: (it['width'] as num?)?.toInt() ?? 0,
            height: (it['height'] as num?)?.toInt() ?? 0,
          ));
        }
      }
    }

    if (images.isEmpty) {
      throw const LocalParseError('这条动态里没有可下载的图片。');
    }

    // 作者：新版在 modules.module_author，老版在 item.modules.module_author 里也一样
    var author = '';
    final ma = (mods is Map ? mods['module_author'] : null);
    if (ma is Map) author = (ma['name'] ?? '').toString();
    if (author.isEmpty) {
      final ba = item['basic'];
      if (ba is Map && ba['author'] is Map) {
        author = ((ba['author'] as Map)['name'] ?? '').toString();
      }
    }

    final title = _opusTitle(major ?? const {}, md ?? const {}, item);

    return LocalResult(
      platform: key,
      platformName: name,
      type: 'images',
      // 尽量别退到「B站动态」—— 用户看到这种标题分不清是哪条
      title: title.isNotEmpty ? title : 'B站动态',
      author: author,
      cover: images.first.url,
      referer: referer,
      images: images,
      sourceUrl: url,
    );
  }

  /// B站图床地址清洗：补协议、去掉 `@` 之后的处理参数（那才是原图）。
  String _cleanImageUrl(String raw) {
    if (raw.isEmpty) return '';
    var u = raw.trim();
    if (u.startsWith('//')) u = 'https:$u';
    if (!u.startsWith('http')) return '';
    // 接口有时候给 http（new_dyn 那一批就是）。必须升到 https ——
    // 否则 Android 会拦明文请求，表现是「解析出来了但图下不来」。
    if (u.startsWith('http://')) u = 'https://${u.substring(7)}';
    // `xxx.jpg@1080w_1c.webp` → `xxx.jpg`（去掉 @ 后缀即原图）
    final at = u.indexOf('@');
    if (at > 0) u = u.substring(0, at);
    return u;
  }

  /// 从动态数据里取标题。
  ///
  /// 新版 opus 把正文放在 `major.opus.title` / `major.opus.summary.text`，
  /// 老版放在 `module_dynamic.desc`（可能是字符串，也可能是 `{text: ...}`）。
  /// 都不给才退回通用标题 —— 用户看到「B站动态」是分不清哪条的。
  String _opusTitle(Map<dynamic, dynamic> major, Map<dynamic, dynamic> md, Map item) {
    String pick(dynamic v) {
      if (v is String) return v.trim();
      if (v is Map) return (v['text'] ?? '').toString().trim();
      return '';
    }

    final opus = major['opus'];
    if (opus is Map) {
      final t = pick(opus['title']);
      if (t.isNotEmpty) return t;
      final s = pick(opus['summary']);
      if (s.isNotEmpty) return s;
    }

    final desc = pick(md['desc']);
    if (desc.isNotEmpty) return desc;

    final basic = item['basic'];
    if (basic is Map) {
      final t = pick(basic['title']);
      if (t.isNotEmpty) return t;
      final s = pick(basic['summary']);
      if (s.isNotEmpty) return s;
    }

    // 还有的放在 modules[*].module_content.paragraphs[].text.nodes[].text
    final mods = item['modules'];
    if (mods is Map) {
      for (final k in mods.keys) {
        final m = mods[k];
        if (m is! Map) continue;
        final mc = m['module_content'] ?? m['module_dynamic'];
        if (mc is Map) {
          final t = pick(mc['desc']);
          if (t.isNotEmpty) return t;
          final ps = mc['paragraphs'];
          if (ps is List) {
            final buf = StringBuffer();
            for (final p in ps) {
              final txt = p is Map ? (p['text'] ?? '') : '';
              final nodes = (txt is Map ? txt['nodes'] : null);
              if (nodes is List) {
                for (final n in nodes) {
                  if (n is Map) buf.write((n['text'] ?? '').toString());
                }
              }
            }
            final s = buf.toString().trim();
            if (s.isNotEmpty) return s.length > 60 ? '${s.substring(0, 60)}…' : s;
          }
        }
      }
    }
    return '';
  }

  /* ------------------------------------------------------------------ */
  /* 接口                                                                */
  /* ------------------------------------------------------------------ */

  Future<String> _resolveShort(String url) async {
    try {
      final r = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain));
      final real = r.realUri.toString();
      if (_bvidRe.hasMatch(real)) return real;
    } catch (_) {}
    return url;
  }

  Future<Map<String, dynamic>> _view(String id) async {
    final q = id.startsWith('av') ? 'aid=${id.substring(2)}' : 'bvid=$id';
    try {
      final r = await _dio
          .get<Map<String, dynamic>>('https://api.bilibili.com/x/web-interface/view?$q');
      final body = r.data ?? const {};
      final code = (body['code'] as num?)?.toInt() ?? -1;
      if (code != 0) {
        var msg = (body['message'] ?? '未知错误').toString();
        if (code == -404) msg = '视频不存在或已被删除';
        if (code == -403) msg = '访问被拒绝，可能需要登录';
        throw LocalParseError('B站返回：$msg');
      }
      final d = body['data'];
      if (d is! Map) throw const LocalParseError('B站没返回视频信息。');
      return Map<String, dynamic>.from(d);
    } on LocalParseError {
      rethrow;
    } catch (e) {
      throw LocalParseError('请求 B站失败：$e');
    }
  }

  /// 先试不签名，失败再上 wbi 签名。
  ///
  /// 不能一上来就签名 —— 走签名要额外请求一次 nav 接口拿密钥，多一次往返。
  /// 而 `x/player/playurl`（不带 wbi）对一部分视频仍然放行。
  Future<Map<String, dynamic>?> _playUrl(String bvid, int cid) async {
    final params = <String, dynamic>{
      'bvid': bvid,
      'cid': cid,
      'qn': 80, // 请求 1080P，未登录会被降到实际可给的清晰度
      'fnval': 1, // 1 = 返回 durl（MP4 直链），而不是 dash
      'fourk': 1,
    };

    final attempts = <String>[
      'https://api.bilibili.com/x/player/playurl?${_toQuery(params)}',
      'https://api.bilibili.com/x/player/wbi/playurl?${await _signedQuery(params)}',
    ];

    for (final url in attempts) {
      try {
        final r = await _dio.get<Map<String, dynamic>>(url);
        final body = r.data ?? const {};
        if ((body['code'] as num?)?.toInt() == 0 && body['data'] is Map) {
          return Map<String, dynamic>.from(body['data'] as Map);
        }
      } catch (_) {
        // 换下一种策略
      }
    }
    return null;
  }

  /* ------------------------------------------------------------------ */
  /* wbi 签名                                                            */
  /* ------------------------------------------------------------------ */

  /// 从 nav 接口取 img_key / sub_key，拼起来按重排表打乱取前 32 位。
  Future<String> _wbi() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_wbiKey.isNotEmpty && _wbiExpireAt > now) return _wbiKey;

    try {
      final r = await _dio
          .get<Map<String, dynamic>>('https://api.bilibili.com/x/web-interface/nav');
      final d = r.data?['data'];
      final wbi = (d is Map ? d['wbi_img'] : null);
      if (wbi is! Map) return '';

      final imgUrl = (wbi['img_url'] ?? '').toString();
      final subUrl = (wbi['sub_url'] ?? '').toString();
      if (imgUrl.isEmpty || subUrl.isEmpty) return '';

      String nameOf(String u) {
        final seg = u.substring(u.lastIndexOf('/') + 1);
        return seg.split('.').first;
      }

      _wbiKey = _mixinKey('${nameOf(imgUrl)}${nameOf(subUrl)}');
      _wbiExpireAt = now + 30 * 60 * 1000;
      return _wbiKey;
    } catch (_) {
      return '';
    }
  }

  String _mixinKey(String origin) {
    final buf = StringBuffer();
    for (var i = 0; i < _mixinKeyEncTab.length && i < origin.length; i++) {
      buf.write(origin[_mixinKeyEncTab[i]]);
    }
    final s = buf.toString();
    return s.length > 32 ? s.substring(0, 32) : s;
  }

  Future<String> _signedQuery(Map<String, dynamic> params) async {
    final mixinKey = await _wbi();
    if (mixinKey.isEmpty) return _toQuery(params);

    final all = Map<String, dynamic>.from(params);
    all['wts'] = (DateTime.now().millisecondsSinceEpoch / 1000).round();

    final keys = all.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      // 官方要求过滤这几个字符
      final v = all[k].toString().replaceAll(RegExp(r"[!'()*]"), '');
      parts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(v)}');
    }
    final query = parts.join('&');
    return '$query&w_rid=${_md5('$query$mixinKey')}';
  }

  String _toQuery(Map<String, dynamic> obj) => obj.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
      .join('&');

  String _md5(String s) => md5.convert(utf8.encode(s)).toString();

  /* ------------------------------------------------------------------ */

  String? _first(String url, RegExp re) => re.firstMatch(url)?.group(1);

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatDate(dynamic ts) {
    final n = ts is num ? ts.toInt() : int.tryParse('$ts');
    if (n == null || n <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(n * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
