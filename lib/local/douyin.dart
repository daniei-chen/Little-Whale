import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'douyin_parse.dart';
import 'engine.dart';
import 'types.dart';

/// 抖音 · 本地解析（v0.1.0 重写）
///
/// ## 这一版解决的是什么
///
/// 旧实现有两条硬依赖，任何一条不成立就整条链接解析失败：
///   · 视频只读页面上的 `<video>` 元素
///   · 图文只读 `__pace_f` 里 `"images":[{"width"` 这一种写死的形态
///
/// 而抖音最近两次改版恰好把这两处都动了：
///   · 分享页渲染后的**完整作品数据回到了 `window._ROUTER_DATA` 里**
///     （`loaderData["video_(id)/page"].videoInfoRes.item_list[0]`），
///     比 `<video>` 稳得多 —— 不用等播放器挂载，还能一次拿到标题/作者/时长/封面；
///   · `__pace_f` 里的 `images` 字段顺序不再固定，只认一种前缀必然漏。
///
/// 现在的策略是**多入口 + 多数据源 + 真探测**：
///
/// ```
/// 链接归一化 ──► 入口候选（手机分享页 / PC 作品页 / 分享域）
///                     │
///                     ├─ 一次导航，同一份探针脚本同时取回四类数据：
///                     │     _ROUTER_DATA · __pace_f(images/play_addr) · DOM · 页面计数
///                     │
///                     ├─ 纯 Dart 的 DouyinParser 统一解析（有真实数据单测）
///                     │
///                     └─ 媒体地址**真探测**：Range 请求 + ftyp 头校验，
///                        候选地址逐个试，用第一个真能取到字节的
/// ```
///
/// 关键取舍：**宁可多花一次 Range 请求，也不要把一个取不到的地址交给下载器。**
/// 「解析成功、保存失败」对用户的伤害比「解析失败」大得多 —— 前者会让人以为
/// 文件已经在手机里了。
class DouyinLocalPlatform extends LocalPlatform {
  @override
  String get key => 'douyin';

  @override
  String get name => '抖音';

  @override
  List<String> get hosts => const [
        'douyin.com',
        'iesdouyin.com',
        // 【不要在这里加 douyinpic.com】那是**图片 CDN**，不是作品页。
        // 加进来的后果：用户粘贴一张抖音图片的地址，App 会说「识别到抖音链接」
        // 然后解析失败 —— 比干脆说「这不是作品链接」更糟。
        // 图片域名在 DouyinParser.isDouyinImageHost 里单独判断。
      ];

  @override
  String get referer => 'https://www.douyin.com/';

  /* ------------------------------------------------------------------ */
  /* UA 常量                                                             */
  /* ------------------------------------------------------------------ */

  /// iPhone Safari —— 抖音对它给的是**真正的手机分享页**（带完整 `_ROUTER_DATA`）
  static const String _uaIphone =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  /// Android Chrome —— 少数情况下 iPhone UA 被拦时的备选
  static const String _uaAndroid =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  /// 桌面 Chrome —— **图文页必须用它**（手机 UA 会被跳到分享页，那套不发图文数据）
  static String get _uaDesktop => LocalEngine.desktopUa;

  /// 下载/探测媒体时用的 UA
  static const String _uaMedia = _uaIphone;

  /* ------------------------------------------------------------------ */
  /* 链接归一化                                                          */
  /* ------------------------------------------------------------------ */

  /// 路径里的作品号。注意 `slides` ——
  /// 抖音图文有一种分享形态是 `iesdouyin.com/share/slides/{id}`，
  /// 旧实现只认 `video|note`，这类链接会掉进「没找到作品号」。
  static final RegExp _idInPath =
      RegExp(r'/(?:share/)?(video|note|slides)/(\d{15,25})');

  /// 查询参数里也可能直接带作品号（`modal_id` 是网页版弹层分享的形式）
  static const List<String> _idQueryKeys = ['aweme_id', 'item_id', 'modal_id'];

  static final RegExp _digitId = RegExp(r'^\d{15,25}$');

