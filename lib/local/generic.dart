import 'engine.dart';
import 'types.dart';

/// 通用适配器 —— 靠「内置 WebView 渲染 + 提取」覆盖新平台。
///
/// 【为什么需要它】
/// 实测主流平台（西瓜视频 / 今日头条 / 好看视频 / 豆瓣 / 贴吧 / 优酷 …）
/// 的网页**全是 SPA**：首页 HTML 只有几 KB 的空壳，数据全靠 JS 渲染出来，
/// 直接 HTTP 抓页面什么都拿不到。
///
/// 而我们的架构本来就有个隐藏 WebView —— 让页面**真的跑起来**，
/// 再读渲染后的 DOM 就行了。每个平台只需要填一组配置：
/// 域名、视频选择器、图片过滤规则。
///
/// 【它的边界，必须说清楚】
/// 通用适配器做不到平台专用适配器那么准（比如拿不到无水印原图、
/// 认不出动图）。所以：
///   · 抖音/小红书/B站/微博/快手/知乎 —— 用**专用适配器**（准确、能去水印）
///   · 其他平台 —— 先上通用适配器**保证能用**，之后再逐个做专用优化
///
/// 这是「覆盖广度」和「单平台质量」的取舍，我选了先有广度。
class GenericLocalPlatform extends LocalPlatform {
  GenericLocalPlatform({
    required this.key,
    required this.name,
    required this.hosts,
    required this.referer,
    this.videoSelector,
    this.imageAllow,
    this.minImageWidth = 300,
    this.titleSelector,
    this.authorSelector,
    this.settle = const Duration(milliseconds: 900),
    this.timeout = const Duration(seconds: 16),
  });

  @override
  final String key;

  @override
  final String name;

  @override
  final List<String> hosts;

  @override
  final String referer;

  /// 额外指定视频元素的选择器（默认全页找 `<video>`）
  final String? videoSelector;

  /// 图片域名白名单片段。为空则接受所有「尺寸够大」的图。
  final List<String>? imageAllow;

  /// 图片最小宽度（过滤图标、头像）
  final int minImageWidth;

  /// 标题 / 作者的选择器（拿不到就退回 `document.title`）
  final String? titleSelector;
  final String? authorSelector;

  final Duration settle;
  final Duration timeout;

  @override
  Future<LocalResult> parse(String url) async {
    final engine = LocalEngine.instance;
    // 用桌面 UA：这些平台的移动页往往更封闭，桌面页反而数据更全。
    await engine.setUserAgent(LocalEngine.desktopUa);

    // 【为什么要「稳定即收工」】通用适配器面对的是各种不认识的页面 ——
    // 有的内容很多、有的只有一张图、有的一张都没有（比如被反爬挡了）。
    // 原来只判断「有视频 或 ≥2 张图」，那么内容少的页面就得**白等满 16 秒超时**，
    // 用户看着进度条干等，体验很差。
    //
    // 现在加一条：数量连续几轮不变就认为加载完了，直接返回。
    // 这样「页面确实没什么内容」也能在 3 秒左右给用户一个明确结果，
    // 而不是让他等 16 秒。
    var lastKey = '';
    var stable = 0;

    final r = await engine.evaluatePolling(
      url,
      _script,
      settle: settle,
      interval: const Duration(milliseconds: 300),
      timeout: timeout,
      isDone: (v) {
        if (v is! Map) return false;
        final video = (v['videoUrl'] ?? '').toString();
        final imgs = v['images'];
        final n = imgs is List ? imgs.length : 0;

        // 有视频就够（视频是强信号，不用再等）
        if (video.isNotEmpty) return true;
        // 图够多也是强信号
        if (n >= 2) return true;

        // 弱信号：数量连续 4 轮没变（约 1.2 秒）就收工
        final key = '$n';
        if (key == lastKey) {
          stable++;
        } else {
          stable = 0;
        }
        lastKey = key;
        return stable >= 4;
      },
    );

    if (r is! Map) {
      throw LocalParseError('$name 页面没能读到内容 —— 可能是链接失效，或该页需要登录。');
    }

    final videoUrl = (r['videoUrl'] ?? '').toString();
    final rawImages = r['images'];
    final images = <LocalImage>[];
    if (rawImages is List) {
      for (final it in rawImages) {
        if (it is! Map) continue;
        final u = (it['url'] ?? '').toString();
        if (u.isEmpty) continue;
        images.add(LocalImage(
          url: u,
          width: (it['width'] as num?)?.toInt() ?? 0,
          height: (it['height'] as num?)?.toInt() ?? 0,
        ));
      }
    }

    if (videoUrl.isEmpty && images.isEmpty) {
      throw LocalParseError(
          '$name 这条内容里没有找到可下载的视频或图片。\n\n'
          '可能是链接类型不支持（比如首页/列表页），或者页面结构变了。');
    }

    final title = (r['title'] ?? '').toString();
    final author = (r['author'] ?? '').toString();

    return LocalResult(
      platform: key,
      platformName: name,
      type: videoUrl.isNotEmpty ? 'video' : 'images',
      title: title.isEmpty ? name : title,
      author: author,
      cover: (r['cover'] ?? '').toString().isNotEmpty
          ? r['cover'].toString()
          : (images.isNotEmpty ? images.first.url : ''),
      videoUrl: videoUrl,
      referer: referer,
      images: images,
      sourceUrl: url,
    );
  }

