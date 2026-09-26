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
      '如果这条链接在抖音 App 里能正常打开，麻烦把链接发给我们排查。';

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
      '如果一直不行，换个链接试试，或过一会儿再来。',
    );
  }

  Future<LocalResult?> _fetchNoteOnce(
    String id,
    String sourceUrl, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final pageUrl = 'https://www.douyin.com/note/$id';

    // 【为什么改成读 __pace_f 而不是抠 DOM】
    //
    // 抠 DOM 有两个硬伤：
    //   1. 轮播是**懒加载**的 —— 只渲染可见的那几张，得一边等一边数数量，
    //      慢而且可能漏。
    //   2. **动图的视频地址根本不在 DOM 里** —— 页面只把静态封面渲染成 <img>，
    //      用户存下来就是一张死图，动效和声音全丢了。
    //
    // 而页面里的 `__pace_f`（React Server Components 的数据流）**一次就带了
    // 完整的 images 数组**，每项含：
    //   · urlList[]        —— 静态图（无水印，带 tplv-dy-aweme-images 模板）
    //   · video.playAddr[] —— **动图的短视频**（带音轨，形如 douyinvod.com/...mp4）
    //   · clipType == 5    —— 动图标志
    //
    // 所以拿到第一条就齐了，不用等稳定；DOM 抠图保留为兜底，
    // 万一哪天 pace 结构变了还能出结果。
    final r = await LocalEngine.instance.evaluatePolling(
      pageUrl,
      _paceNoteScript,
      settle: const Duration(milliseconds: 500),
      interval: const Duration(milliseconds: 250),
      timeout: timeout,
      isDone: (v) =>
          v is Map && v['images'] is List && (v['images'] as List).isNotEmpty,
    );

    if (r is! Map) return null;

    var rawImages = r['images'];
    var title = (r['title'] ?? '').toString();
    var author = (r['author'] ?? '').toString();

    // 【为什么要补读一次 DOM】
    // `__pace_f` 里的图片数据**来得很早**（页面骨架一出来就有），
    // 而 `document.title` 和作者名是页面稍后才设上的 ——
    // 于是「图片有了但标题还是空的」。所以标题/作者缺任何一项都要补读；
    // 图片没解析出来也走这条路（DOM 抠图兜底）。
    final needDom = rawImages is! List ||
        rawImages.isEmpty ||
        title.isEmpty ||
        author.isEmpty;

    if (needDom) {
      final dom = await LocalEngine.instance.evalCurrent(_noteDomScript);
      if (dom is Map) {
        final domImages = dom['images'];
        if ((rawImages is! List || rawImages.isEmpty) && domImages is List) {
          rawImages = domImages;
        }
        if (title.isEmpty) title = (dom['title'] ?? '').toString();
        if (author.isEmpty) author = (dom['author'] ?? '').toString();
      }
    }

    if (rawImages is! List || rawImages.isEmpty) return null;

    final images = <LocalImage>[];
    for (final it in rawImages) {
      if (it is! Map) continue;
      final url = (it['url'] ?? '').toString();
      if (url.isEmpty) continue;
      images.add(LocalImage(
        url: url,
        width: _asInt(it['width']) ?? 0,
        height: _asInt(it['height']) ?? 0,
        videoUrl: (it['videoUrl'] ?? '').toString(),
        durationSec: _asInt(it['durationSec']) ?? 0,
      ));
    }
    if (images.isEmpty) throw const LocalParseError('图文作品没抓到可用的图片地址');

    return LocalResult(
      platform: key,
      platformName: name,
      type: 'images',
      title: title,
      author: author,
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

  // ---- 封面 ----
  //
  // 【为什么不能只取 video.poster】实测抖音的手机分享页上，`<video>` 的
  // `poster` 属性经常是空的 —— 用户看到的就是一张空白卡片（只有播放按钮）。
  // 所以按可靠度依次兜底：
  //   1. og:image（平台给分享卡片准备的图，最稳）
  //   2. video 的 poster
  //   3. 页面上第一张够大的图（通常是视频封面）
  var cover = '';
  var og = document.querySelector('meta[property="og:image"], meta[name="og:image"]');
  if (og) cover = String(og.getAttribute('content') || '').trim();
  if (!cover && v) cover = String(v.poster || '').trim();
  if (!cover) {
    var all = document.querySelectorAll('img');
    for (var q = 0; q < all.length; q++) {
      var el = all[q];
      var s = el.currentSrc || el.src || '';
      if (!s || s.indexOf('http') !== 0) continue;
      // 太小的多半是头像/图标
      if (el.naturalWidth && el.naturalWidth < 300) continue;
      if (/avatar|icon|logo|emoji/i.test(s)) continue;
      cover = s;
      break;
    }
  }
  // 网站常常给 http 的封面地址，必须升到 https —— 否则 Android 会拦明文请求
  if (cover.indexOf('http://') === 0) cover = 'https://' + cover.substring(7);

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

  /// 读 `__pace_f`（React Server Components 的数据流）—— **图文作品的主路径**。
  ///
  /// 【为什么要用它，而不是抠 DOM】
  /// 抠 DOM 有两个硬伤：
  ///   1. 轮播是**懒加载**的，只渲染可见的那几张 —— 得一边等一边数数量，
  ///      慢，而且可能漏。
  ///   2. **动图的视频地址根本不在 DOM 里** —— 页面只把静态封面渲染成 `<img>`。
  ///      用户保存下来就是一张死图，动效和声音全丢。
  ///
  /// 而 `__pace_f` 里一次就带着完整的 `images` 数组：
  ///   · `urlList[]`        —— 静态图，**无水印**（`downloadUrlList` 才带水印，不用它）
  ///   · `video.playAddr[]` —— **动图的短视频**（带音轨）
  ///   · `clipType == 5`    —— 动图标志
  ///
  /// 【一个踩过的坑】`playAddr` 是**数组**，元素字段名是 `src`。
  /// 一开始按对象处理、找 `playAddr.urlList`，结果永远是 0 条 ——
  /// 明明数据就在眼前却拿不到。
  static const String _paceNoteScript = r'''
(function () {
  var host = '';
  function scan() {
    var f = window.__pace_f || [];
    for (var i = 0; i < f.length; i++) {
      var s = '';
      try { s = String(f[i]); } catch (e) { continue; }
      if (s.indexOf('"images":[{"width"') > -1) { host = s; break; }
    }
    if (!host) return null;

    // 平衡括号抠出完整的数组 —— JSON.parse 需要一整段，不能截断
    var at = host.indexOf('"images":[');
    var start = host.indexOf('[', at);
    var depth = 0, inStr = false, esc = false, end = -1;
    for (var k = start; k < host.length; k++) {
      var ch = host.charAt(k);
      if (inStr) {
        if (esc) esc = false;
        else if (ch === '\\') esc = true;
        else if (ch === '"') inStr = false;
        continue;
      }
      if (ch === '"') { inStr = true; continue; }
      if (ch === '[' || ch === '{') depth++;
      else if (ch === ']' || ch === '}') { depth--; if (depth === 0) { end = k; break; } }
    }
    if (end < 0) return null;
    try { return JSON.parse(host.slice(start, end + 1)); } catch (e) { return null; }
  }

  var host = '';
  var arr = scan();
  if (!arr) return JSON.stringify({ images: [] });

  var out = [];
  for (var n = 0; n < arr.length; n++) {
    var it = arr[n] || {};
    var list = it.urlList || it.url_list || [];
    var url = list.length ? String(list[0]) : '';
    if (!url) continue;

    var item = { url: url, width: it.width || 0, height: it.height || 0 };

    // 动图：视频地址在 video.playAddr（数组，元素字段是 src）
    var v = it.video;
    if (v) {
      var pa = v.playAddr || v.play_addr || [];
      var src = '';
      if (pa && pa.length) {
        for (var j = 0; j < pa.length && !src; j++) {
          if (pa[j] && pa[j].src) src = String(pa[j].src);
          else if (pa[j] && pa[j].url) src = String(pa[j].url);
        }
      }
      if (src) {
        item.videoUrl = src;
        item.durationSec = Math.round((Number(v.duration) || 0) / 1000);
      }
    }
    out.push(item);
  }

  // ---- 标题 / 作者 ----
  //
  // 【必须从 pace 数据里取，不能读 document.title】
  // pace 里的图片数据**来得很早**（页面骨架一出来就有），
  // 那一刻 `document.title` 还没设上 —— 于是会出现「46 张图都有了、标题却是空的」。
  // 直接在 pace 文本里抓 desc / nickname 最稳。
  function grab(re) {
    var m = host.match(re);
    if (!m) return '';
    var s = m[1];
    // 处理 JSON 转义
    try { return JSON.parse('"' + s + '"'); } catch (e) { return s; }
  }

  var title = grab(/"desc":"((?:[^"\\]|\\.)*)"/);
  if (!title) title = String(document.title || '').replace(/\s*-\s*抖音\s*$/, '').trim();

  var author = grab(/"nickname":"((?:[^"\\]|\\.)*)"/);
  if (!author) {
    // pace 里没有就退回 DOM：页面上有 19 个 /user/ 链接，只有 1 个是真作者 ——
    // 必须同时满足「非 self」「元素可见」「文本非空」
    var links = document.querySelectorAll('a[href*="/user/"]');
    for (var p = 0; p < links.length; p++) {
      var a = links[p];
      var href = a.getAttribute('href') || '';
      if (href.indexOf('self') > -1) continue;
      var t = String(a.textContent || '').trim();
      if (!t || t.length > 40) continue;
      if (!(a.offsetWidth || a.offsetHeight || a.getClientRects().length)) continue;
      author = t;
      break;
    }
  }

  return JSON.stringify({ images: out, title: title, author: author });
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
  static const String _noteDomScript = r'''
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
