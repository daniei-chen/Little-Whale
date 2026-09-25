import 'dart:convert';

import 'package:dio/dio.dart';

import 'types.dart';

/// 小红书 · 本地解析（纯 HTTP，不需要服务器）
///
/// 【为什么不用 WebView】实测踩过：WebView 里带了 xiaohongshu.com 的 Cookie，
/// 未登录状态下小红书会**直接跳登录墙**（页面正文只有「登录后推荐更懂你的笔记」），
/// `__INITIAL_STATE__` 里也没有 `note.noteData`。
/// 而**不带 Cookie 的干净请求反而能拿到数据** —— 服务端
/// `src/adapters/xiaohongshu.js` 就是这么做的。
///
/// 所以这里照服务端的做法：手机自己发 HTTP 请求抓页面 HTML，
/// 再从 HTML 里抠 `window.__INITIAL_STATE__`。全程在手机上完成，不经过任何服务器。
///
/// **关键点**：
///   · 必须带分享链接里的 `xsec_token`，否则拿不到数据
///   · 请求要用**还原后的完整地址**（自带 share_id / track_code 等参数，比手拼的全）
///   · UA 必须是手机浏览器 —— 桌面 UA 拿不到同样的页面
class XiaohongshuLocalPlatform extends LocalPlatform {
  @override
  String get key => 'xhs';

  @override
  String get name => '小红书';

  @override
  List<String> get hosts =>
      const ['xiaohongshu.com', 'xhslink.cn', 'xhslink.com'];

  @override
  String get referer => 'https://www.xiaohongshu.com/';

  /// 与服务端 `src/utils.js` 的 MOBILE_UA 保持一致
  static const _mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

  static final _idInPath =
      RegExp(r'/(?:explore|discovery/item|item)/([0-9a-fA-F]{20,32})');
  static final _tokenRe = RegExp(r'xsec_token=([^&]+)');
  static final _sourceRe = RegExp(r'xsec_source=([^&]+)');

  /* ------------------------------------------------------------------ */

  @override
  Future<LocalResult> parse(String url) async {
    final resolved = _unwrapLoginRedirect(await _resolve(url));
    final noteId = _extract(resolved, _idInPath);
    if (noteId == null) {
      throw const LocalParseError(
          '没在链接里找到小红书笔记号。这条分享链接可能已经过期，重新复制一次试试。');
    }

    final token = _decode(_extract(resolved, _tokenRe));
    final source = _extract(resolved, _sourceRe) ?? 'pc_feed';

    // **必须用还原出来的那个地址（含全部原始分享参数），只把 http 换成 https。**
    //
    // 这里踩过一个坑，值得记下来：我一度觉得那个地址「不干净」——
    // 它带着 app_platform / app_version / share_id / track_code 一长串给 App 用的
    // 参数，于是自作聪明改成自拼 `https://www.xiaohongshu.com/explore/{id}?xsec_token=...`。
    // 结果**恰好把唯一能用的那条路砍掉了**。实测同一台手机：
    //
    //   原始地址（含全部参数）: 138727 字节，noteData ✅，无登录墙
    //   自拼的干净地址        :  36202 字节，登录墙 ❌
    //
    // 原因应该是那些看似冗余的参数（尤其 share_id / track_code / apptime）
    // 正是小红书用来判定「这条笔记来自分享、可以匿名访问」的依据。
    // 所以：**别动这个地址，只把协议升级成 https。**
    var detailUrl = resolved.replaceFirst(RegExp(r'^http://'), 'https://');

    // 兜底：万一还原出来不是小红书域名（极端情况），再退回自拼
    if (!detailUrl.contains('xiaohongshu.com')) {
      detailUrl = 'https://www.xiaohongshu.com/explore/$noteId';
      if (token != null && token.isNotEmpty) {
        detailUrl +=
            '?xsec_token=${Uri.encodeComponent(token)}&xsec_source=$source';
      }
    }

    final html = await _fetchHtml(detailUrl);
    if (html.isEmpty) {
      throw const LocalParseError('小红书页面没取到内容，检查一下网络再试。');
    }

    var state = _extractJsonAfter(html, 'window.__INITIAL_STATE__');
    state ??= _extractJsonAfter(html, '__INITIAL_STATE__');
    if (state == null) {
      throw const LocalParseError('小红书页面结构变了，没能取到笔记数据。');
    }

    final note = _findNote(state, noteId);
    if (note == null) {
      throw const LocalParseError(
          '小红书没返回笔记内容 —— xsec_token 可能已过期。重新复制一次分享链接试试。');
    }

    return await _fromNote(note, noteId, url);
  }

