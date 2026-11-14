/// 抖音作品数据的**纯解析层**。
///
/// 【为什么要单独抽一层】
/// 抖音的解析有两次「翻车」的经历：
///   1. 视频只认 `<video>` 元素 —— 页面不给 `<video>`（改渲染方式、被风控降级）就直接失败；
///   2. 图文只认 `__pace_f` 里 `"images":[{"width"` 这一种形态 —— 字段顺序一变就全军覆没。
///
/// 这两件事的共同点是：**数据其实拿到了，只是没认出来**。
/// 所以这里把「怎么从各种形态里认出作品数据」全部写成纯函数：
///   · 不碰网络、不碰 WebView、不依赖 Flutter —— 可以用真实页面数据做单元测试
///   · 每个入口（`_ROUTER_DATA` / 接口 JSON / `__pace_f` / DOM）都能独立验证
///
/// 上层 `douyin.dart` 只负责「把数据取回来」，判断逻辑都在这儿。
library;

import 'dart:convert';

/// 图文作品里的一张图（也可能是动图）
class DouyinImage {
  final String url;
  final int width;
  final int height;

  /// 动图对应的短视频地址（带音轨）。非动图为空。
  final String videoUrl;
  final int durationSec;

  const DouyinImage({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.videoUrl = '',
    this.durationSec = 0,
  });

  bool get isLive => videoUrl.isNotEmpty;

  @override
  String toString() =>
      'DouyinImage(${width}x$height${isLive ? ' live' : ''})';
}

/// 一个抖音作品（视频或图文）的统一形态
class DouyinAweme {
  final String awemeId;
  final String desc;
  final String author;
  final String cover;
  final int durationSec;

  /// `video.play_addr.uri` —— 无水印播放接口要的就是它
  final String videoId;

  /// 页面直接给出的播放地址（通常是带水印的 `playwm`）
  final List<String> playUrls;

  /// 图文作品的图片列表（视频作品为空）
  final List<DouyinImage> images;

  final int createTime;
  final String musicName;

  /// 视频的像素尺寸（有就填，用于展示清晰度）
  final int width;
  final int height;

  /// 这份数据是从哪个入口拿到的，排障时很有用
  final String source;

  const DouyinAweme({
    this.awemeId = '',
    this.desc = '',
    this.author = '',
    this.cover = '',
    this.durationSec = 0,
    this.videoId = '',
    this.playUrls = const [],
    this.images = const [],
    this.createTime = 0,
    this.musicName = '',
    this.width = 0,
    this.height = 0,
    this.source = '',
  });

  bool get isImages => images.isNotEmpty;
  bool get hasVideo => videoId.isNotEmpty || playUrls.isNotEmpty;
  int get imageCount => images.length;
  bool get hasLivePhotos => images.any((e) => e.isLive);

  /// 这份数据够不够交差
  bool get usable => isImages || hasVideo;

  DouyinAweme copyWith({String? source}) => DouyinAweme(
        awemeId: awemeId,
        desc: desc,
        author: author,
        cover: cover,
        durationSec: durationSec,
        videoId: videoId,
        playUrls: playUrls,
        images: images,
        createTime: createTime,
        musicName: musicName,
        width: width,
        height: height,
        source: source ?? this.source,
      );
}

/// 抖音数据提取器 —— 全部是纯函数
class DouyinParser {
  DouyinParser._();

  /// 图片 CDN 白名单：只认这两个域，避免把 UI 图标/头像当作品图
  static bool isDouyinImageHost(String url) =>
      url.contains('douyinpic.com') ||
      url.contains('byteimg.com') ||
      url.contains('douyin.com/tos-cn-i');

  /* ------------------------------------------------------------------ */
  /* 入口 1：`_ROUTER_DATA` —— 手机分享页渲染后带着完整作品数据            */
  /* ------------------------------------------------------------------ */

