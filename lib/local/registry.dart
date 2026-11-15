import 'bilibili.dart';
import 'douyin.dart';
import 'generic.dart';
import 'hls_platform.dart';
import 'kuaishou.dart';
import 'types.dart';
import 'weibo.dart';
import 'xiaohongshu.dart';
import 'zhihu.dart';

export 'types.dart';

/// 平台注册表。
///
/// 分成两层：
///
/// **① 专用适配器** —— 抖音 / 小红书 / B站 / 微博 / 快手 / 知乎。
/// 每个平台单独逆推过，能拿到**无水印原图**、能识别**动图**、速度快。
///
/// **② 通用适配器** —— 其余主流平台。
/// 实测西瓜视频 / 今日头条 / 好看视频 / 豆瓣 / 贴吧 / 优酷 / 爱奇艺 /
/// 腾讯视频 / 芒果TV / 虎牙 / 斗鱼 / 微视的网页**全是 SPA**：
/// 首页 HTML 只有几 KB 空壳，数据全靠 JS 渲染。直接 HTTP 抓什么都拿不到，
/// 但我们的隐藏 WebView 能让页面**真的跑起来**，再读渲染后的 DOM 就有内容。
///
/// 通用适配器拿不到无水印原图（平台的页面本来给的就是带水印的流），
/// 也识别不了动图 —— 这是「先保证能用」的取舍。等某个平台用的人多了，
/// 再单独做专用适配器优化。
class LocalRegistry {
  LocalRegistry._();

