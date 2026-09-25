
import 'engine.dart';
import 'types.dart';

/// 知乎 · 本地解析
///
/// 【能做什么、不能做什么 —— 如实说明】
/// 实测：
///   · **专栏文章** `zhuanlan.zhihu.com/p/{id}` —— **不需要登录**，页面标题、
///     作者、正文图片都能拿到（数据在 `js-initialData` 里，但直接从 DOM 抠更稳）。
///   · **回答页** `zhihu.com/question/{qid}/answer/{aid}` —— 未登录会被
///     302 到 `/signin?next=...`，拿不到内容。这是知乎的策略，不是我们没做。
///
/// 所以这里对回答页给出**明确提示**（告诉用户去知乎 App 里复制专栏链接，
/// 而不是含糊地说「失败了」——用户不知道该干什么。
class ZhihuLocalPlatform extends LocalPlatform {
  @override
  String get key => 'zhihu';

  @override
  String get name => '知乎';

  @override
  List<String> get hosts => const ['zhihu.com', 'zhimg.com'];

  @override
  String get referer => 'https://www.zhihu.com/';

  static final _articleRe = RegExp(r'zhuanlan\.zhihu\.com/p/(\d+)');
  static final _answerRe = RegExp(r'/question/(\d+)/answer/(\d+)');
  static final _pinRe = RegExp(r'zhihu\.com/pin/(\d+)');
  static final _zvideoRe = RegExp(r'/zvideo/(\d+)');

  /* ------------------------------------------------------------------ */

  @override
  Future<LocalResult> parse(String url) async {
    final engine = LocalEngine.instance;
    await engine.setUserAgent(LocalEngine.desktopUa);

    // 知乎视频（zvideo）单独给提示。
    //
    // 实测：知乎未登录时**拿不到任何视频内容** —— 首页 SSR 里出现的 `zvideo`
    // 全是空的 store 命名空间（`"zvideos":{}`），相关接口清一色
    // 401「身份未经过验证」。这是平台的登录策略，不是我们没做。
    //
    // 与其让用户看到含糊的「不支持这个链接」，不如直接说清楚该怎么办。
    if (_zvideoRe.hasMatch(url)) {
      throw const LocalParseError(
        '知乎视频需要登录才能看 —— 未登录时知乎不返回任何视频内容。\n\n'
        '知乎上**不需要登录**的只有专栏文章：\n'
        'zhuanlan.zhihu.com/p/…\n'
        '在知乎 App 里：进作者主页 → 文章 → 选一篇 → 分享 → 复制链接。',
      );
    }

    final isAnswer = _answerRe.hasMatch(url);

    var lastKey = '';
    var stable = 0;

    final r = await engine.evaluatePolling(
      url,
      _probeScript(_articleRe.firstMatch(url)?.group(1) ??
          _pinRe.firstMatch(url)?.group(1) ??
          ''),
      settle: const Duration(milliseconds: 1500),
      interval: const Duration(milliseconds: 300),
      timeout: const Duration(seconds: 18),
      isDone: (v) {
        if (v is! Map) return false;
        // 撞上登录墙就没必要再等
        if (v['needLogin'] == true) return true;
        final imgs = v['images'];
        final n = imgs is List ? imgs.length : 0;
        if (n == 0) return false;
        final key = '$n';
        if (key == lastKey) {
          stable++;
        } else {
          stable = 0;
        }
        lastKey = key;
        return stable >= 2;
      },
    );

    if (r is! Map) {
      throw const LocalParseError('知乎页面没能读到内容，可能链接已失效。');
    }

    if (r['needLogin'] == true) {
      throw LocalParseError(
        isAnswer
            ? '知乎的**回答页**未登录打不开 —— 知乎要求登录才能看回答。\n\n'
                '换个**专栏文章**的链接就行（zhuanlan.zhihu.com/p/…），那个不需要登录。\n'
                '在知乎 App 里：进作者主页 → 文章 → 选一篇 → 分享 → 复制链接。'
            : '知乎要求登录后才能看这个页面。\n\n'
                '试试专栏文章（zhuanlan.zhihu.com/p/…），那个不需要登录。',
      );
    }

    final rawImages = r['images'];
    final images = <LocalImage>[];
    if (rawImages is List) {
      for (final it in rawImages) {
        if (it is! Map) continue;
        final u = (it['url'] ?? '').toString();
        if (u.isEmpty) continue;
        images.add(LocalImage(
          url: _toOriginal(u),
          width: (it['width'] as num?)?.toInt() ?? 0,
          height: (it['height'] as num?)?.toInt() ?? 0,
        ));
      }
    }

    final videoUrl = (r['videoUrl'] ?? '').toString();
    if (images.isEmpty && videoUrl.isEmpty) {
      // 区分「打开的不是我们请求的那一页」和「页面里确实没有媒体」——
      // 前者说明链接失效（知乎会把不存在的回答渲染成一个推荐页），
      // 后者只是这篇没有图。混在一起说会让用户以为链接坏了。
      final href = (r['href'] ?? '').toString();
      final wanted = _articleRe.firstMatch(url)?.group(1) ??
          _answerRe.firstMatch(url)?.group(2) ??
          _pinRe.firstMatch(url)?.group(1) ??
          '';
      if (wanted.isNotEmpty && href.isNotEmpty && !href.contains(wanted)) {
        throw const LocalParseError('这条知乎链接打不开 —— 内容可能已删除，或者链接不完整。');
      }
      throw const LocalParseError('这篇知乎内容里没有可下载的图片或视频。');
    }

    return LocalResult(
      platform: key,
      platformName: name,
      type: videoUrl.isNotEmpty && images.isEmpty ? 'video' : 'images',
      title: (r['title'] ?? '').toString(),
      author: (r['author'] ?? '').toString(),
      cover: images.isNotEmpty ? images.first.url : '',
      videoUrl: videoUrl,
      referer: referer,
      images: images,
      sourceUrl: url,
    );
  }

