import 'package:dio/dio.dart';

import 'engine.dart';
import 'types.dart';

/// 抖音 · 本地解析
///
/// 逻辑基本是把服务端 `03-后端服务/src/adapters/douyin.js` 搬过来，
/// 只把「playwright 开浏览器」换成「App 内置 WebView」：
///
/// · **视频**：打开 `/video/{id}`，拦截页面自己发的 `/aweme/v1/web/aweme/detail/`
/// · **图文**：打开 `/note/{id}`，从 DOM 抠图
///   （图文页面**不发** detail 接口 —— 服务端那边实测确认过，别再踩）
class DouyinLocalPlatform extends LocalPlatform {
  @override
  String get key => 'douyin';

  @override
  String get name => '抖音';

  @override
  List<String> get hosts => const ['douyin.com', 'iesdouyin.com'];

  @override
  String get referer => 'https://www.douyin.com/';

  static final _idInPath = RegExp(r'/(?:video|note|share/video|share/note)/(\d{15,25})');
  static final _idInText = RegExp(r'(\d{15,25})');

  /// 短链还原专用的 Dio —— 复用连接，别每次都 new 一个
  static final Dio _shortLinkDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 8),
    followRedirects: true,
    maxRedirects: 6,
    validateStatus: (s) => s != null && s < 400,
  ));

  /* ------------------------------------------------------------------ */

  @override
  Future<LocalResult> parse(String url) async {
    final finalUrl = await _resolveShortLink(url);
    final id = _extractId(finalUrl) ?? _extractId(url);
    if (id == null) {
      throw const LocalParseError('没在链接里找到抖音作品号');
    }

    final isNote = finalUrl.contains('/note/') || url.contains('/note/');
    return isNote ? _parseNote(id, url) : _parseVideo(id, url);
  }

  /// v.douyin.com 短链还原成带作品号的完整地址。
  ///
  /// 【先发 HEAD 再考虑 GET】最初写的是先 GET —— 那会把整个分享页（上百 KB）
  /// 完整下下来，只为读一个跳转地址，白白多花将近一秒。
  /// HEAD 只拿响应头、不取正文，快得多。只有 HEAD 不灵时才退到 GET。
  Future<String> _resolveShortLink(String url) async {
    if (_extractId(url) != null) return url;
    for (final method in ['HEAD', 'GET']) {
      try {
        final r = await _shortLinkDio.request<String>(
          url,
          options: Options(method: method, responseType: ResponseType.plain),
        );
        final real = r.realUri.toString();
        if (_extractId(real) != null) return real;
      } catch (_) {
        // 换下一种方法
      }
    }
    return url;
  }

  String? _extractId(String url) {
    final m = _idInPath.firstMatch(url);
    if (m != null) return m.group(1);
    // 兜底：整段里找一串长数字（短链还原后常是这个形态）
    final t = _idInText.firstMatch(url);
    return t?.group(1);
  }

  /* ------------------------------------------------------------------ */
  /* 视频：拦截详情接口                                                  */
  /* ------------------------------------------------------------------ */

  /// 视频：走**手机分享页**，不要走 PC 站。
  ///
  /// 【为什么换入口 —— 这是整个抖音视频本地化最关键的一步】
  /// PC 站（`www.douyin.com/video/{id}`）在 WebView 里能加载 72 万字节 HTML、
  /// 钩子也装上了，但它自己发的 `/aweme/v1/web/aweme/detail/` 请求**拿不到内容**
  /// （status=0、body 为空），于是播放器起不来、页面里也没有任何视频地址。
  /// 四条备用路（`<video>` blob、页面脚本、`__pace_f` RSC 流、网络层请求）全堵死。
  ///
  /// 换成**手机 UA 打开同一个链接**，抖音会跳到 `m.douyin.com/share/video/{id}` ——
  /// 这是面向 App 内浏览器/分享场景的页面，**`<video>` 元素里直接挂着可下载的地址**：
  ///   `https://m.douyin.com/aweme/v1/playwm/?...&video_id=...`
  ///
  /// 而且这个 `playwm` 路径换成 `play` 就是**无水印**版本（抖音沿用多年的经典规则）。
  ///
  /// 教训和小红书那次一模一样：**入口/形态选错，怎么调都白搭。**
  Future<LocalResult> _parseVideo(String id, String sourceUrl) async {
    final engine = LocalEngine.instance;
    await engine.setUserAgent(LocalEngine.mobileUa);
    try {
      var lastUrl = '';
      var stable = 0;
      var firstSeenAt = 0;

      final r = await engine.evaluatePolling(
        'https://www.douyin.com/video/$id',
        _videoProbeScript,
        settle: const Duration(milliseconds: 1800),
        interval: const Duration(milliseconds: 300),
        timeout: const Duration(seconds: 18),
        isDone: (v) {
          if (v is! Map) return false;
          final u = (v['videoUrl'] ?? '').toString();
          if (u.isNotEmpty && firstSeenAt == 0) {
            firstSeenAt = DateTime.now().millisecondsSinceEpoch;
          }
          // 等地址出现并稳定两轮，避免拿到播放器切换清晰度时的中间值
          if (u.isNotEmpty && u == lastUrl) {
            stable++;
          } else {
            stable = 0;
          }
          lastUrl = u;
          if (u.isNotEmpty && stable >= 2) return true;
          // 兜底：已经有地址但一直变（播放器在切清晰度），最多再等 3 秒
          if (u.isNotEmpty &&
              DateTime.now().millisecondsSinceEpoch - firstSeenAt > 3000) {
            return true;
          }
          return false;
        },
      );

      if (r is! Map) {
        throw const LocalParseError(_videoFailHint);
      }
      final rawVideoUrl = (r['videoUrl'] ?? '').toString();
      if (rawVideoUrl.isEmpty) {
        throw const LocalParseError(_videoFailHint);
      }

      final noWm = _toNoWatermark(rawVideoUrl);
      // 解析时就把 302 解掉，直接给下载器 CDN 地址 ——
      // 否则每次下载都要先请求一次 snssdk 再跳过去，白白多一跳，
      // 大文件上这一跳的握手开销很明显（用户反馈「下载慢」就有这部分）。
      final direct = await _resolveRedirect(noWm) ?? noWm;
      final isPlayable = await _probePlayable(direct);

      return LocalResult(
        platform: key,
        platformName: name,
        type: 'video',
        title: (r['title'] ?? '').toString(),
        author: (r['author'] ?? '').toString(),
        cover: (r['cover'] ?? '').toString(),
        durationSec: (r['durationSec'] as num?)?.toInt() ?? 0,
        resolution: (r['resolution'] ?? '').toString(),
        videoUrl: isPlayable ? direct : rawVideoUrl,
        // 手机站的媒体地址要用手机站做 Referer
        referer: 'https://m.douyin.com/',
        sourceUrl: sourceUrl,
      );
    } finally {
      // 一定要还原，否则会污染后续的图文解析（图文必须用桌面 UA）
      await engine.setUserAgent(LocalEngine.desktopUa);
    }
  }

  /// 跟着 302 走到最终地址。
  ///
  /// 用「只取 1 字节」的 Range GET，而不是 HEAD ——
  /// 实测 `aweme/v1/play/` 这个接口**只对 GET 返回 302**，HEAD 请求不跳转，
  /// 所以用 HEAD 会一直解不出最终地址。
  Future<String?> _resolveRedirect(String url) async {
    try {
      final r = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 400,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 7) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
          'Referer': 'https://m.douyin.com/',
          'Range': 'bytes=0-0',
        },
      )).get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final real = r.realUri.toString();
      return real != url && real.startsWith('http') ? real : null;
    } catch (_) {
      return null;
    }
  }

  static const String _videoFailHint =      '没能从抖音手机分享页取到视频地址。可能是作品已删除、仅好友可见，或需要登录。\n'
      '可以到「我的 → 解析偏好」临时切到服务器模式。';

  /// `playwm`（带水印）→ `play`（无水印）。
  ///
  /// 【为什么不能只改路径】手机分享页给的是
  /// `https://m.douyin.com/aweme/v1/playwm/?...&video_id=...`，
  /// 但 **`m.douyin.com` 上没有 `play` 这个口子**（实测 404）。
  /// 同一个 `video_id` 在 `aweme.snssdk.com` 上有，而且是**无水印版本**。
  ///
  /// 实测同一作品两个地址拿到的文件确实不同：
  ///   play   → 3,060,859 字节（无水印）
  ///   playwm → 3,981,301 字节（带水印）
  ///
  /// 所以这里保留 `video_id` / `ratio` / `line`，把 host 和路径换成 snssdk 的。
  String _toNoWatermark(String url) {
    if (url.isEmpty) return url;
    final u = Uri.tryParse(url);
    if (u == null) return url;

    final vid = u.queryParameters['video_id'] ?? '';
    if (vid.isEmpty) return url;

    final ratio = u.queryParameters['ratio'] ?? '720p';
    final line = u.queryParameters['line'] ?? '0';
    return 'https://aweme.snssdk.com/aweme/v1/play/'
        '?video_id=$vid&ratio=$ratio&line=$line';
  }

  /// 验证无水印地址真的能取到数据；不行就回退到带水印那条。
  ///
  /// 不能想当然认为 `play` 一定可用 —— 平台随时可能收回这个口子。
  Future<bool> _probePlayable(String url) async {
    try {
      final r = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (s) => s != null && s < 400,
        headers: const {
          'Range': 'bytes=0-1023',
          'Referer': 'https://m.douyin.com/',
          'User-Agent': LocalEngine.mobileUa,
        },
      )).get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final n = (r.data ?? const <int>[]).length;
      return (r.statusCode == 200 || r.statusCode == 206) && n > 500;
    } catch (_) {
      return false;
    }
  }

  /* ------------------------------------------------------------------ */
  /* 图文：从 DOM 抠                                                     */
  /* ------------------------------------------------------------------ */

  /// 图文：从 DOM 抠。
  ///
  /// 【为什么要重试】抖音对同一 IP 的频繁访问会**悄悄降级页面** ——
  /// 页面能打开、也不报错，就是一张图都不渲染。
  /// 实测同一个链接：单独跑能拿到 46 张，在一串测试里连着跑就是 0 张。
  /// 这不是代码问题，是风控。所以失败后歇一下重试一次，
  /// 两次都不行才报错，并把真实原因告诉用户（而不是含糊地说「失败了」）。
  Future<LocalResult> _parseNote(String id, String sourceUrl) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      // 首次尝试给短超时：如果抖音要降级，通常**一开始就不给图**，
      // 没必要傻等 20 秒才判断失败。重试那次才给足时间。
      final r = await _fetchNoteOnce(
        id,
        sourceUrl,
        timeout: attempt == 0
            ? const Duration(seconds: 9)
            : const Duration(seconds: 20),
      );
      if (r != null) return r;
      if (attempt == 0) {
        // 歇一下再试，给风控一点冷却时间
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }
    throw const LocalParseError(
      '抖音这次没返回图片内容。\n\n'
      '通常是短时间内解析太频繁触发了风控 —— 等十几秒再试一次就好；'
      '如果一直不行，也可以到「我的 → 解析偏好」临时切到服务器模式。',
    );
  }

  Future<LocalResult?> _fetchNoteOnce(
    String id,
    String sourceUrl, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final pageUrl = 'https://www.douyin.com/note/$id';

    // 轮播是懒加载的：等「图片数量连续几轮不再增长」再收工。
    // 这段等待必须由 Dart 驱动 —— WebView 不会等 Promise。
    var lastCount = -1;
    var stable = 0;
    var firstSeenAt = 0;

    final r = await LocalEngine.instance.evaluatePolling(
      pageUrl,
      _noteProbeScript,
      settle: const Duration(milliseconds: 600),
      interval: const Duration(milliseconds: 250),
      timeout: timeout,
      isDone: (value) {
        final n = (value is Map && value['images'] is List)
            ? (value['images'] as List).length
            : 0;
        final total = (value is Map ? (value['total'] as num?)?.toInt() : 0) ?? 0;

        if (n > 0 && firstSeenAt == 0) {
          firstSeenAt = DateTime.now().millisecondsSinceEpoch;
        }
        if (n > 0 && n == lastCount) {
          stable++;
        } else {
          stable = 0;
        }
        lastCount = n;

        // 【最快的一条】页面自己写着总数（比如 4/46），拿够了立刻收工
        if (n > 0 && total > 0 && n >= total) return true;

        // 主判据：连续 2 轮数量不再变化，说明加载完了
        if (n > 0 && stable >= 2) return true;

        // 【兜底，很重要】已经拿到图片，但数量一直在小幅波动
        // （轮播会边渲染边回收，数量可能在 45/46 之间反复跳）——
        // 这种情况「连续不变」可能永远等不到，曾经因此白等满 25 秒超时。
        // 所以只要已经有图，最多再观察 2 秒就收工。
        if (n > 0 &&
            DateTime.now().millisecondsSinceEpoch - firstSeenAt > 2000) {
          return true;
        }
        return false;
      },
    );

    if (r is! Map) {
      // 页面连内容都没读到 —— 大概率也是风控，交给上层重试
      return null;
    }
    final rawImages = r['images'];
    if (rawImages is! List || rawImages.isEmpty) {
      return null;
    }

    final images = <LocalImage>[];
    for (final it in rawImages) {
      final m = it is Map ? it : const {};
      final url = (m['url'] ?? '').toString();
      if (url.isEmpty) continue;
      images.add(LocalImage(
        url: url,
        width: _asInt(m['width']) ?? 0,
        height: _asInt(m['height']) ?? 0,
      ));
    }
    if (images.isEmpty) throw const LocalParseError('图文作品没抓到可用的图片地址');

    return LocalResult(
      platform: key,
      platformName: name,
      type: 'images',
      title: (r['title'] ?? '').toString(),
      author: (r['author'] ?? '').toString(),
      cover: images.first.url,
      referer: referer,
      images: images,
      sourceUrl: sourceUrl,
    );
  }

  /// 手机分享页的探针。
  ///
  /// 核心就一句：**`<video>` 元素的 src** —— 手机分享页会把它直接挂在元素上，
  /// 这是 PC 站无论如何都拿不到的东西。
  ///
  /// 注意排除 `blob:` 开头的地址（那是 MSE，不是可下载文件）和平台自己的
  /// 宣传片（`douyinstatic.com` 上的 mp4）。
  static const String _videoProbeScript = r'''
(function () {
  function good(u) {
    if (!u) return false;
    u = String(u);
    if (u.indexOf('blob:') === 0) return false;         // MSE，不可下载
    if (u.indexOf('douyinstatic.com') > -1) return false; // 平台宣传片
    return u.indexOf('http') === 0;
  }

  var v = document.querySelector('video');
  var url = '';
  if (v) {
    if (good(v.currentSrc)) url = String(v.currentSrc);
    else if (good(v.src)) url = String(v.src);
    if (!url) {
      var ss = v.querySelectorAll('source');
      for (var i = 0; i < ss.length; i++) {
        if (good(ss[i].src)) { url = String(ss[i].src); break; }
      }
    }
  }

  var title = String(document.title || '').replace(/\s*-\s*抖音\s*$/, '').trim();

  // 作者：和图文页一样的「三条约束」，页面上大部分 /user/ 链接都不是作者
  var author = '';
  var links = document.querySelectorAll('a[href*="/user/"]');
  for (var j = 0; j < links.length; j++) {
    var a = links[j];
    var href = a.getAttribute('href') || '';
    if (href.indexOf('self') > -1) continue;
    var t = String(a.textContent || '').trim();
    if (!t || t.length > 40) continue;
    if (!(a.offsetWidth || a.offsetHeight || a.getClientRects().length)) continue;
    author = t;
    break;
  }

  // 手机分享页**一个 /user/ 链接都没有**，昵称是以 @ 开头直接显示在页面上的
  // （页面文本形如：记录美好生活 | @吨吨八嘎 | 作品标题…）。
  // 所以这里按「元素本身就是一段以 @ 开头的短文本」来找。
  if (!author) {
    var els = document.querySelectorAll('span, div, a, p');
    for (var k = 0; k < els.length; k++) {
      var el = els[k];
      if (el.children.length > 0) continue;      // 必须是叶子节点，别把容器算进来
      var tx = String(el.textContent || '').trim();
      if (tx.length < 2 || tx.length > 30) continue;
      if (tx.charAt(0) !== '@') continue;
      if (!(el.offsetWidth || el.offsetHeight)) continue;
      author = tx.replace(/^@/, '');
      break;
    }
  }

  var cover = v ? String(v.poster || '') : '';
  var dur = (v && isFinite(v.duration) && v.duration > 0) ? Math.round(v.duration) : 0;

  // 清晰度：地址里通常带 ratio=720p
  var res = '';
  var m = url.match(/ratio=(\d+p)/);
  if (m) res = m[1].toUpperCase();

  return JSON.stringify({
    videoUrl: url,
    title: title,
    author: author,
    cover: cover,
    durationSec: dur,
    resolution: res
  });
})()
''';

  /// 同步表达式，返回 JSON 字符串。
  ///
  /// 图片判据：URL 带 `tplv-dy-aweme-images` 且落在这两个 CDN 域上 ——
  /// 其余都是 UI 图标 / 头像 / 二维码。按对象 id 去重（同一张图有 1x/2x 两个地址）。
  ///
  /// 作者判据三条缺一不可：非 `/user/self`、元素可见、文本非空。
  /// 页面上有 19 个 `a[href*="/user/"]`，只有 1 个是真作者 ——
  /// 少任何一条都会抓到推荐流里的隐藏元素，甚至不可见字符组成的假名字。
  static const String _noteProbeScript = r'''
(function () {
  var seen = {}, out = [];
  var all = document.querySelectorAll('img');
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    var src = el.currentSrc || el.src || '';
    if (!src || src.indexOf('data:') === 0) continue;
    if (src.indexOf('aweme-images') === -1) continue;
    if (!/douyinpic\.com|byteimg\.com/.test(src)) continue;
    var m = src.match(/tos-cn-i-[a-z0-9]+\/([A-Za-z0-9_~-]+?)~/);
    var key = m ? m[1] : src;
    if (seen[key]) continue;
    seen[key] = 1;
    out.push({ url: src, width: el.naturalWidth || 0, height: el.naturalHeight || 0 });
  }

  var title = String(document.title || '').replace(/\s*-\s*抖音\s*$/, '').trim();

  // 页面上直接写着「当前/总数」（比如 4/46）—— 拿它当「齐了没」的判据，
  // 比等「数量不再变化」快得多：一集齐立刻收工，不用干等观察窗口。
  var total = 0;
  try {
    var tm = String(document.body ? document.body.innerText : '')
        .match(/(?:^|\s)\d{1,3}\s*\/\s*(\d{1,4})(?:\s|$)/);
    if (tm) total = parseInt(tm[1], 10) || 0;
  } catch (e) {}

  var author = '';
  var links = document.querySelectorAll('a[href*="/user/"]');
  for (var j = 0; j < links.length; j++) {
    var a = links[j];
    var href = a.getAttribute('href') || '';
    if (href.indexOf('self') > -1) continue;
    var t = String(a.textContent || '').trim();
    if (!t || t.length > 40) continue;
    if (!(a.offsetWidth || a.offsetHeight || a.getClientRects().length)) continue;
    author = t;
    break;
  }

  return JSON.stringify({ images: out, title: title, author: author, total: total });
})()
''';

  /* ------------------------------------------------------------------ */
  /* 小工具                                                              */
  /* ------------------------------------------------------------------ */

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
