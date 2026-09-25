import 'bilibili.dart';
import 'douyin.dart';
import 'generic.dart';
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
  ];

  /// 按 URL 找平台，找不到返回 null
  static LocalPlatform? detect(String? url) {
    if (url == null || url.isEmpty) return null;
    final lower = url.toLowerCase();
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