  /// 【这是目前最可靠的视频入口，实测确认】
  ///
  /// 手机 UA 打开 `www.douyin.com/video/{id}` 会 302 到 `m.douyin.com/share/video/{id}?share_sign=…`。
  /// 页面 SSR 输出是空壳（直接 HTTP 抓只有 layout），但**页面自己的 JS 跑完之后**，
  /// `window._ROUTER_DATA.loaderData["video_(id)/page"].videoInfoRes.item_list[0]`
  /// 里就是一份完整的 aweme 对象：desc / author.nickname / video.play_addr /
  /// cover / create_time / duration 全都有。
  ///
  /// 比读 `<video>` 元素强的地方：不依赖播放器真的挂载（不用等视频起播）、
  /// 能一次拿到标题作者时长封面，而且 `play_addr.uri` 直接就是无水印接口的 video_id。
  static DouyinAweme? fromRouterData(dynamic routerData) {
    final rd = _asMap(routerData);
    if (rd == null) return null;

    // 结构：{ loaderData: { "video_(id)/page": { videoInfoRes: { item_list: [...] } } } }
    // 键名带动态的 "(id)"，所以遍历而不是硬编码。
    final loader = _asMap(rd['loaderData']);
    if (loader == null) return null;

    for (final page in loader.values) {
      final p = _asMap(page);
      if (p == null) continue;
      final vir = _asMap(p['videoInfoRes']);
      if (vir == null) continue;
      final list = vir['item_list'];
      if (list is! List) continue;
      for (final item in list) {
        final m = _asMap(item);
        if (m == null) continue;
        final a = fromAwemeJson(m, source: 'router');
        if (a != null && a.usable) return a;
      }
    }
    return null;
  }

  /* ------------------------------------------------------------------ */
  /* 入口 2：标准 aweme JSON（接口响应 / SSR 内嵌对象）                    */
  /* ------------------------------------------------------------------ */

  /// 解析一份标准 aweme 对象。
  ///
  /// 这个结构在接口（`aweme/detail`、`aweme/post`、`aweme/related`）和
  /// `_ROUTER_DATA` 里是同一套，所以一个函数全吃。
  static DouyinAweme? fromAwemeJson(Map<String, dynamic> j, {String source = ''}) {
    final id = _str(j['aweme_id'] ?? j['awemeId'] ?? j['group_id_str'] ?? j['group_id']);
    if (id.isEmpty) return null;

    final author = _str(_asMap(j['author'])?['nickname']);

    // ---- 视频 ----
    final video = _asMap(j['video']);
    var videoId = '';
    final playUrls = <String>[];
    var vw = 0;
    var vh = 0;
    if (video != null) {
      // play_addr 是首选；某些作品只有 play_addr_h264 / play_addr_265
      for (final key in const [
        'play_addr',
        'play_addr_h264',
        'play_addr_265',
        'play_addr_bytevc1',
      ]) {
        final pa = video[key];
        final m = _asMap(pa);
        if (m == null) continue;
        if (videoId.isEmpty) videoId = _str(m['uri']);
        final ul = m['url_list'];
        if (ul is List) {
          for (final u in ul) {
            final s = _str(u);
            if (s.startsWith('http') && !playUrls.contains(s)) playUrls.add(s);
          }
        }
      }
      vw = _int(video['width']);
      vh = _int(video['height']);
    }

    // ---- 图文 ----
    final images = <DouyinImage>[];
    final rawImages = j['images'];
    if (rawImages is List) {
      for (final it in rawImages) {
        final m = _asMap(it);
        if (m == null) continue;
        final url = _pickImageUrl(m);
        if (url.isEmpty) continue;

        // 动图：video.play_addr 可能是 Map（含 url_list）也可能是 List（元素带 src）
        // 【字段名有两套】接口 JSON 用下划线 `play_addr`，页面 `__pace_f` 里
        // 是驼峰 `playAddr`。只认一种就会漏掉全部动图（实测：动图作品的 pace 里
        // `play_addr` 出现 0 次、`playAddr` 出现 3 次）。
        var liveUrl = '';
        var liveDur = 0;
        final v = _asMap(m['video']);
        if (v != null) {
          liveUrl = _pickVideoUrl(v['play_addr'] ?? v['playAddr']);
          liveDur = (_int(v['duration']) / 1000).round();
        }
        // clipType == 5 是平台标注的动图，但**不作为唯一判据**：
        // 实测有些动图没带这个字段，有些静态图却带了 —— 以「真的有没有视频地址」为准。
        images.add(DouyinImage(
          url: url,
          width: _int(m['width']),
          height: _int(m['height']),
          videoUrl: liveUrl,
          durationSec: liveDur,
        ));
      }
    }

    // 封面：顶层 cover → video.cover → video.origin_cover → 首图
    // 【实测】视频作品的 item_list[0] 里**顶层没有 cover**，封面挂在 video.cover，
    // 只读顶层会拿到空封面（卡片就是一片空白）。
    var coverFromJson = _pickImageUrl(_asMap(j['cover']));
    if (coverFromJson.isEmpty) {
      coverFromJson = _pickImageUrl(_asMap(video?['cover']));
    }
    if (coverFromJson.isEmpty) {
      coverFromJson = _pickImageUrl(_asMap(video?['origin_cover']));
    }
    final cover = coverFromJson.isNotEmpty
        ? coverFromJson
        : (images.isNotEmpty ? images.first.url : '');

    final music = _asMap(j['music']);
    final musicName = _str(music?['title'] ?? j['musicName']);

    return DouyinAweme(
      awemeId: id,
      desc: _str(j['desc']),
      author: author,
      cover: cover,
      durationSec: (_int(video?['duration']) / 1000).round(),
      videoId: videoId,
      playUrls: playUrls,
      images: images,
      createTime: _int(j['create_time']),
      musicName: musicName,
      width: vw,
      height: vh,
      source: source,
    );
  }