  /* ------------------------------------------------------------------ */
  /* 网络                                                                */
  /* ------------------------------------------------------------------ */

  Dio get _dio => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        followRedirects: true,
        maxRedirects: 6,
        validateStatus: (s) => s != null && s < 400,
        headers: const {
          'User-Agent': _mobileUa,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      ));

  Future<String> _fetchHtml(String url) async {
    try {
      final r = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain));
      return r.data ?? '';
    } catch (e) {
      throw LocalParseError('请求小红书失败：${_friendly(e)}');
    }
  }

  String _friendly(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return '网络超时';
      }
      if (e.type == DioExceptionType.connectionError) return '连不上（检查网络）';
      return e.message ?? '网络错误';
    }
    return '$e';
  }

  /// 小红书图片地址 → **无水印原图**。
  ///
  /// 【为什么必须做这一步】小红书的图片 CDN 地址长这样：
  ///   `http://sns-webpic-qc.xhscdn.com/{日期}/{哈希}/notes_pre_post/{资源ID}!h5_1080jpg`
  /// 末尾那个 `!h5_1080jpg` 是**小红书自己的图片处理模板** ——
  /// 水印（图上那行半透明的「小红书」）就是这一步加上去的，顺便还压了画质。
  ///
  /// 实测同一张图：
  ///   · 带模板 `!h5_1080jpg`  → 31,454 字节 JPEG，**有水印**
  ///   · 去掉模板 + 换公开节点 → 61,784 字节 PNG，**水印消失**
  ///
  /// 做法（社区通行）：
  ///   1. 取出 `notes_pre_post/{资源ID}` 这段路径，丢掉 `!...` 后缀
  ///   2. 域名换成 `sns-img-hw.xhscdn.com`（华为云）或 `sns-img-bd.xhscdn.com`（百度云）
  ///      —— `sns-webpic-qc` 是带鉴权的域，直接去掉参数访问会 403
  ///
  /// 换完拿不到就退回原地址，不能让用户白等一场。
  static String? noWatermarkImage(String url) {
    if (url.isEmpty) return null;
    // 取出 notes_pre_post/xxx 这一段（有的地址没有这个前缀，就只取资源 ID）
    final m = RegExp(r'(notes_pre_post/[A-Za-z0-9_~-]+)').firstMatch(url);
    String tail;
    if (m != null) {
      tail = m.group(1)!;
    } else {
      final id = RegExp(r'(1040g[^!/?]+)').firstMatch(url);
      if (id == null) return null;
      tail = id.group(1)!;
    }
    return 'https://sns-img-hw.xhscdn.com/$tail';
  }

  /// 同一张图的备用节点（华为云不通时试百度云）
  static String? noWatermarkImageAlt(String url) {
    final a = noWatermarkImage(url);
    if (a == null) return null;
    return a.replaceFirst('sns-img-hw.xhscdn.com', 'sns-img-bd.xhscdn.com');
  }

  /// 小红书视频：用 `originVideoKey` 拼公开节点地址，同样是**无水印**版本。
  ///
  /// 页面给的 `video.media.stream.h264[].masterUrl` 是带水印的成品；
  /// 而 `originVideoKey` 指向**上传时的原始对象**。
  static String? noWatermarkVideo(String? originKey) {
    if (originKey == null || originKey.isEmpty) return null;
    return 'https://sns-video-bd.xhscdn.com/$originKey';
  }

  /// 短链还原。必须做 —— noteId 和 xsec_token 都只在还原后的地址里。
  ///
  /// 注意：还原「成功」不等于「路径里就有 noteId」——
  /// 未登录时小红书会跳到 `/login?redirectPath=<编码后的真实地址>`，
  /// 真实地址就藏在参数里，交给 [_unwrapLoginRedirect] 展开。
  Future<String> _resolve(String url) async {
    if (_extract(url, _idInPath) != null) return url;
    var best = url;
    try {
      final r = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain));
      final real = r.realUri.toString();
      if (real.isNotEmpty && real != url) best = real;
    } catch (_) {
      // 短链解析失败不致命，下面的报错会说明情况
    }
    return best;
  }

  /// 展开登录页的 `redirectPath`。
  ///
  /// 实测：xhslink 短链在未登录时跳
  /// `https://www.xiaohongshu.com/login?redirectPath=<编码后的真实地址>`。
  /// 只认路径里的 `/discovery/item/{id}` 会误判成「没找到笔记号」，
  /// 但 noteId 和 xsec_token 完整地放在 `redirectPath` 里。
  String _unwrapLoginRedirect(String url) {
    if (!url.contains('redirectPath')) return url;
    try {
      final rp = Uri.parse(url).queryParameters['redirectPath'];
      if (rp != null && rp.isNotEmpty) return rp;
    } catch (_) {}
    return url;
  }

  String? _extract(String url, RegExp re) => re.firstMatch(url)?.group(1);

  /// token 在 URL 里可能是 `%3D` 这种形态，要还原成 `=`
  String? _decode(String? s) {
    if (s == null) return null;
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  /* ------------------------------------------------------------------ */
  /* HTML 里的 JSON 抠取                                                 */
  /* ------------------------------------------------------------------ */

  /// 从 [anchor] 之后找到第一个 `{`，然后按括号配对扫出完整的 JSON 对象。
  ///
  /// **必须做括号配对扫描，不能正则**：对象里嵌套对象和字符串，
  /// 字符串里还可能有 `}`、转义引号 —— 正则在这里一定会截断。
  /// （逻辑与服务端 `src/http.js` 的 `extractJsonAfter` 一致。）
  dynamic _extractJsonAfter(String html, String anchor) {
    final idx = html.indexOf(anchor);
    if (idx < 0) return null;
    final start = html.indexOf('{', idx + anchor.length);
    if (start < 0) return null;

    var depth = 0;
    var inStr = false;
    var quote = '';
    var escaped = false;

    for (var i = start; i < html.length; i++) {
      final ch = html[i];
      if (inStr) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == quote) {
          inStr = false;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        inStr = true;
        quote = ch;
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return _parseLooseJson(html.substring(start, i + 1));
        }
      }
    }
    return null;
  }

  /// 页面里的对象字面量不是严格 JSON —— 常见 `"key":undefined`。
  /// 把裸的 `undefined` / `NaN` 换成 `null` 再解析。
  dynamic _parseLooseJson(String s) {
    if (s.isEmpty) return null;
    var t = s
        .replaceAll(RegExp(r':\s*undefined\b'), ':null')
        .replaceAll(RegExp(r':\s*NaN\b'), ':null')
        .replaceAll(RegExp(r'\bundefined\b'), 'null');
    try {
      return jsonDecode(t);
    } catch (_) {
      return null;
    }
  }

  /* ------------------------------------------------------------------ */
  /* 数据映射                                                            */
  /* ------------------------------------------------------------------ */

  /// 小红书改过好几次结构，这里把三种都兼容上（与服务端 `findNote` 对齐）。
  ///
  /// 【主路径是顶层 `state.noteData`，不是 `state.note`】
  /// 实测 2026 年的页面返回的是：
  ///   `state.noteData.data.{noteData|note|noteInfo}`
  /// 注意 `noteData` 挂在**顶层**。一开始我按老文章写成 `state.note.noteData`，
  /// 结果一直报「没返回笔记内容」—— 明明页面数据好好的。
  Map<String, dynamic>? _findNote(dynamic state, String? noteId) {
    if (state is! Map) return null;

    // ---- 新结构：state.noteData.data.{noteData|note|noteInfo} ----
    final nd = state['noteData'];
    if (nd is Map) {
      final data = nd['data'];
      if (data is Map) {
        for (final k in ['noteData', 'note', 'noteInfo']) {
          final c = data[k];
          if (c == null) continue;
          if (c is List && c.isNotEmpty) {
            final first = c.first;
            if (first is Map) return Map<String, dynamic>.from(first);
          } else if (c is Map) {
            return Map<String, dynamic>.from(c);
          }
        }
      }
    }

    // ---- 旧结构：state.note.noteDetailMap[noteId].note ----
    final noteRoot = state['note'];
    if (noteRoot is Map) {
      final map = noteRoot['noteDetailMap'] ?? noteRoot['note_detail_map'];
      if (map is Map) {
        final direct = noteId == null ? null : map[noteId];
        if (direct is Map && direct['note'] is Map) {
          return Map<String, dynamic>.from(direct['note'] as Map);
        }
        for (final k in map.keys) {
          final entry = map[k];
          if (entry is Map && entry['note'] is Map) {
            return Map<String, dynamic>.from(entry['note'] as Map);
          }
        }
      }
      // 兜底：个别版本把 noteData 挂在 note 下面
      final nested = noteRoot['noteData'];
      if (nested is Map) {
        final d = nested['data'];
        final inner = (d is Map ? d['noteData'] : null);
        if (inner is Map) return Map<String, dynamic>.from(inner);
        if (nested['noteId'] != null) return Map<String, dynamic>.from(nested);
      }
    }

    return null;
  }

  Future<LocalResult> _fromNote(
      Map<String, dynamic> note, String noteId, String sourceUrl) async {
    final rawImages = _buildImages(note);

    // ---- 图片：换成无水印原图 ----
    // 先只换地址，然后抽验第一张 —— 配方对整条笔记是一致的，
    // 验一张就够，不至于为 46 张图多打 46 个请求。验不过就整组退回原地址。
    final cleanImages = rawImages
        .map((im) {
      final clean = noWatermarkImage(im.url);
      return clean == null
          ? im
          // 【必须把动图字段一起带过去】
          // 这里原来是 `LocalImage(url: clean, width: .., height: ..)` ——
          // 新建对象时漏了 videoUrl/durationSec，结果动图信息在这一步被丢光，
          // 表现是「18 张动图，一张都识别不出来」。
          : LocalImage(
              url: clean,
              width: im.width,
              height: im.height,
              videoUrl: im.videoUrl,
              durationSec: im.durationSec,
            );
    })
        .toList();

    var images = rawImages;
    if (cleanImages.isNotEmpty &&
        rawImages.isNotEmpty &&
        cleanImages.first.url != rawImages.first.url) {
      final probe = await _probeOkDetail(
        cleanImages.first.url,
        noWatermarkImageAlt(rawImages.first.url),
      );
      if (probe.ok) {
        images = cleanImages;
        // 【HEIC → JPEG】老安卓解不了 HEIC，相册里会是一张看不见的图。
        // 同地址加格式参数就能拿到等分辨率的 JPEG，整组统一换掉。
        if (probe.heic) {
          images = cleanImages
              .map((im) => LocalImage(
                    url: _asJpeg(im.url),
                    width: im.width,
                    height: im.height,
                    // 动图信息要带着 —— 这里新建对象漏过一次，18 张动图全丢了
                    videoUrl: im.videoUrl,
                    durationSec: im.durationSec,
                  ))
              .toList();
        }
      }
    }

    // ---- 视频：优先用 originVideoKey 拼的原始对象（无水印）----
    final rawVideoUrl = _https(_buildVideoUrl(note));
    var videoUrl = rawVideoUrl;
    final originKey = _originVideoKey(note);
    final cleanVideo = noWatermarkVideo(originKey);
    if (cleanVideo != null) {
      if ((await _probeOkDetail(cleanVideo, null)).ok) {
        videoUrl = cleanVideo;
      }
    }

    final isVideo =
        note['type'] == 'video' || (videoUrl.isNotEmpty && images.isEmpty);

    if (images.isEmpty && videoUrl.isEmpty) {
      throw const LocalParseError('这条笔记没有可下载的图片或视频。');
    }

    final user = note['user'];
    final author = user is Map
        ? (user['nickName'] ?? user['nickname'] ?? user['name'] ?? '').toString()
        : '';

    var title = (note['title'] ?? '').toString();
    if (title.isEmpty && note['desc'] != null) {
      final d = note['desc'].toString();
      title = d.length > 60 ? d.substring(0, 60) : d;
    }

    final durMs = (note['video'] is Map &&
            (note['video'] as Map)['capa'] is Map &&
            ((note['video'] as Map)['capa'] as Map)['duration'] != null)
        ? (((note['video'] as Map)['capa'] as Map)['duration'] as num).toInt()
        : 0;

    return LocalResult(
      platform: key,
      platformName: name,
      type: (isVideo && videoUrl.isNotEmpty) ? 'video' : 'images',
      title: title.replaceAll(RegExp(r'\s+'), ' ').trim(),
      author: author,
      cover: images.isNotEmpty ? images.first.url : '',
      durationSec: durMs > 0 ? (durMs / 1000).round() : 0,
      publishTime: _formatDate(note['time'] ?? note['lastUpdateTime']),
      videoUrl: videoUrl,
      referer: referer,
      images: images,
      sourceUrl: sourceUrl,
    );
  }

  /// 从上到下找 `originVideoKey`（小红书不同版本放在不同层级）
  String? _originVideoKey(Map<String, dynamic> note) {
    final v = note['video'];
    if (v is! Map) return null;
    final c = v['consumer'];
    if (c is Map) {
      final k = c['originVideoKey'] ?? c['origin_video_key'];
      if (k != null && '$k'.isNotEmpty) return '$k';
    }
    final media = v['media'];
    if (media is Map) {
      final k = media['originVideoKey'] ?? media['origin_video_key'];
      if (k != null && '$k'.isNotEmpty) return '$k';
    }
    return null;
  }

  /// 抽查地址能不能取到数据（只取 1KB）。拿不到就试备选，都拿不到返回 false。
  /// 抽验第一张图能不能下 —— 顺带把是否为 HEIC 告诉调用方。
  ///
  /// 【为什么要关心 HEIC】动图笔记的封面 CDN 返回 `image/heic`。
  /// Android 10+ 能解，但我们 minSdk 是 24（Android 7），
  /// 老设备解码不了 —— 表现是「存进相册了却看不见」，很难查。
  /// 好在同一条地址加 `?imageView2/format/jpg` 就能拿到**同分辨率**的 JPEG
  /// （实测 175 KB → 173 KB，不是压缩，只是换容器）。
  Future<({bool ok, bool heic})> _probeOkDetail(String primary, String? alt) async {
    var ok = false;
    var heic = false;
    for (final u in [primary, if (alt != null && alt.isNotEmpty) alt]) {
      try {
        final r = await _dio.get<List<int>>(u,
            options: Options(
              responseType: ResponseType.bytes,
              headers: const {'Range': 'bytes=0-1023'},
            ));
        final bytes = r.data ?? const <int>[];
        if ((r.statusCode == 200 || r.statusCode == 206) && bytes.length > 200) {
          ok = true;
          final ct = (r.headers.value('content-type') ?? '').toLowerCase();
          // 两重判断：content-type 会说谎，再对文件头（bytes 4-12 = "ftypheic" 等）
          final magic = String.fromCharCodes(
              bytes.length >= 12 ? bytes.sublist(4, 12) : const <int>[]);
          heic = ct.contains('heic') ||
              ct.contains('heif') ||
              magic.startsWith('ftyphei') ||
              magic.startsWith('ftypmif');
          if (heic) return (ok: true, heic: true);
          return (ok: true, heic: false);
        }
      } catch (_) {
        // 试下一个
      }
    }
    return (ok: ok, heic: heic);
  }

  /// 把 HEIC 换成同分辨率的 JPEG。
  /// 用 `imageMogr2` 而不是 `!h5_1080jpg` —— 后者是**加水印**的模板。
  String _asJpeg(String url) {
    if (url.contains('?')) return url;
    return '$url?imageView2/format/jpg';
  }

  List<LocalImage> _buildImages(Map<String, dynamic> note) {
    final list = note['imageList'] ?? note['image_list'];
    if (list is! List) return const [];

    final out = <LocalImage>[];
    for (final it in list) {
      if (it is! Map) continue;
      // 详情大图优先，其次才是主 url
      var detail = '';
      final info = it['infoList'] ?? it['info_list'];
      if (info is List) {
        for (final e in info) {
          if (e is! Map || e['url'] == null) continue;
          if (e['imageScene'] == 'H5_DTL') detail = e['url'].toString();
        }
      }
      final main = (it['url'] ??
              it['urlDefault'] ??
              it['url_default'] ??
              it['urlPre'] ??
              it['url_pre'] ??
              '')
          .toString();
      final url = detail.isNotEmpty ? detail : main;
      if (url.isEmpty) continue;

      // ---- 动图（Live Photo）----
      //
      // 小红书从 2024 年起大量推「动图」笔记：静态封面 + 一段 2~3 秒的短视频。
      // 数据长这样：
      //   { "livePhoto": true,
      //     "url": ".../notes_pre_post/xxx",            ← 封面图
      //     "stream": { "h264": [{ "masterUrl": "...mp4?sign=...",
      //                            "videoDuration": 2933 }] } }
      //
      // 只取封面的话，用户拿到的就是一张死图 —— 动效和声音全丢。
      final isLive = it['livePhoto'] == true || it['live_photo'] == true;
      final liveUrl = isLive ? _liveVideoUrl(it) : '';
      final liveSec = isLive ? _liveVideoSeconds(it) : 0;

      out.add(LocalImage(
        url: _https(url),
        width: (it['width'] as num?)?.toInt() ?? 0,
        height: (it['height'] as num?)?.toInt() ?? 0,
        videoUrl: liveUrl,
        durationSec: liveSec,
      ));
    }
    return out;
  }

  /// 动图的视频地址。
  ///
  /// 优先 h264 —— 兼容性最好，而且**带音轨**（动图的意义就在声音和动效）。
  String _liveVideoUrl(Map<dynamic, dynamic> it) {
    final st = it['stream'];
    if (st is! Map) return '';
    for (final codec in ['h264', 'h265', 'av1']) {
      final arr = st[codec];
      if (arr is! List) continue;
      for (final e in arr) {
        if (e is! Map) continue;
        final u = (e['masterUrl'] ?? e['master_url'] ?? '').toString();
        if (u.isNotEmpty) return _https(u);
        // 兜底：有的版本只给 backupUrls
        final bk = e['backupUrls'] ?? e['backup_urls'];
        if (bk is List && bk.isNotEmpty) return _https('${bk.first}');
      }
    }
    return '';
  }

  /// 动图时长（秒）。小红书给的是毫秒。
  int _liveVideoSeconds(Map<dynamic, dynamic> it) {
    final st = it['stream'];
    if (st is! Map) return 0;
    for (final codec in ['h264', 'h265', 'av1']) {
      final arr = st[codec];
      if (arr is! List || arr.isEmpty) continue;
      final e = arr.first;
      if (e is! Map) continue;
      final ms = (e['videoDuration'] ?? e['video_duration'] ?? e['duration'] as num?)
          ?.toInt();
      if (ms != null && ms > 0) return (ms / 1000).round();
    }
    return 0;
  }

  /// 取分辨率最高的一条。h264 → h265 → av1 依次回退。
  String _buildVideoUrl(Map<String, dynamic> note) {
    final v = note['video'];
    if (v is! Map) return '';

    final media = (v['media'] is Map ? v['media'] : v) as Map;
    final stream = media['stream'];
    final cands = <Map>[];
    if (stream is Map) {
      for (final k in ['h264', 'h265', 'av1']) {
        final arr = stream[k];
        if (arr is List) cands.addAll(arr.whereType<Map>());
      }
    }

    if (cands.isEmpty) {
      return (media['masterUrl'] ??
              media['master_url'] ??
              v['masterUrl'] ??
              v['url'] ??
              '')
          .toString();
    }

    cands.sort((a, b) {
      final sa = ((a['width'] as num?)?.toInt() ?? 0) *
          ((a['height'] as num?)?.toInt() ?? 0);
      final sb = ((b['width'] as num?)?.toInt() ?? 0) *
          ((b['height'] as num?)?.toInt() ?? 0);
      return sb.compareTo(sa);
    });

    final best = cands.first;
    return (best['masterUrl'] ?? best['master_url'] ?? best['url'] ?? '')
        .toString();
  }

  /// 小红书给的是 http 地址，必须转 https —— 否则 Android 会拦明文请求。
  String _https(String u) {
    if (u.isEmpty) return u;
    return u.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://');
  }

  String _formatDate(dynamic ts) {
    final n = ts is num ? ts.toInt() : int.tryParse('$ts');
    if (n == null || n <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(n > 100000000000 ? n : n * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
