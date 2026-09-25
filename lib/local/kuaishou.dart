import 'engine.dart';
import 'types.dart';

/// 快手 · 本地解析（不需要服务器）
///
/// 【入口很关键 —— 和抖音是同一个教训】
/// 服务端那套用 PC 站访问，被识别成「浏览器版本过低」，一直是下线状态。
/// 换成**手机 UA 打开 v.kuaishou.com 短链**就通了：会跳到
/// `v.m.chenzhongtech.com/fw/photo/{id}` 这个面向分享场景的页面，
/// `<video>` 元素上**直接挂着可下载的 mp4 地址**（实测拿到
/// `.../photo-video-mz/5243597543753940027_....mp4`）。
///
/// 所以这里不逆向任何接口，只做一件服务端做不到的事：用手机的身份打开分享页。
class KuaishouLocalPlatform extends LocalPlatform {
  @override
  String get key => 'kuaishou';

  @override
  String get name => '快手';

  @override
  List<String> get hosts => const [
        'kuaishou.com',
        'chenzhongtech.com',
        'gifshow.com',
      ];

  @override
  String get referer => 'https://v.m.chenzhongtech.com/';

  /* ------------------------------------------------------------------ */

  @override
  Future<LocalResult> parse(String url) async {
    final engine = LocalEngine.instance;
    // 必须用手机 UA：PC 身份会被快手判成「浏览器版本过低」直接拒绝
    await engine.setUserAgent(LocalEngine.mobileUa);
    try {
      var r = await _probe(url, const Duration(seconds: 18));

      // 【为什么要重试一次】快手偶尔会返回一个**降级页面** ——
      // 页面能打开、封面图也在，但 `<video>` 是空的，视频地址就拿不到。
      // 表现是「一条视频作品被解析成图集」，而且是偶发的（同一链接时好时坏）。
      // 所以：只拿到图、没有视频时，等一会儿重新打开一次。
      // 真的图集作品第二次结果一样，不会误判成视频。
      if (r != null && r.videoUrl.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 900));
        final retry = await _probe(url, const Duration(seconds: 12));
        if (retry != null && retry.videoUrl.isNotEmpty) r = retry;
      }

      if (r == null) {
        throw const LocalParseError(
            '快手这次没返回内容。可能是作品已删除，或这条分享链接已失效。');
      }
      if (r.videoUrl.isEmpty && r.images.isEmpty) {
        throw const LocalParseError('这条快手作品没有可下载的内容。');
      }