  /// 从一堆 aweme JSON 里挑出**目标作品**。
  ///
  /// 【为什么必须按 id 挑】
  /// 图文页会顺手加载作者的作品列表和「相关推荐」，里面几十个作品都带
  /// `images` 和 `play_addr`。不按 id 挑的话，用户点的是 A 作品，
  /// 存下来的是 B 作品 —— 这比「解析失败」恶劣得多。
  static DouyinAweme? pickById(Iterable<Map<String, dynamic>> list, String awemeId) {
    for (final m in list) {
      final id = _str(m['aweme_id'] ?? m['awemeId']);
      if (id == awemeId) {
        final a = fromAwemeJson(m, source: 'api');
        if (a != null && a.usable) return a;
      }
    }
    return null;
  }

  /* ------------------------------------------------------------------ */
  /* 入口 3：`__pace_f`（React Server Components 数据流）                */
  /* ------------------------------------------------------------------ */

  /// 从 `__pace_f` 的拼接文本里抠作品数据。
  ///
  /// 【这个文本长什么样】它是 RSC 的 flight 流，几十万字符，里面混着
  /// 页面骨架、组件树和 props。我们要找的东西有两种形态：
  ///   · `"images":[{"width":1282,"height":2282,"uri":"…","urlList":[…]},…]`
  ///   · `"play_addr":{"uri":"v1e00…","url_list":["https://…/playwm/?…"]}`
  ///
  /// 【为什么不能只认一种形态】
  /// 旧实现写死了 `"images":[{"width"`。实测同一个平台不同作品的字段顺序
  /// 并不固定（也见过 `"images":[{"uri"` 开头），写死一种就是等着失效。
  /// 这里改成「按 `"images":` 定位、用平衡括号抠出整段、JSON.parse」，
  /// 字段顺序完全不影响。
  ///
  /// 【为什么要取「最大的一组」】
  /// 页面里可能出现多组 images（当前作品 + 预加载的推荐作品）。当前图文作品
  /// 通常图最多，取最大的一组能避开「存下来是别人的图」。再叠一层 id 校验
  /// （见 [pickById]）与数量校验（见 `expectedImageCount`）。
  static DouyinAweme? fromPaceText(
    String pace, {
    String wantAwemeId = '',
    String hintTitle = '',
    String hintAuthor = '',
  }) {
    if (pace.isEmpty) return null;

    // ---- images：可能有多组，取元素最多的那组 ----
    var bestImages = <DouyinImage>[];
    var bestRaw = <dynamic>[];
    var bestAt = -1;
    var from = 0;
    while (true) {
      final at = pace.indexOf('"images":', from);
      if (at < 0) break;
      from = at + 9;
      final arr = _extractJsonAt(pace, at + 9);
      if (arr is! List) continue;
      final parsed = <DouyinImage>[];
      for (final it in arr) {
        final m = _asMap(it);
        if (m == null) continue;
        final url = _pickImageUrl(m);
        if (url.isEmpty) continue;
        if (!isDouyinImageHost(url)) continue;
        // 动图：video.play_addr 可能是 Map（含 url_list）也可能是 List（元素带 src）
        // 【字段名有两套】接口 JSON 用下划线 `play_addr`，页面 `__pace_f` 里
        // 是驼峰 `playAddr`。只认一种就会漏掉全部动图（实测：动图作品的 pace 里
        // `play_addr` 出现 0 次、`playAddr` 出现 3 次）。
        var liveUrl = '';
        var liveDur = 0;
        final v = _asMap(m['video']);
        if (v != null) {
          liveUrl = _pickVideoUrl(v['play_addr'] ?? v['playAddr']);
          liveDur = (_int(v['duration']) / 1000).round();
        }
        parsed.add(DouyinImage(
          url: url,
          width: _int(m['width']),
          height: _int(m['height']),
          videoUrl: liveUrl,
          durationSec: liveDur,
        ));
      }
      // 只认「看起来像作品图集」的组：至少 1 张，且都是图片 CDN
      if (parsed.length > bestImages.length) {
        bestImages = parsed;
        bestRaw = arr;
        bestAt = at;
      }
    }
    if (bestImages.isEmpty) {
      // 没有 images 时退一步：至少把视频地址找出来（视频页的 pace 里只有 play_addr）
      return _fromPaceVideoOnly(pace,
          wantAwemeId: wantAwemeId, hintTitle: hintTitle, hintAuthor: hintAuthor);
    }

    // ---- 元信息 ----
    // 【标题/作者不能"全文取第一个"】`__pace_f` 里混着**推荐流**的作品数据
    // （实测 68 个 `"desc"`、19 个 `"nickname"`），取第一个会拿到别人的标题。
    // 优先级：页面 title（就是当前作品的标题）> 目标 images 附近的 desc > 全文兜底。
    var title = hintTitle.trim();
    if (title.isEmpty) title = _jsonStringFieldNear(pace, 'desc', bestAt, 4000);
    if (title.isEmpty) title = _jsonStringField(pace, 'desc');

    var author = hintAuthor.trim();
    if (author.isEmpty) {
      // ownerNickname 是当前作品对象的作者字段（推荐流里不会有）
      author = _jsonStringField(pace, 'ownerNickname');
    }
    if (author.isEmpty) author = _jsonStringFieldNear(pace, 'nickname', bestAt, 4000);
    if (author.isEmpty) author = _jsonStringField(pace, 'nickname');

    final music = _jsonStringField(pace, 'musicName');
    var id = _jsonStringField(pace, 'aweme_id', preferDigits: true);
    if (id.isEmpty) id = _jsonStringField(pace, 'awemeId', preferDigits: true);
    var ct = _int(_jsonNumberField(pace, 'create_time'));
    if (ct == 0) ct = _int(_jsonNumberField(pace, 'createTime'));

    // 动图计数（clipType 5）只作为展示信息，不影响是否可用
    return DouyinAweme(
      awemeId: id.isEmpty ? wantAwemeId : id,
      desc: title,
      author: author,
      cover: bestImages.isNotEmpty ? bestImages.first.url : '',
      images: bestImages,
      musicName: music,
      createTime: ct,
      source: 'pace',
    ).copyWith(source: 'pace/${bestRaw.length}');
  }