  /// 全部平台（专用在前，通用在后 —— 顺序决定 `detect` 的优先级）
  static final List<LocalPlatform> all = <LocalPlatform>[
    // ---- ① 专用适配器 ----
    DouyinLocalPlatform(),
    XiaohongshuLocalPlatform(),
    BilibiliLocalPlatform(),
    WeiboLocalPlatform(),
    KuaishouLocalPlatform(),
    ZhihuLocalPlatform(),

    // ---- ② 通用适配器 ----
    //
    // 【为什么用桌面 UA + 全页找 video/img】
    // 这些平台的移动页往往更封闭（要求 App 内打开），桌面页反而宽松。
    // 通用适配器的实现见 lib/local/generic.dart。
    GenericLocalPlatform(
      key: 'ixigua',
      name: '西瓜视频',
      hosts: const ['ixigua.com'],
      referer: 'https://www.ixigua.com/',
    ),
    GenericLocalPlatform(
      key: 'toutiao',
      name: '今日头条',
      hosts: const ['toutiao.com'],
      referer: 'https://www.toutiao.com/',
    ),
    GenericLocalPlatform(
      key: 'haokan',
      name: '好看视频',
      hosts: const ['haokan.baidu.com'],
      referer: 'https://haokan.baidu.com/',
      imageAllow: const ['baidu.com', 'bdstatic.com'],
    ),
    GenericLocalPlatform(
      key: 'weishi',
      name: '微视',
      hosts: const ['weishi.qq.com'],
      referer: 'https://isee.weishi.qq.com/',
    ),
    GenericLocalPlatform(
      key: 'douban',
      name: '豆瓣',
      hosts: const ['douban.com'],
      referer: 'https://www.douban.com/',
      imageAllow: const ['doubanio.com', 'douban.com'],
    ),
    GenericLocalPlatform(
      key: 'tieba',
      name: '百度贴吧',
      hosts: const ['tieba.baidu.com'],
      referer: 'https://tieba.baidu.com/',
      imageAllow: const ['baidu.com', 'bdstatic.com', 'bdimg.com'],
    ),
    GenericLocalPlatform(
      key: 'qqvideo',
      name: '腾讯视频',
      hosts: const ['v.qq.com'],
      referer: 'https://v.qq.com/',
    ),
    GenericLocalPlatform(
      key: 'iqiyi',
      name: '爱奇艺',
      hosts: const ['iqiyi.com'],
      referer: 'https://www.iqiyi.com/',
    ),
    GenericLocalPlatform(
      key: 'youku',
      name: '优酷',
      hosts: const ['youku.com'],
      referer: 'https://www.youku.com/',
    ),
    GenericLocalPlatform(
      key: 'mgtv',
      name: '芒果TV',
      hosts: const ['mgtv.com'],
      referer: 'https://www.mgtv.com/',
    ),
    GenericLocalPlatform(
      key: 'huya',
      name: '虎牙',
      hosts: const ['huya.com'],
      referer: 'https://www.huya.com/',
    ),
    GenericLocalPlatform(
      key: 'douyu',
      name: '斗鱼',
      hosts: const ['douyu.com'],
      referer: 'https://www.douyu.com/',
    ),

    // ---- ③ v0.2.0 新增：短视频 / 弹幕站 ----
    //
    // 【为什么用通用适配器而不是专用适配器】
    // 专用适配器要逐个逆向（数据落在哪个 window 变量、哪个 DOM 容器），
    // 每加一个都是几天工作量 + 持续维护。这四家目前的量级还不够，
    // 先用通用适配器把「能识别、能渲染、能取到 <video> / <img>」走通 ——
    // 用户在 App 里能直接用，我们也能从真实反馈判断值不值得做专用。
    // 通用适配器的已知边界（拿不到无水印原图、识别不了动图）同样适用。
    GenericLocalPlatform(
      key: 'acfun',
      name: 'AcFun',
      hosts: const ['acfun.cn'],
      referer: 'https://www.acfun.cn/',
      // 实测（2026-11，真实作品页 ac41234567）：播放器给的是
      // ...-hls_1080p_h264_60_1.m3u8，是分段流不是文件。
      failHint: 'AcFun 的视频是 HLS 流式格式（m3u8 分段流），App 暂不支持直接保存。',
      // 播放器要 5 秒以上才挂 src，不标这个会时好时坏地判成图文
      expectVideo: true,
    ),
    GenericLocalPlatform(
      key: 'pipix',
      name: '皮皮虾',
      hosts: const ['pipix.com'],
      referer: 'https://h5.pipix.com/',
      // 【实测更正】上一版我只看过首页 `h5.pipix.com`（那是 APP 下载引导页），
      // 就写下"作品只在 App 里"——**这个判断是错的**。
      // 真实作品页 `h5.pipix.com/s/xxx/` 是正常渲染的：
      //   <video src="https://v26-cdn-tos.ppxvod.com/.../video/tos/cn/...">
      // 实测该地址 Range 请求返回 206 video/mp4、文件头 ftyp isom —— 能直接下载。
      // 所以这里不需要 failHint，正常走通用提取。
    ),
    GenericLocalPlatform(
      key: 'izuiyou',
      name: '最右',
      hosts: const ['izuiyou.com'],
      referer: 'https://www.izuiyou.com/',
    ),
    GenericLocalPlatform(
      key: 'miaopai',
      name: '秒拍',
      hosts: const ['miaopai.com'],
      referer: 'https://www.miaopai.com/',
    ),

    // ---- ④ HLS 播放列表（没有固定域名，按 .m3u8 后缀识别）----
    //
    // AcFun 那类站在隐藏 WebView 里拿不到 `<video>`（明文被禁，播放器不初始化），
    // 所以把 m3u8 直链本身做成一等公民：用户从别处拿到播放列表地址就能存。
    HlsLocalPlatform(),
  ];

  /// 按 URL 找平台，找不到返回 null
  static LocalPlatform? detect(String? url) {
    if (url == null || url.isEmpty) return null;
    final lower = url.toLowerCase();
    // m3u8 直链没有固定域名，按后缀识别。
    // **必须在域名匹配之前判断** —— 否则像 `...douyinpic.com/x.m3u8`
    // 这种会被域名规则抢先归到抖音，然后按图片/作品去解析，必然失败。
    if (lower.contains('.m3u8')) return HlsLocalPlatform();
    for (final p in all) {
      for (final h in p.hosts) {
        if (lower.contains(h)) return p;
      }
    }
    return null;
  }

  /// 这个链接本地能解析吗
  static bool canParseLocally(String url) => detect(url) != null;

  /// 已支持的平台名（给界面用）
  static List<String> get supportedNames => all.map((e) => e.name).toList();

  /// 专用适配器的平台名（准确度高、能去水印的那些）
  static List<String> get coreNames => all
      .where((e) => e is! GenericLocalPlatform)
      .map((e) => e.name)
      .toList();

  /// 通用适配器的平台名
  static List<String> get genericNames => all
      .whereType<GenericLocalPlatform>()
      .map((e) => e.name)
      .toList();
}
