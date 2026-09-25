import 'package:flutter/material.dart';

/// 平台元信息。
///
/// 这里驱动两件事：
///   1. 首页那几个平台标签
///   2. 粘贴链接时「已识别到 XX 链接」的提示
/// 所以加了新平台**一定要同步这里** —— 否则解析已经支持了，界面上却看不到，
/// 用户会以为没做（踩过：快手/微博/知乎做完后首页还是只显示三个）。
class PlatformMeta {
  final String key;
  final String name;
  final String short;
  final Color color;
  final Color soft;
  final List<String> hosts;
  final List<String> keywords;

  const PlatformMeta({
    required this.key,
    required this.name,
    required this.short,
    required this.color,
    required this.soft,
    required this.hosts,
    required this.keywords,
  });
}

const kPlatforms = <PlatformMeta>[
  PlatformMeta(
    key: 'douyin',
    name: '抖音',
    short: '抖',
    color: Color(0xFF161823),
    soft: Color(0x12161823), // rgba(22,24,35,.07)
    hosts: ['v.douyin.com', 'www.iesdouyin.com', 'iesdouyin.com', 'douyin.com', 'douyin'],
    keywords: ['抖音', 'dou音'],
  ),
  PlatformMeta(
    key: 'xhs',
    name: '小红书',
    short: '红',
    color: Color(0xFFFF2442),
    soft: Color(0x12FF2442), // rgba(255,36,66,.07)
    hosts: ['xhslink.com', 'xhslink.cn', 'xiaohongshu.com'],
    keywords: ['小红书'],
  ),
  PlatformMeta(
    key: 'bilibili',
    name: '哔哩哔哩',
    short: 'B',
    color: Color(0xFF00A1D6),
    soft: Color(0x1400A1D6), // rgba(0,161,214,.08)
    hosts: ['b23.tv', 'bilibili.com', 'acg.tv'],
    keywords: ['哔哩哔哩', 'bilibili', 'b站', '哔哩'],
  ),
  PlatformMeta(
    key: 'weibo',
    name: '微博',
    short: '微',
    color: Color(0xFFE6162D),
    soft: Color(0x12E6162D),
    hosts: ['weibo.com', 'weibo.cn', 't.cn'],
    keywords: ['微博', 'weibo'],
  ),
  PlatformMeta(
    key: 'kuaishou',
    name: '快手',
    short: '快',
    color: Color(0xFFFF5000),
    soft: Color(0x12FF5000),
    // chenzhongtech 是快手分享页的真实域名（v.kuaishou.com 会跳到那里）
    hosts: ['kuaishou.com', 'chenzhongtech.com', 'gifshow.com'],
    keywords: ['快手', 'kuaishou'],
  ),
  PlatformMeta(
    key: 'zhihu',
    name: '知乎',
    short: '知',
    color: Color(0xFF0084FF),
    soft: Color(0x120084FF),
    hosts: ['zhihu.com', 'zhimg.com'],
    keywords: ['知乎', 'zhihu'],
  ),
  // ---- 下面这些走「通用适配器」（见 lib/local/generic.dart）----
  //
  // 【为什么要分开列】它们的网页实测**全是 SPA**：首页 HTML 只有几 KB 空壳，
  // 数据全靠 JS 渲染。直接 HTTP 抓什么都拿不到，只能靠内置 WebView
  // 把页面真的跑起来再读 DOM。
  //
  // 代价是：**拿不到无水印原图，也识别不了动图** ——
  // 平台页面上给的就是带水印的流。这是「先保证能用」的取舍。
  PlatformMeta(
    key: 'ixigua', name: '西瓜视频', short: '西',
    color: Color(0xFF1E90FF), soft: Color(0x121E90FF),
    hosts: ['ixigua.com'], keywords: ['西瓜视频', 'ixigua'],
  ),
  PlatformMeta(
    key: 'toutiao', name: '今日头条', short: '头',
    color: Color(0xFFF04142), soft: Color(0x12F04142),
    hosts: ['toutiao.com'], keywords: ['今日头条', '头条'],
  ),
  PlatformMeta(
    key: 'haokan', name: '好看视频', short: '好',
    color: Color(0xFF2932E1), soft: Color(0x122932E1),
    hosts: ['haokan.baidu.com'], keywords: ['好看视频', 'haokan'],
  ),
  PlatformMeta(
    key: 'weishi', name: '微视', short: '微',
    color: Color(0xFF12B7F5), soft: Color(0x1212B7F5),
    hosts: ['weishi.qq.com'], keywords: ['微视', 'weishi'],
  ),
  PlatformMeta(
    key: 'douban', name: '豆瓣', short: '豆',
    color: Color(0xFF2E963D), soft: Color(0x122E963D),
    hosts: ['douban.com'], keywords: ['豆瓣', 'douban'],
  ),
  PlatformMeta(
    key: 'tieba', name: '百度贴吧', short: '贴',
    color: Color(0xFF3385FF), soft: Color(0x123385FF),
    hosts: ['tieba.baidu.com'], keywords: ['贴吧', 'tieba'],
  ),
  PlatformMeta(
    key: 'qqvideo', name: '腾讯视频', short: '腾',
    color: Color(0xFF1BAAFB), soft: Color(0x121BAAFB),
    hosts: ['v.qq.com'], keywords: ['腾讯视频'],
  ),
  PlatformMeta(
    key: 'iqiyi', name: '爱奇艺', short: '爱',
    color: Color(0xFF00BE06), soft: Color(0x1200BE06),
    hosts: ['iqiyi.com'], keywords: ['爱奇艺', 'iqiyi'],
  ),
  PlatformMeta(
    key: 'youku', name: '优酷', short: '优',
    color: Color(0xFF1B9EF5), soft: Color(0x121B9EF5),
    hosts: ['youku.com'], keywords: ['优酷', 'youku'],
  ),
  PlatformMeta(
    key: 'mgtv', name: '芒果TV', short: '芒',
    color: Color(0xFFFF7300), soft: Color(0x12FF7300),
    hosts: ['mgtv.com'], keywords: ['芒果', 'mgtv'],
  ),
  PlatformMeta(
    key: 'huya', name: '虎牙', short: '虎',
    color: Color(0xFFFF9F00), soft: Color(0x12FF9F00),
    hosts: ['huya.com'], keywords: ['虎牙', 'huya'],
  ),
  PlatformMeta(
    key: 'douyu', name: '斗鱼', short: '斗',
    color: Color(0xFFFF5D23), soft: Color(0x12FF5D23),
    hosts: ['douyu.com'], keywords: ['斗鱼', 'douyu'],
  ),
];

/// 从一段分享文案里抓出第一个可用的链接。
///
/// 逻辑与小程序端 `utils/parser.js` 的 extractUrl 对齐：
/// 结尾常见的标点会被误吞，需要剥掉。
String? extractUrl(String? text) {
  if (text == null) return null;
  final re = RegExp(r"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+");
  final m = re.firstMatch(text);
  if (m == null) return null;
  var url = m.group(0)!;
  url = url.replaceAll(RegExp(r'[.,;，。；、]+$'), '');
  return url.isEmpty ? null : url;
}

/// 按域名或关键词识别平台
PlatformMeta? detectPlatform(String? text) {
  if (text == null || text.isEmpty) return null;
  final lower = text.toLowerCase();

  for (final p in kPlatforms) {
    for (final h in p.hosts) {
      if (lower.contains(h)) return p;
    }
  }
  for (final p in kPlatforms) {
    for (final w in p.keywords) {
      if (lower.contains(w.toLowerCase())) return p;
    }
  }
  return null;
}

/// 按 key 取平台
PlatformMeta? platformByKey(String? key) {
  if (key == null) return null;
  for (final p in kPlatforms) {
    if (p.key == key) return p;
  }
  return null;
}