  /// 在 [at] 附近的窗口里找字段 —— 只认「这一段数据所属作品」的字段，
  /// 避开推荐流里同名但属于别的作品的值。
  static String _jsonStringFieldNear(String s, String key, int at, int window) {
    if (at < 0) return '';
    final lo = (at - window).clamp(0, s.length);
    final hi = (at + window).clamp(0, s.length);
    // 先在 images 之前找（作品对象的字段通常写在 images 前面）
    final before = s.substring(lo, at);
    final fromBefore = _jsonStringField(before, key);
    if (fromBefore.isNotEmpty) return fromBefore;
    // 再在之后找
    return _jsonStringField(s.substring(at, hi), key);
  }

  /// pace 里没有 images 时，只抠视频信息（视频作品的页面就是这种情况）
  static DouyinAweme? _fromPaceVideoOnly(
    String pace, {
    String wantAwemeId = '',
    String hintTitle = '',
    String hintAuthor = '',
  }) {
    final at = pace.indexOf('"play_addr":');
    if (at < 0) return null;
    final obj = _extractJsonAt(pace, at + 12);
    final m = _asMap(obj);
    if (m == null) return null;
    final vid = _str(m['uri']);
    final urls = <String>[];
    final ul = m['url_list'];
    if (ul is List) {
      for (final u in ul) {
        final s = _str(u);
        if (s.startsWith('http')) urls.add(s);
      }
    }
    if (vid.isEmpty && urls.isEmpty) return null;

    // 标题同样优先用页面 title —— pace 里的 desc 是推荐流的热搜词
    var desc = hintTitle.trim();
    if (desc.isEmpty) desc = _jsonStringField(pace, 'desc');
    var author = hintAuthor.trim();
    if (author.isEmpty) author = _jsonStringField(pace, 'ownerNickname');
    if (author.isEmpty) author = _jsonStringField(pace, 'nickname');

    return DouyinAweme(
      awemeId: wantAwemeId.isNotEmpty
          ? wantAwemeId
          : _jsonStringField(pace, 'aweme_id', preferDigits: true),
      desc: desc,
      author: author,
      videoId: vid,
      playUrls: urls,
      source: 'pace-video',
    );
  }