  /// 知乎图片去掉尺寸后缀就是原图。
  ///
  /// 页面里给的是 `..._1440w.jpg`、`..._720w.webp` 这类**压缩过的展示尺寸**，
  /// 把 `_1440w` 这类后缀去掉才是原始上传的那张。
  String _toOriginal(String url) {
    // 【必须先把查询串摘掉】知乎的图片地址常带 `?source=xxx` 这种跟踪参数，
    // 而「去掉尺寸后缀」的正则要求以扩展名**结尾** —— 带着查询串就永远匹配不上，
    // 于是用户拿到的还是 _1440w 的压缩图（踩过）。
    final q = url.indexOf('?');
    final path = q >= 0 ? url.substring(0, q) : url;

    final m = RegExp(
            r'^(https?://[^/]*(?:zhimg\.com|zhihu\.com)/.*?)_(\d+w|r|b|q\d+)(\.(?:jpg|jpeg|png|webp|gif))$',
            caseSensitive: false)
        .firstMatch(path);
    if (m != null) return '${m.group(1)}${m.group(3)}';
    return path; // 跟踪参数没有保留价值
  }

  /* ------------------------------------------------------------------ */

  /// 直接从 DOM 抠 —— 比解析 6 万字节的 `js-initialData` 稳得多，
  /// 而且知乎的 JSON 结构改过好几版。
  static String _probeScript(String id) => r'''
(function () {
  var href = String(window.location.href);

  // 撞上登录墙就早点说，别让用户干等
  if (/\/signin/.test(href)) {
    return JSON.stringify({ needLogin: true, images: [] });
  }

  // ---- 标题 ----
  var title = '';
  var h1 = document.querySelector('h1');
  if (h1) title = String(h1.textContent || '').trim();
  if (!title) {
    var el = document.querySelector('[class*="Title"], [class*="title"]');
    if (el) title = String(el.textContent || '').trim();
  }
  title = title.replace(/\s*-\s*知乎\s*$/, '').trim().slice(0, 100);

  // ---- 作者 ----
  var author = '';
  var a = document.querySelector('[class*="AuthorInfo"] a, .AuthorInfo-name a, [itemprop="author"]');
  if (a) author = String(a.textContent || '').trim().slice(0, 40);
  if (!author) {
    var meta = document.querySelector('meta[itemprop="name"], meta[name="author"]');
    if (meta) author = String(meta.getAttribute('content') || '').trim().slice(0, 40);
  }

  // ---- 正文图片 ----
  //
  // 【判据要严】只认知乎图床 **并且路径要真的像图片**。
  // 只按域名过滤会误伤：曾经把页面自身的地址
  // `https://zhuanlan.zhihu.com/p/28852607` 当成了首图 ——
  // 它同样含 "zhihu.com"。所以这里额外要求 URL 以图片后缀结尾。
  var seen = {}, images = [];
  var all = document.querySelectorAll('img');
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    // 知乎把原图放在 data-original / data-actualsrc 上，src 是缩略图
    var src = el.getAttribute('data-original') ||
              el.getAttribute('data-actualsrc') ||
              el.currentSrc || el.src || '';
    if (!src || src.indexOf('data:') === 0) continue;
    // 域名收紧到**内容图床 zhimg.com**：
    // 正文图都在 pic1/pic2/pic3.zhimg.com，而界面资源在 static.zhihu.com ——
    // 只写 "zhihu.com" 会把知乎自己的分享 logo 当成首图（踩过）。
    if (!/^https?:\/\/[a-z0-9.-]*zhimg\.com\//i.test(src)) continue;
    if (el.naturalWidth && el.naturalWidth < 200) continue;
    if (seen[src]) continue;
    seen[src] = 1;
    images.push({ url: src, width: el.naturalWidth || 0, height: el.naturalHeight || 0 });
  }

  // ---- 视频 ----
  var videoUrl = '';
  var vs = document.querySelectorAll('video');
  for (var k = 0; k < vs.length && !videoUrl; k++) {
    var v = vs[k];
    var s = v.currentSrc || v.src || '';
    if (s && s.indexOf('blob:') !== 0 && s.indexOf('http') === 0) videoUrl = String(s);
  }

  return JSON.stringify({
    href: href.slice(0, 160),
    title: title,
    author: author,
    images: images,
    videoUrl: videoUrl,
    needLogin: false
  });
})()
''';
}