  String get _script {
    final allow = (imageAllow ?? const <String>[]).map((e) => "'$e'").join(',');
    final vs = videoSelector == null ? '' : "var __vs = '$videoSelector';";
    final ts = titleSelector == null ? '' : "var __ts = '$titleSelector';";
    final as = authorSelector == null ? '' : "var __as = '$authorSelector';";

    return r'''
(function () {
  var out = { images: [] };
  var allow = [''' + allow + r'''];
  ''' + vs + r'''
  ''' + ts + r'''
  ''' + as + r'''

  // ---- 标题 ----
  var title = '';
  if (typeof __ts !== 'undefined') {
    var te = document.querySelector(__ts);
    if (te) title = String(te.textContent || '').trim();
  }
  if (!title) {
    var h1 = document.querySelector('h1');
    if (h1) title = String(h1.textContent || '').trim();
  }
  if (!title) title = String(document.title || '').trim();
  out.title = title.replace(/\s+/g, ' ').slice(0, 100);

  // ---- 作者 ----
  var author = '';
  if (typeof __as !== 'undefined') {
    var ae = document.querySelector(__as);
    if (ae) author = String(ae.textContent || '').trim();
  }
  out.author = author.slice(0, 40);

  // ---- 视频：找 <video>，排除 blob:/data:（那些是 MSE，下不了）----
  var videoUrl = '';
  var vs = typeof __vs !== 'undefined'
      ? document.querySelectorAll(__vs)
      : document.querySelectorAll('video');
  for (var i = 0; i < vs.length && !videoUrl; i++) {
    var v = vs[i];
    var s = v.currentSrc || v.src || '';
    if (!s || s.indexOf('blob:') === 0 || s.indexOf('data:') === 0) continue;
    if (s.indexOf('http') !== 0) continue;
    videoUrl = s;
    out.cover = String(v.poster || '');
  }
  // 有些平台把地址放在 source 子标签上
  if (!videoUrl) {
    var ss = document.querySelectorAll('video source');
    for (var j = 0; j < ss.length && !videoUrl; j++) {
      var s2 = ss[j].src || '';
      if (s2.indexOf('http') === 0) videoUrl = s2;
    }
  }
  out.videoUrl = videoUrl;

  // ---- 图片：只留「够大」的，过滤图标/头像/表情 ----
  var seen = {}, imgs = [];
  var all = document.querySelectorAll('img');
  for (var k = 0; k < all.length; k++) {
    var el = all[k];
    var src = el.currentSrc || el.src || '';
    if (!src || src.indexOf('data:') === 0) continue;
    if (src.indexOf('http') !== 0) continue;
    if (el.naturalWidth && el.naturalWidth < ''' + minImageWidth.toString() + r''') continue;
    if (allow.length) {
      var okHost = false;
      for (var a = 0; a < allow.length; a++) {
        if (src.indexOf(allow[a]) > -1) { okHost = true; break; }
      }
      if (!okHost) continue;
    }
    // 排除常见的小图标/占位图
    if (/logo|icon|avatar|emoji|qrcode|sprite|blank|placeholder/i.test(src)) continue;
    if (seen[src]) continue;
    seen[src] = 1;
    imgs.push({ url: src, width: el.naturalWidth || 0, height: el.naturalHeight || 0 });
  }
  out.images = imgs;

  return JSON.stringify(out);
})()
''';
  }
}