  /* ------------------------------------------------------------------ */
  /* 入口 4：DOM 里散着的数据                                            */
  /* ------------------------------------------------------------------ */

  /// 用 DOM 抠出来的散装数据拼一个结果。
  ///
  /// [imageUrls] 是页面上 `aweme-images` 图片地址（已去重、按出现顺序），
  /// [videoUrls] 是 `<video>` / `<source>` 的地址（可能是 blob，需要上层过滤）。
  static DouyinAweme? fromDomParts({
    String awemeId = '',
    String title = '',
    String author = '',
    String cover = '',
    int durationSec = 0,
    List<String> imageUrls = const [],
    List<String> videoUrls = const [],
  }) {
    final images = <DouyinImage>[];
    for (final u in imageUrls) {
      if (!u.startsWith('http')) continue;
      if (!isDouyinImageHost(u)) continue;
      images.add(DouyinImage(url: u));
    }

    String cover2 = cover;
    if (cover2.isEmpty && images.isNotEmpty) cover2 = images.first.url;

    final plays = <String>[];
    for (final u in videoUrls) {
      if (!u.startsWith('http')) continue;
      if (_isStaticOrImageUrl(u)) continue;
      plays.add(u);
    }

    if (images.isEmpty && plays.isEmpty) return null;
    return DouyinAweme(
      awemeId: awemeId,
      desc: title,
      author: author,
      cover: cover2,
      durationSec: durationSec,
      playUrls: plays,
      images: images,
      source: 'dom',
    );
  }