  /// 短链还原专用 Dio —— 复用连接，且**不跟随到最终页面的 body**
  static final Dio _shortDio = Dio(BaseOptions(
    // 【v0.1.2 收紧】短链还原只是一次 302 跟随，页面上百 KB 的正文我们并不需要。
    // 原来给 8s/12s，遇到网络抽风时会挨个等满 —— 实测这样一次解析能多花 8 秒。
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 5),
    followRedirects: true,
    maxRedirects: 8,
    validateStatus: (s) => s != null && s < 500,
    responseType: ResponseType.plain,
  ));

  /// 媒体可用性探测专用 Dio
  static final Dio _probeDio = Dio(BaseOptions(
    // 【v0.1.2 收紧】这两个超时原先给的是 8s / 12s，本意是"稳一点"，
    // 实测代价极大：weme.snssdk.com 的 play 接口在某些网络下会挂住，
    // 于是 4 个候选并发探测要一起等到 12 秒 —— 用户看到的就是"点了解析，
    // 转圈二十多秒才出来"。探测只是确认"能不能取到一段字"，
    // 4 秒足够；真取不到再让下载环节兜底。
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
    followRedirects: true,
    maxRedirects: 5,
    validateStatus: (s) => s != null && s < 500,
    responseType: ResponseType.bytes,
  ));

  /* ------------------------------------------------------------------ */
  /* 主流程                                                              */
  /* ------------------------------------------------------------------ */

  @override
  Future<LocalResult> parse(String url) async {
    final link = await _resolveLink(url);
    if (link.awemeId.isEmpty) {
      throw const LocalParseError(
        '没在链接里找到抖音作品号。\n\n'
        '请确认复制的是「分享 → 复制链接」的完整内容（形如 '
        'https://v.douyin.com/xxxx/ 或 https://www.douyin.com/video/7…）。',
      );
    }

    final entries = _entriesFor(link);
    final failures = <String>[];

    for (final e in entries) {
      try {
        final r = await _tryEntry(e, link);
        if (r != null) return r;
        failures.add('${e.label}：页面没有给出可用的媒体地址');
      } on LocalParseError catch (ex) {
        failures.add('${e.label}：${ex.message}');
      } catch (ex) {
        failures.add('${e.label}：$ex');
      }
    }

    throw LocalParseError(
      '抖音这次没能解析出来（已依次尝试 ${entries.length} 个入口）。\n\n'
      '常见原因：作品已删除/设为私密、仅好友可见、或短时间内解析太频繁触发了风控。\n'
      '可以等十几秒再试；如果这条链接在抖音里能正常打开，把链接反馈给我们。\n\n'
      '—— 各入口结果 ——\n${failures.join('\n')}',
    );
  }

  /* ------------------------------------------------------------------ */
  /* 入口候选                                                            */
  /* ------------------------------------------------------------------ */

  /// 一个解析入口：用什么地址、什么 UA、等多久
  List<_Entry> _entriesFor(DouyinLink link) {
    final id = link.awemeId;
    if (link.kind == DouyinKind.video) {
      return [
        // ① PC 作品页 + 手机 UA：会 302 到带 share_sign 的分享页，
        //    渲染后 `_ROUTER_DATA` 里就是完整作品数据。**目前最稳的一条**。
        _Entry(
          label: '手机分享页',
          url: 'https://www.douyin.com/video/$id',
          mobile: true,
          timeout: const Duration(seconds: 22),
        ),
        // ② 分享域直达：不带 share_sign 时可能被挡，但对老作品常常可用
        _Entry(
          label: 'iesdouyin 分享域',
          url: 'https://www.iesdouyin.com/share/video/$id/',
          mobile: true,
          timeout: const Duration(seconds: 16),
        ),
        // ③ PC 作品页 + 桌面 UA：详情接口那条路，作为最后兜底
        _Entry(
          label: 'PC 作品页',
          url: 'https://www.douyin.com/video/$id',
          mobile: false,
          timeout: const Duration(seconds: 18),
        ),
      ];
    }

    // 图文（含 slides）：桌面 UA 打开作品页，`__pace_f` 里带全量 images
    return [
      _Entry(
        label: '图文作品页',
        url: 'https://www.douyin.com/note/$id',
        mobile: false,
        timeout: const Duration(seconds: 22),
      ),
      // 有些图文的分享形态落在 slides 路由上
      _Entry(
        label: 'slides 分享页',
        url: 'https://www.iesdouyin.com/share/slides/$id/',
        mobile: false,
        timeout: const Duration(seconds: 16),
      ),
      // 兜底：同一个 id 用 video 路由打开，部分图文作品也能出数据
      _Entry(
        label: 'video 路由兜底',
        url: 'https://www.douyin.com/video/$id',
        mobile: false,
        timeout: const Duration(seconds: 16),
      ),
    ];
  }

  Future<LocalResult?> _tryEntry(_Entry e, DouyinLink link) async {
    final engine = LocalEngine.instance;

    // 【UA 和指纹必须一起切】
    // 旧实现只切 UA、指纹脚本却一直装"桌面 Chrome"那套（plugins、1440×900、
    // maxTouchPoints=0）。手机 UA + 桌面指纹是**自相矛盾**的组合，
    // 平台的风控很容易据此给降级页面 —— 表现就是「页面能打开，但没有任何数据」。
    await engine.setUserAgent(e.mobile ? _uaIphone : _uaDesktop);
    try {
      final t0 = DateTime.now();
      final env = await engine.evaluatePolling(
        e.url,
        _probeScript,
        settle: e.settle,
        interval: const Duration(milliseconds: 350),
        timeout: e.timeout,
        isDone: (v) => _isEnough(v, since: t0),
      );
      if (env is! Map) return null;

      if (kDebugMode) {
        debugPrint('[抖音] 探针(${e.label})：paceSegs=${env['paceSegs']} '
            'paceChars=${env['paceChars']} '
            'paceImages=${(env['paceImages'] as List?)?.length ?? 0} '
            'domImages=${(env['domImages'] as List?)?.length ?? 0} '
            'router=${_str(env['router']).length} '
            'title="${_short(_str(env['title']))}"');
      }

      // 【标题/作者补读】
      // pace 的图片数据到得比 `document.title` 早 —— 轮询一看到 images
      // 就收工，此时页面标题往往还是空的，界面上就是「46 张图 + 无标题」。
      // 这里在当前文档再补读几次（不导航，只读，成本很低）。
      var envFixed = env;
      if (_str(env['title']).isEmpty || _str(env['author']).isEmpty) {
        for (var attempt = 0; attempt < 1; attempt++) {
          final fix = await engine.evalCurrent(_metaFixScript);
          if (fix is Map) {
            envFixed = {
              ...envFixed,
              'title': _str(envFixed['title']).isNotEmpty
                  ? envFixed['title']
                  : fix['title'],
              'author': _str(envFixed['author']).isNotEmpty
                  ? envFixed['author']
                  : fix['author'],
              'ogImage': _str(envFixed['ogImage']).isNotEmpty
                  ? envFixed['ogImage']
                  : fix['ogImage'],
            };
          }
          if (_str(envFixed['title']).isNotEmpty &&
              _str(envFixed['author']).isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        if (kDebugMode) {
          debugPrint('[抖音] 补读元信息：title="${_short(_str(envFixed['title']))}" '
              'author="${_str(envFixed['author'])}"');
        }
      }

      final tBuild = DateTime.now();
      final aweme = _buildAweme(envFixed, link.awemeId);
      if (aweme == null) return null;
      if (kDebugMode) {
        debugPrint('[抖音] 入口 ${e.label} 命中数据源 ${aweme.source} '
            '（图 ${aweme.imageCount} 张，videoId=${aweme.videoId}）');
      }
      final r = await _toResult(aweme, link);
      if (kDebugMode) {
        final tEnd = DateTime.now();
        debugPrint('[抖音] 耗时拆解：采集=${tBuild.difference(t0).inMilliseconds}ms '
            '媒体校验=${tEnd.difference(tBuild).inMilliseconds}ms '
            '总计=${tEnd.difference(t0).inMilliseconds}ms');
      }
      return r;
    } finally {
      await engine.setUserAgent(_uaDesktop);
    }
  }

  /// 轮询结束条件 —— **判据要扎实，不能"拿到一点就收工"**
  ///
  /// 只认「平台自己的完整数据」：
  ///   · `_ROUTER_DATA` 里出现了 `videoInfoRes`（视频作品的完整数据，标题也在里面）
  ///   · `__pace_f` 里抠到了 images 段（图文作品的全量图集）**且页面标题已就绪**
  ///   · pace 里抠到了 play_addr（视频作品）
  ///   · DOM 里出现了**可下载的播放地址**（视频作品没有 pace，这条能提前收工）
  ///
  /// 【两个实测踩出来的坑】
  /// 1. 不能用「DOM 图数 >= 页面计数」收工：动图作品的计数是 `1/1`，
  ///    而 DOM 里还挂着 14 张推荐位图 —— 条件立刻成立，`__pace_f` 里那份带
  ///    `playAddr` 的数据再也没机会读。
  /// 2. 图文**必须等到标题**：图片数据到得比 `document.title` 早，
  ///    一看到 images 就收工会拿到空标题；退而求其次去 `__pace_f` 里捞
  ///    `"desc"` 更糟 —— 实测那一堆 desc 全是推荐流的热搜词
  ///    （"王濛"、"三角洲行动"…），跟作品毫无关系。
  ///    所以这里最多再等 [titleGrace] 秒，等不到就用页面 title 的空值走补读。
  bool _isEnough(dynamic v, {required DateTime since}) {
    if (v is! Map) return false;

    final router = _str(v['router']);
    if (router.contains('videoInfoRes')) return true;

    final pi = v['paceImages'];
    if (pi is List && pi.isNotEmpty) {
      if (_str(v['title']).isNotEmpty) return true;
      // 图片有了但标题还没上来 → 再给一点时间
      return DateTime.now().difference(since) > _titleGrace;
    }

    final pv = v['paceVideo'];
    if (pv is List && pv.isNotEmpty) return true;

    // DOM 严格过滤后已经凑齐页面计数 → 收工（不必为了 pace 死等满超时）
    final counter = _intOr(v['counter'], 0);
    final dom = v['domImages'];
    if (counter > 0 && dom is List && dom.length >= counter) return true;

    final vids = v['domVideos'];
    if (vids is List) {
      for (final u in vids) {
        final s = _str(u);
        if (s.contains('playwm') || s.contains('/play/')) return true;
      }
    }
    return false;
  }

  static int _intOr(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// 等页面标题就绪的最长时间
  static const Duration _titleGrace = Duration(milliseconds: 1500);

  /* ------------------------------------------------------------------ */
  /* 数据合成                                                            */
  /* ------------------------------------------------------------------ */

  /// 把探针回传的四类数据统一成一份作品。
  ///
  /// 【优先级】越靠前越权威：
  ///   1. `_ROUTER_DATA` —— 平台自己 SSR 的作品对象，字段最全
  ///   2. `__pace_f` 的 images —— 图文的全量图集（含动图视频）
  ///   3. `__pace_f` 的 play_addr —— 视频作品的播放地址
  ///   4. DOM —— 前三条都拿不到时的兜底（懒加载/结构变更时它还能救一下）
  DouyinAweme? _buildAweme(Map env, String awemeId) {
    final candidates = <DouyinAweme>[];

    final router = _str(env['router']);
    if (router.isNotEmpty) {
      final a = DouyinParser.fromRouterData(router);
      if (a != null && a.usable) candidates.add(a);
    }

    for (final list in [env['paceImages'], env['paceVideo']]) {
      if (list is! List) continue;
      for (final seg in list) {
        final a = DouyinParser.fromPaceText(
          _str(seg),
          wantAwemeId: awemeId,
          // 页面 title 就是当前作品的标题，比在 pace 里取第一个 "desc" 可靠
          hintTitle: _str(env['title']),
          hintAuthor: _str(env['author']),
        );
        if (a != null && a.usable) candidates.add(a);
      }
    }

    final dom = DouyinParser.fromDomParts(
      awemeId: awemeId,
      title: _str(env['title']),
      author: _str(env['author']),
      cover: _str(env['ogImage']),
      imageUrls: _strList(env['domImages']),
      videoUrls: _strList(env['domVideos']),
      maxImages: _intOr(env['counter'], 0),
    );
    if (dom != null && dom.usable) candidates.add(dom);

    if (candidates.isEmpty) return null;

    // 【判定顺序很关键，这里踩过两个坑】
    //
    // 坑 1：视频作品的 DOM 兜底也会捡到封面图（1 张），
    //       如果「有图就当图文」，视频会被解析成「1 张图的图文作品」。
    // 坑 2：动图（Live Photo）作品的 `<video>` 是动图播放器，
    //       如果「有视频就当视频」，动图会被解析成一段视频。
    //
    // 正确判据：
    //   a. 图片里有动图（每张图自带 videoUrl）→ 这是图文作品
    //   b. 有 platform 级 videoId（来自 _ROUTER_DATA / pace 的 play_addr）→ 视频
    //   c. 图片 >= 2 张 → 图文
    //   d. 剩下只有「1 张图 + DOM 播放地址」的模糊情况 → 按视频（抖音单图图文极少，
    //      而视频作品的封面必然只有 1 张）
    final withImages = candidates.where((e) => e.isImages).toList();
    final withVideo = candidates.where((e) => e.hasVideo).toList();

    final liveLike = withImages.where((e) => e.hasLivePhotos).toList();
    if (liveLike.isNotEmpty) {
      liveLike.sort((a, b) => b.imageCount.compareTo(a.imageCount));
      return _mergeInfo(liveLike.first, candidates);
    }

    final byVideoId = withVideo.where((e) => e.videoId.isNotEmpty).toList();
    if (byVideoId.isNotEmpty) {
      byVideoId.sort((a, b) => b.playUrls.length.compareTo(a.playUrls.length));
      return _mergeInfo(byVideoId.first, candidates);
    }

    final multiImage = withImages.where((e) => e.imageCount >= 2).toList();
    if (multiImage.isNotEmpty) {
      multiImage.sort((a, b) => b.imageCount.compareTo(a.imageCount));
      return _mergeInfo(multiImage.first, candidates);
    }

    if (withVideo.isNotEmpty) {
      withVideo.sort((a, b) => b.playUrls.length.compareTo(a.playUrls.length));
      return _mergeInfo(withVideo.first, candidates);
    }

    if (withImages.isNotEmpty) {
      return _mergeInfo(withImages.first, candidates);
    }
    return null;
  }

  /// 用其它候选补齐缺失的元信息（某个来源可能只有图、没有标题作者）
  DouyinAweme _mergeInfo(DouyinAweme main, List<DouyinAweme> all) {
    var desc = main.desc;
    var author = main.author;
    var cover = main.cover;
    var music = main.musicName;
    var duration = main.durationSec;
    for (final e in all) {
      if (desc.isEmpty && e.desc.isNotEmpty) desc = e.desc;
      if (author.isEmpty && e.author.isNotEmpty) author = e.author;
      if (cover.isEmpty && e.cover.isNotEmpty) cover = e.cover;
      if (music.isEmpty && e.musicName.isNotEmpty) music = e.musicName;
      if (duration == 0 && e.durationSec > 0) duration = e.durationSec;
    }
    return DouyinAweme(
      awemeId: main.awemeId.isNotEmpty ? main.awemeId : '',
      desc: desc,
      author: author,
      cover: cover,
      durationSec: duration,
      videoId: main.videoId,
      playUrls: main.playUrls,
      images: main.images,
      createTime: main.createTime,
      musicName: music,
      width: main.width,
      height: main.height,
      source: main.source,
    );
  }

  /* ------------------------------------------------------------------ */
  /* 结果转换（含媒体可用性真探测）                                        */
  /* ------------------------------------------------------------------ */

  Future<LocalResult> _toResult(DouyinAweme a, DouyinLink link) async {
    if (a.isImages) {
      final alive = await _verifyImages(a.images);
      if (!alive) {
        throw const LocalParseError(
          '拿到了图片地址，但实际取不到内容（链接可能已签发过期）。'
          '重新解析一次通常会好。',
        );
      }
      return LocalResult(
        platform: key,
        platformName: name,
        type: 'images',
        title: a.desc,
        author: a.author,
        cover: a.cover.isNotEmpty ? a.cover : a.images.first.url,
        referer: referer,
        music: a.musicName,
        publishTime: _formatTime(a.createTime),
        images: a.images
            .map((e) => LocalImage(
                  url: e.url,
                  width: e.width,
                  height: e.height,
                  videoUrl: e.videoUrl,
                  durationSec: e.durationSec,
                ))
            .toList(),
        sourceUrl: link.resolvedUrl,
      );
    }

    final candidates = DouyinParser.videoUrlCandidates(a);
    final picked = await _pickPlayable(candidates);
    if (picked == null) {
      throw const LocalParseError(
        '找到了作品，但所有播放地址都取不到内容。'
        '可能是这条作品被限制访问，或 CDN 暂时抽风 —— 稍后重试一般会好。',
      );
    }

    return LocalResult(
      platform: key,
      platformName: name,
      type: 'video',
      title: a.desc,
      author: a.author,
      cover: a.cover,
      durationSec: a.durationSec,
      resolution: _resolutionOf(picked, a),
      referer: referer,
      music: a.musicName,
      publishTime: _formatTime(a.createTime),
      videoUrl: picked,
      sourceUrl: link.resolvedUrl,
    );
  }

  /// 逐个探测视频候选地址，返回**第一个真能取到视频字节**的。
  ///
  /// 并发前 4 个：抖音的播放接口有时单个节点会 5xx，串行等下去太慢。
  ///
  /// 【三态判定，不要一刀切】
  ///   true  = 真取到了 MP4 字节
  ///   false = 明确失效（4xx/5xx、返回 HTML）
  ///   null  = 探测本身没做成（超时/DNS/TLS）—— **不能据此判定地址无效**
  /// 全部为 false 才算彻底失败；只要有一个 null 就先交出去，让下载器再试一次，
  /// 否则用户网络抖一下就会看到「解析失败」。
  Future<String?> _pickPlayable(List<String> urls) async {
    if (urls.isEmpty) return null;

    // 前 2 个是**最可能可用的无水印 1080P**（snssdk / www 两条）
    final batch = urls.take(2).toList();
    final results = await Future.wait(batch.map(_isPlayable));
    for (var i = 0; i < results.length; i++) {
      if (results[i] == true) return batch[i];
    }

    // 【关键：只有「全都明确失效」才值得继续串行试】
    //
    // 实测踩到的坑：抖音视频这一次要 25 秒，日志里是
    //   `aweme.snssdk.com/.../play/?ratio=1080p` receive timeout 4s
    // 因为前两个候选探测超时（返回 null），代码继续串行试后面 4 个兜底地址，
    // 每个又是 4 秒 —— 光"确认地址能不能用"就花了 16 秒。
    //
    // 但「探测没做成」和「地址失效」是两件事：前者说明本机到 CDN 的网络有问题，
    // 这时候换地址也是同样的网络，串行试探没有意义。直接交第一个给下载器，
    // 它那边还有一次重试机会，而且用户至少立刻看到结果。
    if (results.every((r) => r == false)) {
      for (final u in urls.skip(2)) {
        if (await _isPlayable(u) == true) return u;
      }
      return null; // 全部明确失效
    }

    return batch.first;
  }

  /// 真的取一段字回来，并确认它是 MP4 —— 不看状态码，看字节。
  ///
  /// 【为什么要看 `ftyp`】抖音的 CDN 在链接失效时**会回 200 带一个 HTML 错误页**，
  /// 只校验状态码会被骗过去，用户那边表现就是「下载到的文件打不开」。
  Future<bool?> _isPlayable(String url) async {
    if (!url.startsWith('http')) return false;
    try {
      final r = await _probeDio.get<List<int>>(
        url,
        options: Options(headers: {
          'User-Agent': _uaMedia,
          'Referer': referer,
          'Range': 'bytes=0-2047',
          'Accept': '*/*',
        }),
      );
      final code = r.statusCode ?? 0;
      final data = r.data ?? const <int>[];
      if (code != 200 && code != 206) {
        if (kDebugMode) debugPrint('[抖音] 视频候选 HTTP $code：${_short(url)}');
        return false;
      }
      if (data.length < 512) return false;
      final mp4 = _looksLikeMp4(data);
      if (!mp4 && kDebugMode) {
        debugPrint('[抖音] 视频候选不是 MP4（${data.length}B）：${_short(url)}');
      }
      return mp4;
    } catch (e) {
      // 网络层异常：不能据此判定地址无效
      if (kDebugMode) debugPrint('[抖音] 视频探测异常：${_short(url)} → $e');
      return null;
    }
  }

  /// 抽样校验图片可用性 —— **只验首图，且最多等 3 秒**。
  ///
  /// 【为什么要克制】抖音的图片地址带 `x-signature` 和 `x-expires`，整批发同一张
  /// 签名，验一张就能判断"这批还新鲜吗"。早先抽首/中/尾三张并发去验，
  /// 在网络抖动的模拟器上实测要 **10 秒以上**才回来 —— 而这一步只是防御性检查，
  /// 不应该让用户干等。现在：一张、5 秒上限、拿不到就放行（交给下载环节再兜底）。
  Future<bool> _verifyImages(List<DouyinImage> images) async {
    if (images.isEmpty) return false;
    bool? ok;
    try {
      ok = await _isImageAlive(images.first.url)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {
      ok = null;
    }
    if (ok == true) return true;
    if (ok == false) {
      if (kDebugMode) debugPrint('[抖音] 首图明确失效');
      return false;
    }
    if (kDebugMode) debugPrint('[抖音] 图片探测超时/网络异常，放行');
    return true;
  }

  Future<bool?> _isImageAlive(String url) async {
    if (!url.startsWith('http')) return false;
    try {
      final r = await _probeDio.get<List<int>>(
        url,
        options: Options(headers: {
          'User-Agent': _uaMedia,
          'Referer': referer,
          'Range': 'bytes=0-1023',
          'Accept': '*/*',
        }),
      );
      final code = r.statusCode ?? 0;
      final data = r.data ?? const <int>[];
      if (code != 200 && code != 206) {
        if (kDebugMode) debugPrint('[抖音] 图片 HTTP $code：${_short(url)}');
        return false;
      }
      if (data.length < 128) return false;
      final html = _startsWithText(data, '<');
      if (html && kDebugMode) debugPrint('[抖音] 图片返回了 HTML：${_short(url)}');
      return !html;
    } catch (e) {
      if (kDebugMode) debugPrint('[抖音] 图片探测异常：${_short(url)} → $e');
      return null;
    }
  }

  static String _short(String u) => u.length <= 100 ? u : '${u.substring(0, 100)}…';

  static bool _looksLikeMp4(List<int> head) {
    if (head.length < 12) return false;
    // ISO BMFF: 4 字节 box 长度 + "ftyp"
    return head[4] == 0x66 && head[5] == 0x74 && head[6] == 0x79 && head[7] == 0x70;
  }

  static bool _startsWithText(List<int> data, String ch) {
    if (data.isEmpty) return false;
    // 跳过可能的 BOM / 空白
    for (var i = 0; i < data.length && i < 8; i++) {
      final c = data[i];
      if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09) continue;
      return c == ch.codeUnitAt(0);
    }
    return false;
  }

  String _resolutionOf(String url, DouyinAweme a) {
    final m = RegExp(r'ratio=(\d{3,4})p').firstMatch(url);
    if (m != null) return '${m.group(1)}P';
    if (a.height > 0) return '${a.height}P';
    return '';
  }

  /// 秒级时间戳 → `yyyy-MM-dd`
  static String _formatTime(int seconds) {
    if (seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: false);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /* ------------------------------------------------------------------ */
  /* 短链还原                                                            */
  /* ------------------------------------------------------------------ */

  /// 把 `v.douyin.com/xxxx/` 这类短链还原成带作品号的形式。
  ///
  /// 【为什么不是"先 HEAD 再 GET"就够】
  /// 实测（2026-11）：
  ///   · `HEAD` 在部分短链上直接 404（desktop UA 尤其常见），只能靠 `GET`；
  ///   · 同一个短链，iPhone UA 会 302 到 `iesdouyin.com/share/…`（带 share_sign），
  ///     桌面 UA 会 302 到 `www.douyin.com/video/…` —— **两者都能用，但形态不同**；
  ///   · 用 Dart 默认 UA 请求时连 TLS 握手都可能被拒。
  /// 所以这里按 UA 逐个试，任意一个拿到作品号就收工。
  Future<DouyinLink> _resolveLink(String raw) async {
    final text = raw.trim();
    final url = _extractUrl(text) ?? text;

    final direct = _linkFromUrl(url);
    if (direct.awemeId.isNotEmpty) return direct;

    // 【为什么只留 3 种组合】实测 iPhone UA + GET 的命中率最高，
    // 其余两种是它被拦时的备选。原来 3 UA × 2 方法 = 6 次，
    // 网络不好时光"试错"就要十几秒。
    for (final combo in const [
      (_uaIphone, 'GET'),
      (_uaIphone, 'HEAD'),
      (_uaAndroid, 'GET'),
    ]) {
      final ua = combo.$1;
      final method = combo.$2;
      {
        try {
          final r = await _shortDio.request<String>(
            url,
            options: Options(
              method: method,
              headers: {
                'User-Agent': ua,
                'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
                'Accept-Language': 'zh-CN,zh;q=0.9',
              },
            ),
          );
          final real = r.realUri.toString();
          final hit = _linkFromUrl(real);
          if (hit.awemeId.isNotEmpty) return hit;

          // 有些短链回的是页面（不跳转），作品号在正文里
          final body = r.data;
          if (body is String && body.isNotEmpty) {
            final fromBody = _linkFromUrl(body);
            if (fromBody.awemeId.isNotEmpty) {
              return DouyinLink(fromBody.awemeId, fromBody.kind, real);
            }
          }
        } catch (_) {
          // 换下一个 UA / 方法
        }
      }
    }
    return direct;
  }

  /// 从 URL（或一段文本）里认出作品号与内容形态
  DouyinLink _linkFromUrl(String s) {
    final m = _idInPath.firstMatch(s);
    if (m != null) {
      final kind = m.group(1) == 'video' ? DouyinKind.video : DouyinKind.images;
      return DouyinLink(m.group(2)!, kind, s);
    }

    // 查询参数
    final at = s.indexOf('?');
    if (at > 0 && at < s.length - 1) {
      try {
        final uri = Uri.parse(s.length > 2000 ? s.substring(0, 2000) : s);
        for (final k in _idQueryKeys) {
          final v = uri.queryParameters[k] ?? '';
          if (_digitId.hasMatch(v)) {
            return DouyinLink(v, DouyinKind.unknown, s);
          }
        }
      } catch (_) {}
    }

    // 兜底：只从**路径段**里找长数字（不从整串找 —— 那会把 mid/did 之类的
    // 参数串当成作品号，解析出一个完全不存在的作品，比直接失败更难排查）
    final pathEnd = s.indexOf('?');
    final path = pathEnd > 0 ? s.substring(0, pathEnd) : s;
    for (final seg in path.split('/')) {
      if (_digitId.hasMatch(seg)) {
        return DouyinLink(seg, DouyinKind.unknown, s);
      }
    }
    return DouyinLink('', DouyinKind.unknown, s);
  }

  /// 从分享文案里抠出第一个 http(s) 链接
  static String? _extractUrl(String text) {
    // 用三引号原始串：字符类里要同时排掉中英文标点和引号，
    // 单引号原始串写不进 `'`（反斜杠在 raw 里不转义，会直接把串截断）
    final m = RegExp(r'''https?://[^\s，。、；：！？"'"）】]+''').firstMatch(text);
    return m?.group(0);
  }

  /* ------------------------------------------------------------------ */
  /* 页面探针脚本                                                        */
  /* ------------------------------------------------------------------ */

  /// 一次执行，同时把**四类数据源**取回来。
  ///
  /// 【为什么必须一次取完】
  /// 每次 `runJavaScriptReturningResult` 都是一次跨进程往返，几百毫秒起步。
  /// 旧实现为了拿图片数量反复轮询 DOM，光是空转就把解析时间拖到十几秒。
  ///
  /// 【为什么要把 pace 在 JS 里裁剪】
  /// `__pace_f` 拼接起来有 **60 万字符以上**。整段回传给 Dart 会撞上
  /// Android WebView `evaluateJavascript` 的返回值上限（表现为拿到 null）。
  /// 所以这里只把**真正有用的片段**（images 数组、play_addr 对象）抠出来，
  /// 单段十几 KB，既安全又完整。
  ///
  /// 【为什么带缓存】
  /// 轮询每 350ms 执行一次，每次都重扫 600KB 太浪费。一旦"确认够用"就把
  /// 结果缓存到 `window.__fsDyCache`；导航到新文档时该变量自然消失，不会串数据。
  static const String _probeScript = r'''
(function () {
  // 同一文档里已经拿到完整数据 → 直接返回，省掉每轮 600KB 的重扫
  if (window.__fsDyCache) return window.__fsDyCache;

  // 从 at 处抠出一段平衡的 JSON（正确处理字符串里的括号与转义）
  function balanced(s, at) {
    var i = at;
    while (i < s.length && ' \n\r\t'.indexOf(s.charAt(i)) >= 0) i++;
    if (i >= s.length) return '';
    var open = s.charAt(i);
    if (open !== '[' && open !== '{') return '';
    var depth = 0, inStr = false, esc = false;
    for (var k = i; k < s.length; k++) {
      var ch = s.charAt(k);
      if (inStr) {
        if (esc) esc = false;
        else if (ch === '\\') esc = true;
        else if (ch === '"') inStr = false;
        continue;
      }
      if (ch === '"') inStr = true;
      else if (ch === '[' || ch === '{') depth++;
      else if (ch === ']' || ch === '}') {
        depth--;
        if (depth === 0) return s.substring(i, k + 1);
      }
    }
    return '';
  }

  // ---- 1) _ROUTER_DATA：视频分享页渲染后含 videoInfoRes ----
  var router = '';
  try {
    if (window._ROUTER_DATA) router = JSON.stringify(window._ROUTER_DATA);
  } catch (e) {}

  // ---- 2) __pace_f：图文的全量 images / 视频的 play_addr ----
  //
  // 【为什么不用 String(segs[i]) 直接转】`__pace_f` 的元素通常是「数组里套字符串」
  // 的 RSC 分片，`String()` 会把分片拼成 "1,1:I{...}"（带序号和逗号），
  // 遇到嵌套更深的元素甚至会变成 "[object Object]" —— 数据明明在，却永远提取不到。
  // 这里逐层收集**字符串元素**再拼接，任何结构都能拿到正文。
  function collectPaceText() {
    var segs = window.__pace_f || [];
    var parts = [];
    function dig(v, depth) {
      if (v == null || depth > 3) return;
      if (typeof v === 'string') { parts.push(v); return; }
      if (typeof v === 'object' && v.length !== undefined) {
        for (var i = 0; i < v.length; i++) dig(v[i], depth + 1);
        return;
      }
      if (typeof v === 'object') {
        try { parts.push(JSON.stringify(v)); } catch (e) {}
      }
    }
    try { dig(segs, 0); } catch (e) {}
    return parts.join('\n');
  }

  var paceImages = [];
  var paceVideo = [];
  var paceChars = 0;
  var paceSegs = 0;
  try {
    paceSegs = (window.__pace_f || []).length;
    var s = collectPaceText();
    paceChars = s.length;
    var from = 0;
    while (paceImages.length < 4) {
      var at = s.indexOf('"images":', from);
      if (at < 0) break;
      from = at + 9;
      var sub = balanced(s, at + 9);
      if (sub && sub.length > 8) paceImages.push('"images":' + sub);
    }
    var at2 = s.indexOf('"play_addr":');
    if (at2 >= 0) {
      var sub2 = balanced(s, at2 + 12);
      if (sub2) paceVideo.push('"play_addr":' + sub2);
    }
  } catch (e) {}

  // ---- 3) DOM：懒加载/结构变更时的兜底 ----
  var domImages = [];
  var seen = {};
  try {
    var imgs = document.querySelectorAll('img');
    for (var q = 0; q < imgs.length; q++) {
      var src = imgs[q].currentSrc || imgs[q].src || '';
      if (!src || src.indexOf('http') !== 0) continue;
      // 【判据必须严格：只认 aweme-images 模板】
      // 实测同一条图文页里，DOM 会同时出现两类 douyinpic 图：
      //   作品图  …~tplv-dy-aweme-images:q75.webp?biz_tag=aweme_images   ← 要
      //   封面/推荐 …~tplv-dy-resize-walign-adapt-aq:540:q75.webp?biz_tag=aweme_video ← 不要
      // 早先的判据只要求「douyinpic 域」，于是一条 46 张的图文能收出 58 张 ——
      // 多出来的 12 张是推荐位，用户会存到完全不相干的图。
      if (src.indexOf('aweme-images') < 0) continue;
      if (src.indexOf('biz_tag=aweme_video') > -1) continue;
      var m = /tos-cn-i-[a-z0-9]+\/([A-Za-z0-9_~\-]+)/.exec(src);
      var key = m ? m[1] : src;
      if (seen[key]) continue;
      seen[key] = 1;
      domImages.push(src);
    }
  } catch (e) {}

  var domVideos = [];
  try {
    var vels = document.querySelectorAll('video, source');
    for (var v = 0; v < vels.length; v++) {
      var u = vels[v].currentSrc || vels[v].src || '';
      if (u && u.indexOf('http') === 0 && domVideos.indexOf(u) < 0) domVideos.push(u);
    }
  } catch (e) {}

  // ---- 4) 元信息 ----
  var bodyText = '';
  try { bodyText = String(document.body ? document.body.innerText : ''); } catch (e) {}

  // 页面上的「当前/总数」（如 4/46）—— 用来判断图集是否齐了
  var counter = 0;
  try {
    var cm = bodyText.match(/(?:^|\s)\d{1,3}\s*\/\s*(\d{1,4})(?:\s|$)/);
    if (cm) counter = parseInt(cm[1], 10) || 0;
  } catch (e) {}

  var title = '';
  try {
    title = String(document.title || '').replace(/\s*-\s*抖音\s*$/, '').trim();
  } catch (e) {}

  var ogImage = '';
  try {
    var og = document.querySelector('meta[property="og:image"], meta[name="og:image"]');
    if (og) ogImage = String(og.getAttribute('content') || '').trim();
  } catch (e) {}

  // 作者：三条约束缺一不可（非 self、元素可见、文本短）
  var author = '';
  try {
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
    if (!author) {
      // 手机分享页没有 /user/ 链接，昵称以 @ 开头直接显示
      var els = document.querySelectorAll('span, div, a, p');
      for (var z = 0; z < els.length; z++) {
        var el = els[z];
        if (el.children.length > 0) continue;
        var tx = String(el.textContent || '').trim();
        if (tx.length < 2 || tx.length > 30) continue;
        if (tx.charAt(0) !== '@') continue;
        if (!(el.offsetWidth || el.offsetHeight)) continue;
        author = tx.replace(/^@/, '');
        break;
      }
    }
  } catch (e) {}

  var out = JSON.stringify({
    url: String(location.href || ''),
    router: router,
    paceImages: paceImages,
    paceVideo: paceVideo,
    paceSegs: paceSegs,
    paceChars: paceChars,
    domImages: domImages,
    domVideos: domVideos,
    title: title,
    author: author,
    counter: counter,
    ogImage: ogImage
  });

  // 只有"数据确实齐了"才缓存，避免把骨架阶段的半截数据钉死
  var solid = (router && router.indexOf('videoInfoRes') > -1) ||
              paceImages.length > 0 ||
              paceVideo.length > 0;
  if (solid) window.__fsDyCache = out;
  return out;
})()
''';

  /// 元信息补读：只在**当前文档**里取值，不导航、不等待。
  ///
  /// 标题按可靠度依次取：`document.title`（去掉后缀）→ `og:title` →
  /// 页面上的标题节点 → `__pace_f` 里的第一个 `desc`。
  /// 作者：`/user/` 链接（三条约束）→ `@` 开头的叶节点 → `og:author`。
  static const String _metaFixScript = r'''
(function () {
  function clean(s) {
    return String(s || '').replace(/\s*-\s*抖音\s*$/, '').replace(/\s+/g, ' ').trim();
  }
  function meta(prop) {
    var el = document.querySelector('meta[property="' + prop + '"]') ||
             document.querySelector('meta[name="' + prop + '"]');
    return el ? String(el.getAttribute('content') || '') : '';
  }

  var title = clean(document.title);
  if (!title) title = clean(meta('og:title'));

  // 【最可靠的一条：`发布时间：…` 前面那一行就是作品标题】
  // 实测抖音图文页里 `document.title` 在 Android WebView 中可能一直是空的
  // （页面标题由渲染进程异步设置），而正文里稳定存在：
  //     <标题>\n发布时间：2026-09-08 13:46:12
  // 这个位置比任何 class 名都稳（class 是构建期生成的哈希，随时会变）。
  if (!title) {
    try {
      var body = String(document.body ? document.body.innerText : '');
      var m = body.match(/([^\n]{2,160})\n\s*发布时间/);
      if (m) title = clean(m[1]);
    } catch (e) {}
  }

  // 再退一步：标题节点（h1/h2/h3 的第一个通常就是当前作品）
  if (!title) {
    var hs = document.querySelectorAll('h1, h2, h3, [data-e2e*="desc"], [data-e2e*="title"]');
    for (var i = 0; i < hs.length; i++) {
      var t = clean(hs[i].textContent);
      if (t.length >= 2 && t.length <= 120) { title = t; break; }
    }
  }
  if (!title) {
    // 【别再往 __pace_f 里捞 "desc" 了】
    // 实测：一页里 68 个 desc 全是推荐流的热搜词（"王濛"、"三角洲行动"…），
    // 跟当前作品毫无关系。用它当标题 = 给用户看别人的东西，
    // 比标题空着恶劣得多。宁可空着，让界面显示占位。
  }

  var author = '';
  var links = document.querySelectorAll('a[href*="/user/"]');
  for (var k = 0; k < links.length; k++) {
    var a = links[k];
    if ((a.getAttribute('href') || '').indexOf('self') > -1) continue;
    var tx = clean(a.textContent);
    if (!tx || tx.length > 40) continue;
    if (!(a.offsetWidth || a.offsetHeight || a.getClientRects().length)) continue;
    author = tx; break;
  }
  if (!author) {
    var els = document.querySelectorAll('span, div, a, p');
    for (var z = 0; z < els.length; z++) {
      var el = els[z];
      if (el.children.length > 0) continue;
      var s2 = clean(el.textContent);
      if (s2.length < 2 || s2.length > 30) continue;
      if (s2.charAt(0) !== '@') continue;
      if (!(el.offsetWidth || el.offsetHeight)) continue;
      author = s2.replace(/^@/, ''); break;
    }
  }
  if (!author) author = clean(meta('og:author'));

  var ogImage = meta('og:image');
  if (!ogImage) {
    var v0 = document.querySelector('video');
    if (v0 && v0.poster) ogImage = String(v0.poster);
  }

  return JSON.stringify({ title: title, author: author, ogImage: ogImage });
})()
''';

  /* ------------------------------------------------------------------ */
  /* 小工具                                                              */
  /* ------------------------------------------------------------------ */

  static String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  static List<String> _strList(dynamic v) {
    if (v is! List) return const [];
    return v.map(_str).where((e) => e.isNotEmpty).toList();
  }
}

/// 作品内容形态
enum DouyinKind { video, images, unknown }

/// 归一化之后的链接信息
class DouyinLink {
  final String awemeId;
  final DouyinKind kind;

  /// 还原后的地址（短链还原后会带上 share 参数，报错信息里用它更有用）
  final String resolvedUrl;

  const DouyinLink(this.awemeId, this.kind, this.resolvedUrl);
}

/// 一个解析入口
class _Entry {
  final String label;
  final String url;
  final bool mobile;
  final Duration timeout;

  const _Entry({
    required this.label,
    required this.url,
    required this.mobile,
    required this.timeout,
  });

  /// 导航后的静置时间。
  ///
  /// 【v0.1.0 从 900ms 调到 1200ms】实测：桌面 UA 打开图文页时，900ms 有时
  /// 还没等到 `__pace_f` 就绪（页面骨架出来了、RSC 流还在灌），
  /// 于是只能退回 DOM 抠到 8 张懒加载图 —— 表现就是「46 张的图文只出来 8 张」。
  Duration get settle => const Duration(milliseconds: 900);
}
