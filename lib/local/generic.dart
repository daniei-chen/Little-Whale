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
    this.failHint = '',
    this.expectVideo = false,
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

  /// 解析失败时追加的「这个平台特有的原因」。
  ///
  /// 通用适配器对任何站点都是同一套提取逻辑，但不同站点的失败原因差别很大：
  /// AcFun 给的是 HLS 流，皮皮虾的移动站直接是 APP 落地页。
  /// 空着的话用户只会看到「没有找到可下载的视频或图片」——
  /// 既不知道是谁的问题，也不知道该不该再试。
  final String failHint;

  /// 这个平台的作品**一定是视频**（已知）。
  ///
  /// 实测 AcFun：播放器要 5 秒以上才把 src 挂上来，在那之前页面已经有
  /// 十几张缩略图 —— 「图 >= 2 就收工」会把它判成图文，同一链接这次报 HLS、
  /// 下次报「图文 11 张」，行为不稳定。标了 expectVideo 就**先等播放器**，
  /// 等不到再按 HLS/没有内容来解释。
  final bool expectVideo;

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
    final t0 = DateTime.now();

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

        // 有可下载的视频地址就够（最强信号，不用再等）
        if (video.isNotEmpty) return true;

        // 【已知是视频站 → 先把播放器等出来】
        // AcFun 实测：同一链接有时 1.8 秒报「图文」、有时 5 秒报「HLS」——
        // 因为播放器的 src 挂上来之前，页面已经有十几张缩略图。
        // 这类平台先等 6 秒，等不到再按 HLS / 没有内容来解释，行为才稳定。
        if (expectVideo) {
          return DateTime.now().difference(t0) > const Duration(seconds: 6);
        }

        // 【有播放器但还没拿到地址 → 再等一小会儿】
        // 实测（AcFun 作品页）：播放器起来之前，页面已经有 11 张缩略图
        // （封面 + 推荐位），旧逻辑「图 ≥ 2 就收工」会把它判成「图文 11 张」，
        // 用户点保存会存下一堆不相干的缩略图。
        // 现在：只要页面上有 <video> 元素，就说明这是视频页，给它 2.5 秒把地址挂上来。
        if (v['hasVideoEl'] == true) {
          return DateTime.now().difference(t0) > const Duration(milliseconds: 2500);
        }

        // 完全没有播放器 → 图够多就是图文作品
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

    // 【已知是视频站 → 拿不到视频就是拿不到，别拿缩略图充数】
    // AcFun 实测：播放器没起来时页面有十几张缩略图，如果按「有图就是图文」
    // 返回，用户会存到一堆封面和推荐位。这个站的作品只有视频这一种形态，
    // 所以明确报「拿不到可下载的视频」并带上平台特有的原因。
    if (expectVideo && videoUrl.isEmpty) {
      throw LocalParseError(
          '$name 这条作品没拿到可下载的视频地址。\n\n'
          '${failHint.isNotEmpty ? failHint : '可能是播放器还没加载出来，稍后重试一次。'}');
    }
    // 【流式视频优先判定】页面只有 m3u8 时，那些 <img> 多半是封面、推荐位缩略图。
    // 实测 AcFun 作品页：videoUrl 为空、images 抓到 11 张（全是缩略图），
    // 于是被判成「图文 11 张」—— 用户点保存会存下一堆不相干的图。
    // 明确说「不支持保存这个流」比给一堆垃圾强。
    if (videoUrl.isEmpty && r['hlsOnly'] == true) {
      throw LocalParseError(
          '$name 这条视频是 HLS 流式格式（m3u8 分段流），App 暂不支持直接保存。\n\n'
          '不是链接的问题 —— 平台把视频切成了几百个小片段，保存下来也不是能直接播放的文件。');
    }
    if (videoUrl.isEmpty && images.isEmpty) {
      throw LocalParseError(
          '$name 这条内容里没有找到可下载的视频或图片。\n\n'
          '${failHint.isNotEmpty ? failHint : '可能是链接类型不支持（比如首页/列表页），或者页面结构变了。'}');
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
    // 平台展示名（用于「标题全是站点名」时生成中性占位，如「微视视频」）。
    // 必须像 __ts 一样自己带引号 —— 上一版我写成了 `''' + name + r'''`，
    // raw 字符串不会补引号，生成出来是 `var __sn = 微视;`，整个探针脚本直接语法错误。
    final sn = "var __sn = '${name.replaceAll(RegExp(r"['\\]"), '')}';";
    final as = authorSelector == null ? '' : "var __as = '$authorSelector';";

    return r'''
(function () {
  var out = { images: [] };
  var allow = [''' + allow + r'''];
  ''' + vs + r'''
  ''' + ts + r'''
  ''' + as + r'''

  // ---- 标题 ----
  //
  // 【v0.1.1 修正：`document.title` 往往只是站点名】
  // 实测（2026-11，模拟器 + 真实页面）：
  //   优酷   ->「高清完整正版视频在线观看-优酷」
  //   爱奇艺 ->「爱奇艺-在线视频网站-海量正版高清视频在」
  //   好看视频 ->「好看视频-轻松有收获」
  // 这些都不是作品标题 —— 用户保存下来的文件名就是这句广告语。
  // 现在的顺序：页面标题节点 → h1 → og:title → 描述 → document.title，
  // 并且在每一步都检查「像不像站点标语」，像就继续往下找。
  function metaOf(p) {
    var el = document.querySelector('meta[property="' + p + '"]') ||
             document.querySelector('meta[name="' + p + '"]');
    return el ? String(el.getAttribute('content') || '').trim() : '';
  }
  // 站点标语的特征词（不是作品标题）
  // 【站点名清单】这些词出现在标题里，说明拿到的是「站点名」而不是作品名。
  // 实测微视的作品页：h1 / og:title 全是「腾讯微视」，直接显示给用户就是
  // 一条叫「腾讯微视」的视频 —— 比没有标题还糟。
  ''' + sn + r'''
  var SITE_NOISE = /(在线观看|海量正版|高清完整|官方网站|视频网站|轻松有收获|正版高清|免费在线|首页_|_首页|腾讯微视|微视|西瓜视频|今日头条|好看视频|虎牙直播|斗鱼直播|爱奇艺|优酷|腾讯视频|芒果TV|秒拍|最右|皮皮虾|AcFun|哔哩哔哩|bilibili)/i;

  var title = '';
  if (typeof __ts !== 'undefined') {
    var te = document.querySelector(__ts);
    if (te) title = String(te.textContent || '').trim();
  }
  if (!title) {
    var h1 = document.querySelector('h1');
    if (h1) title = String(h1.textContent || '').trim();
  }
  if (!title || SITE_NOISE.test(title)) {
    var ogTitle = metaOf('og:title');
    if (ogTitle && ogTitle.length >= 4) title = ogTitle;
  }
  if (!title || SITE_NOISE.test(title)) {
    var desc = metaOf('description');
    if (desc && desc.length >= 8) title = desc;
  }
  if (!title) title = String(document.title || '').trim();

  // 去掉尾部的「- 站点名」后缀（比整句当标题可读得多）
  // 先 trim 再替换：`innerText` 常带尾随空白，`$` 锚点会因此匹配不上
  title = title.trim();

  // 【AcFun 这类站会把 SEO 关键词拼进标题】
  // 实测（2026-11）：`喀山冰演run the girls,,null,A站,AcFun,ACG,弹幕,视频,动画,…`
  // —— 标题本身是对的，后面接了一长串站点关键词和一个字面量的 "null"。
  // 判据：逗号 ≥ 4 段且含站点关键词 → 只留第一段（正常作品标题不会有这种形态）。
  if (title.split(',').length >= 5 &&
      /(acfun|A站|弹幕|鬼畜|新番|二次元|ACG|秒拍|最右|皮皮虾)/i.test(title)) {
    title = title.split(',')[0].trim();
  }
  // 顺手清掉悬挂的 `null` 与连续逗号（不是所有站都会走上面那条分支）
  title = title.replace(/,{2,}/g, ',').replace(/,?\bnull\b,?/gi, ',').trim();
  title = title.replace(/^[,\s]+|[,\s]+$/g, '');
  // 兜底：仍然超长且逗号很多 → 取第一段（宁可短，也不要半屏垃圾）
  if (title.length > 80 && title.indexOf(',') > 10) {
    title = title.split(',')[0].trim();
  }

  title = title.replace(/\s*[-_|｜]\s*[^-_|｜]{1,12}\s*$/, '').trim();
  // 【全链条都命中站点名时的兜底】说明这个页面既没有可用的 h1、og:title 也是
  // 站点名、description 也带站点词。与其把「腾讯微视」当成作品名显示，不如
  // 用一个中性占位 —— 用户至少知道「没抓到标题」，而不是以为作品就叫这个名字。
  if (!title || SITE_NOISE.test(title) || title.length < 4) {
    var brand = '';
    try {
      var host = String(location.hostname || '').replace(/^www\./, '');
      var parts = host.split('.');
      brand = parts.length >= 2 ? parts[parts.length - 2] : host;
    } catch (e) { brand = ''; }
    var siteLabel = (typeof __sn !== 'undefined' && __sn) ? __sn : (brand || '该站点');
    title = siteLabel + '视频';
  }
  out.title = title.replace(/\s+/g, ' ').slice(0, 100);

  // ---- 作者 ----
  //
  // 【为什么不能只靠 authorSelector】那个要平台配置，而 16 个通用平台里
  // 大多数没配（也配不准 —— 各站的作者节点 class 名完全不同）。
  // 实测皮皮虾的作品页作者是空的，但页面上明明写着「超爱吃芋泥～」。
  // 这里按可靠度依次找：配置的选择器 → `meta author` → 带 `/user/` 的链接
  // → `@` 开头的叶节点（B站/抖音/皮皮虾这类站都这么展示作者）。
  function metaOf2(p) {
    var el = document.querySelector('meta[property="' + p + '"]') ||
             document.querySelector('meta[name="' + p + '"]');
    return el ? String(el.getAttribute('content') || '').trim() : '';
  }

  var author = '';
  if (typeof __as !== 'undefined') {
    var ae = document.querySelector(__as);
    if (ae) author = String(ae.textContent || '').trim();
  }
  if (!author || author.length > 40) {
    author = metaOf2('author') || metaOf2('article:author') || '';
  }
  if (!author || author.length > 40) {
    // 指向用户主页的链接，文本通常就是昵称
    var uls = document.querySelectorAll('a[href*="/user/"], a[href*="/profile/"], a[href*="/u/"]');
    for (var ai = 0; ai < uls.length; ai++) {
      var a = uls[ai];
      if ((a.getAttribute('href') || '').indexOf('self') > -1) continue;
      var tx = String(a.textContent || '').replace(/\s+/g, ' ').trim();
      if (!tx || tx.length > 40) continue;
      if (!(a.offsetWidth || a.offsetHeight || a.getClientRects().length)) continue;
      author = tx;
      break;
    }
  }
  if (!author || author.length > 40) {
    // `@昵称` 形态
    var els = document.querySelectorAll('span, div, a, p, strong');
    for (var zi = 0; zi < els.length; zi++) {
      var el2 = els[zi];
      if (el2.children.length > 0) continue;
      var s3 = String(el2.textContent || '').replace(/\s+/g, ' ').trim();
      if (s3.length < 2 || s3.length > 30) continue;
      if (s3.charAt(0) !== '@') continue;
      if (!(el2.offsetWidth || el2.offsetHeight)) continue;
      author = s3.replace(/^@/, '').trim();
      break;
    }
  }
  if (!author || author.length > 40) {
    // 最后一招：class/data 属性里带 author / user / nickname 的元素。
    // 实测皮皮虾的作品页，昵称就是这样一个节点（既不在 <a href="/user/"> 里、
    // 也不带 @ 前缀），前面几级都抓不到。
    // 加严格过滤，避免抓到「作者推荐」「相关用户」这类标签文字。
    var cands = document.querySelectorAll(
      '[data-author], [data-nickname], [class*="author" i], [class*="nickname" i], [class*="user-name" i], [class*="userName" i]'
    );
    for (var ci = 0; ci < cands.length; ci++) {
      var c = cands[ci];
      if (c.children.length > 0) continue;
      var t4 = String(c.textContent || '').replace(/\s+/g, ' ').trim();
      if (t4.length < 2 || t4.length > 24) continue;
      if (!(c.offsetWidth || c.offsetHeight)) continue;
      // 过滤明显的标签/按钮文案
      if (/^(作者|关注|已关注|粉丝|关注作者|作者推荐|更多|展开|收起|举报|分享)$/.test(t4)) continue;
      if (/^(作者|关注|粉丝|推荐|相关)/.test(t4)) continue;
      author = t4;
      break;
    }
  }
  out.author = author.slice(0, 40);

  // ---- 视频：找 <video>，排除 blob:/data:（那些是 MSE，下不了）----
  //
  // 【还必须排除 m3u8】实测（2026-11，AcFun 作品页）`<video>` 的 src 是
  // `https://tx-safety-video.acfun.cn/.../xxx-hls_1080p_h264_60_1.m3u8` ——
  // 那是一份**播放列表文本**，不是视频文件。直接下载会得到一个几 KB 的文本，
  // 相册打不开，用户却以为存成功了。宁可明确说「这是流式视频，暂不支持」。
  var videoUrl = '';
  var sawHls = false;
  var vs = typeof __vs !== 'undefined'
      ? document.querySelectorAll(__vs)
      : document.querySelectorAll('video');
  for (var i = 0; i < vs.length && !videoUrl; i++) {
    var v = vs[i];
    var s = v.currentSrc || v.src || '';
    if (!s || s.indexOf('blob:') === 0 || s.indexOf('data:') === 0) continue;
    if (s.indexOf('http') !== 0) continue;
    if (s.indexOf('.m3u8') > -1 || s.indexOf('mime_type=m3u8') > -1) { sawHls = true; continue; }
    videoUrl = s;
    out.cover = String(v.poster || '');
  }
  // 有些平台把地址放在 source 子标签上
  if (!videoUrl) {
    var ss = document.querySelectorAll('video source');
    for (var j = 0; j < ss.length && !videoUrl; j++) {
      var s2 = ss[j].src || '';
      if (s2.indexOf('http') !== 0) continue;
      if (s2.indexOf('.m3u8') > -1) { sawHls = true; continue; }
      videoUrl = s2;
    }
  }
  out.videoUrl = videoUrl;
  out.hlsOnly = !videoUrl && sawHls;
  // 「页面上有没有播放器」—— 轮询靠它区分「这是视频页，再等等」和「这就是图文」
  out.hasVideoEl = vs.length > 0;

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

  // ---- 封面兜底 ----
  // `<video poster>` 为空时（很多站根本不写这个属性）退到 og:image 或首图，
  // 否则历史记录卡片会是一块空白。实测皮皮虾的作品页就是这种：有视频、有封面
  // 大图，但 poster 属性是空的。
  if (!out.cover) {
    var ogi = '';
    try { ogi = metaOf2('og:image'); } catch (e) {}
    if (ogi && ogi.indexOf('http') === 0) out.cover = ogi;
  }
  if (!out.cover && imgs.length > 0) out.cover = imgs[0].url;

  return JSON.stringify(out);
})()
''';
  }
}