  /* ------------------------------------------------------------------ */
  /* 视频地址：候选列表与去水印                                          */
  /* ------------------------------------------------------------------ */

  /// 从任意抖音播放地址里抠出 `video_id`。
  ///
  /// 形如 `…/aweme/v1/playwm/?line=0&ratio=720p&video_id=v1e00fgi0000…`
  static String videoIdFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      final v = u.queryParameters['video_id'] ?? u.queryParameters['videoId'];
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    final m = RegExp(r'[?&]video_id=([A-Za-z0-9]+)').firstMatch(url);
    return m?.group(1) ?? '';
  }

  /// 生成**按优先级排列**的视频地址候选。
  ///
  /// 【为什么是列表而不是一个地址】
  /// 抖音的播放口子有好几个，稳定性各不相同，而且会变：
  ///   · `aweme.snssdk.com/aweme/v1/play/` —— 无水印，实测可用（2026-11）
  ///   · `www.douyin.com/aweme/v1/play/`   —— 无水印，实测可用
  ///   · `…/playwm/…`                       —— 带水印，但接受度最广（兜底）
  ///
  /// 上层会逐个真探测（Range 请求 + `ftyp` 头校验），用第一个真能取到数据的。
  /// 这比「只算一个地址，失败就让用户重试」稳得多。
  static List<String> videoUrlCandidates(DouyinAweme a) {
    final out = <String>[];
    final vid = a.videoId;

    if (vid.isNotEmpty) {
      for (final ratio in const ['1080p', '720p']) {
        out.add('https://aweme.snssdk.com/aweme/v1/play/'
            '?video_id=$vid&ratio=$ratio&line=0');
        out.add('https://www.douyin.com/aweme/v1/play/'
            '?video_id=$vid&ratio=$ratio&line=0');
      }
    }

    for (final raw in a.playUrls) {
      if (!raw.startsWith('http')) continue;
      // playwm → play：同 host 换路径（有些 host 上确实有 play 口子）
      if (raw.contains('/playwm/')) {
        final d = raw
            .replaceFirst('/playwm/', '/play/')
            .replaceAll('logo_name=aweme_diversion_search&', '')
            .replaceAll('&logo_name=aweme_diversion_search', '');
        if (!out.contains(d)) out.add(d);
      }
      // 原始地址放最后：它一定带水印，作为最后兜底
      if (!out.contains(raw)) out.add(raw);
    }

    // 从 playwm 的 query 里也能补出 video_id（uri 缺失时）
    if (vid.isEmpty) {
      for (final raw in a.playUrls) {
        final v = videoIdFromUrl(raw);
        if (v.isEmpty) continue;
        out.insert(0, 'https://aweme.snssdk.com/aweme/v1/play/'
            '?video_id=$v&ratio=1080p&line=0');
        break;
      }
    }
    return out;
  }

  /// 页面上的「当前/总数」计数，例如 `4/46` 里的 46。
  ///
  /// 用来判断「图是不是齐了」：比死等固定时间既快又准。
  static int parseCounter(String text) {
    final m = RegExp(r'(?:^|\s)\d{1,3}\s*/\s*(\d{1,4})(?:\s|$)').firstMatch(text);
    if (m == null) return 0;
    return int.tryParse(m.group(1) ?? '') ?? 0;
  }

  /* ------------------------------------------------------------------ */
  /* 小工具                                                              */
  /* ------------------------------------------------------------------ */

  /// 从 [at] 开始（跳过空白）抠出一段完整的 JSON 数组/对象并解析。
  ///
  /// 【为什么不能用 indexOf 找结尾】JSON 里有嵌套、有字符串里的括号和转义，
  /// 简单截断必然截错。这里做真正的平衡括号扫描，并且正确处理字符串内的
  /// `[`、`]`、`\\` 和 `\"`。
  static dynamic _extractJsonAt(String s, int at) {
    var i = at;
    while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) {
      i++;
    }
    if (i >= s.length) return null;
    final open = s[i];
    if (open != '[' && open != '{') return null;

    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var k = i; k < s.length; k++) {
      final ch = s[k];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (ch == '\\') {
          esc = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '[' || ch == '{') {
        depth++;
      } else if (ch == ']' || ch == '}') {
        depth--;
        if (depth == 0) {
          final raw = s.substring(i, k + 1);
          try {
            return jsonDecode(raw);
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 取 `"key":"value"` 形式的字符串字段（含 JSON 反转义）
  static String _jsonStringField(String s, String key, {bool preferDigits = false}) {
    final m = preferDigits
        ? RegExp('"$key"\\s*:\\s*"?(\\d{15,25})"?').firstMatch(s)
        : RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(s);
    if (m == null) return '';
    final raw = m.group(1) ?? '';
    if (preferDigits) return raw;
    try {
      return jsonDecode('"$raw"') as String;
    } catch (_) {
      return raw;
    }
  }

  static num _jsonNumberField(String s, String key) {
    final m = RegExp('"$key"\\s*:\\s*(\\d+)').firstMatch(s);
    if (m == null) return 0;
    return int.tryParse(m.group(1) ?? '') ?? 0;
  }

  /// 图片地址：**优先无水印**。
  /// `urlList` 是原图，`downloadUrlList` 是带水印的下载版 —— 顺序不能反。
  static String _pickImageUrl(Map<String, dynamic>? m) {
    if (m == null) return '';
    for (final key in const [
      'urlList',
      'url_list',
      'downloadUrlList',
      'download_url_list',
      'src',
      'url',
    ]) {
      final l = m[key];
      if (l is List) {
        for (final u in l) {
          final s = _str(u);
          if (s.startsWith('http')) return s;
        }
      } else if (l is String && l.startsWith('http')) {
        return l;
      }
    }
    return '';
  }

  /// 动图视频地址：`play_addr` 既可能是 Map（url_list），也可能是 List（元素带 src）
  static String _pickVideoUrl(dynamic playAddr) {
    if (playAddr is List) {
      for (final e in playAddr) {
        final m = _asMap(e);
        if (m == null) continue;
        final s = _str(m['src'] ?? m['url']);
        if (s.startsWith('http')) return s;
      }
      return '';
    }
    final m = _asMap(playAddr);
    if (m == null) return '';
    final ul = m['url_list'];
    if (ul is List) {
      for (final u in ul) {
        final s = _str(u);
        if (s.startsWith('http')) return s;
      }
    }
    return '';
  }

  /// 静态资源 / 图片 / 音频地址的判据。
  ///
  /// 【为什么必须排掉】图文页的 `<video>` 里挂的其实是**背景音乐 mp3**
  /// （`lf26-music-east.douyinstatic.com/…mp3`），页面里还有一堆图标 png。
  /// 不排除的话，「没有视频的图文作品」会被认成一个视频作品 ——
  /// 用户点保存，下到一个 mp3 或者一张 logo。
  static bool _isStaticOrImageUrl(String u) {
    final lower = u.toLowerCase();
    for (final ext in const ['.mp3', '.m4a', '.aac', '.jpg', '.jpeg', '.png', '.webp', '.gif', '.svg', '.ico']) {
      if (lower.contains(ext)) return true;
    }
    for (final host in const [
      'douyinstatic.com',
      'bytecdn.com',
      'bytegoofy.com',
      'bytednsdoc.com',
      'douyinpic.com',
      'byteimg.com',
      'ibytedapm.com',
    ]) {
      if (lower.contains(host)) return true;
    }
    return false;
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    if (v is String && v.length > 1) {
      // 有些入口给的是 JSON 字符串
      final t = v.trim();
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          final d = jsonDecode(t);
          if (d is Map) return d.cast<String, dynamic>();
        } catch (_) {}
      }
    }
    return null;
  }

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num) return v.toString();
    return '';
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