      return r;
    } finally {
      // 还原，别污染后面的平台（抖音图文必须用桌面 UA）
      await engine.setUserAgent(LocalEngine.desktopUa);
    }
  }

  /// 打开一次分享页并解析。拿不到内容返回 null。
  Future<LocalResult?> _probe(String url, Duration timeout) async {
    var lastUrl = '';
    var stable = 0;
    var sawSomething = false;

    final r = await LocalEngine.instance.evaluatePolling(
      url,
      _probeScript,
      settle: const Duration(milliseconds: 1800),
      interval: const Duration(milliseconds: 300),
      timeout: timeout,
      isDone: (v) {
        if (v is! Map) return false;
        final video = (v['videoUrl'] ?? '').toString();
        final imgs = v['images'];
        final hasImg = imgs is List && imgs.isNotEmpty;
        if (video.isEmpty && !hasImg) return false;

        sawSomething = true;
        final key = video.isNotEmpty ? video : 'images:${(imgs as List).length}';
        if (key == lastUrl) {
          stable++;
        } else {
          stable = 0;
        }
        lastUrl = key;
        // 地址稳定两轮就收工，别让播放器切清晰度把时间拖满
        return stable >= 2;
      },
    );

    if (!sawSomething || r is! Map) return null;

    final videoUrl = (r['videoUrl'] ?? '').toString();
    final rawImages = r['images'];

    final images = <LocalImage>[];
    if (rawImages is List) {
      for (final it in rawImages) {
        if (it is! Map) continue;
        final u = (it['url'] ?? '').toString();
        if (u.isEmpty) continue;
        images.add(LocalImage(url: u));
      }
    }

    // 【有视频就以视频为准】快手的分享页上也会有封面图、推荐位配图，
    // 它们同样带真实尺寸、能通过图片筛选 —— 早先按「有图就算图集」判断，
    // 结果一条视频作品被识别成了「图集 2 张」。视频存在时优先级最高。
    return LocalResult(
      platform: key,
      platformName: name,
      type: videoUrl.isNotEmpty ? 'video' : 'images',
      title: (r['title'] ?? '').toString(),
      author: (r['author'] ?? '').toString(),
      cover: images.isNotEmpty ? images.first.url : '',
      videoUrl: videoUrl,
      referer: referer,
      images: images,
      sourceUrl: url,
    );
  }

  /// 手机分享页的探针。
  ///
  /// 核心是 `<video>` 的 src —— 排除 `blob:`（MSE，不可下载）。
  /// 图集作品则从页面里的图片里挑（快手的图集会把原图挂在 img 上）。
  static const String _probeScript = r'''
(function () {
  function good(u) {
    if (!u) return false;
    u = String(u);
    if (u.indexOf('blob:') === 0) return false;
    if (u.indexOf('data:') === 0) return false;
    return u.indexOf('http') === 0;
  }

  // ---- 视频 ----
  var videoUrl = '';
  var vs = document.querySelectorAll('video');
  for (var i = 0; i < vs.length && !videoUrl; i++) {
    var v = vs[i];
    if (good(v.currentSrc)) videoUrl = String(v.currentSrc);
    else if (good(v.src)) videoUrl = String(v.src);
    if (!videoUrl) {
      var ss = v.querySelectorAll('source');
      for (var k = 0; k < ss.length; k++) {
        if (good(ss[k].src)) { videoUrl = String(ss[k].src); break; }
      }
    }
  }

  // ---- 图集 ----
  // 快手的作品图挂在 kwimgs / kwaicdn 这类域名上，且带真实尺寸
  var seen = {}, images = [];
  var all = document.querySelectorAll('img');
  for (var j = 0; j < all.length; j++) {
    var el = all[j];
    var src = el.currentSrc || el.src || '';
    if (!src || src.indexOf('data:') === 0) continue;
    if (!/kwimgs|kwaicdn|ksurl|ndcimgs|kuaishou/.test(src)) continue;
    if (el.naturalWidth < 200) continue;   // 头像、图标都不够大
    if (seen[src]) continue;
    seen[src] = 1;
    images.push({ url: src, width: el.naturalWidth || 0, height: el.naturalHeight || 0 });
  }

  // ---- 文案 / 作者 ----
  function meta(prop) {
    var m = document.querySelector('meta[property="' + prop + '"]') ||
            document.querySelector('meta[name="' + prop + '"]');
    return m ? String(m.getAttribute('content') || '') : '';
  }
  var title = meta('og:title') || meta('description') || '';
  title = title.replace(/\s*-\s*快手\s*$/, '').trim();
  if (!title) {
    var h = document.querySelector('h1, [class*="caption"], [class*="desc"]');
    if (h) title = String(h.textContent || '').trim().slice(0, 80);
  }

  var author = meta('og:author') || '';
  if (!author) {
    var els = document.querySelectorAll('span, div, a');
    for (var n = 0; n < els.length && n < 400; n++) {
      var e2 = els[n];
      if (e2.children.length > 0) continue;
      var t = String(e2.textContent || '').trim();
      if (t.length < 2 || t.length > 24) continue;
      if (t.charAt(0) !== '@') continue;
      if (!(e2.offsetWidth || e2.offsetHeight)) continue;
      author = t.replace(/^@/, '');
      break;
    }
  }

  return JSON.stringify({
    videoUrl: videoUrl,
    images: images,
    title: title,
    author: author
  });
})()
''';
}
