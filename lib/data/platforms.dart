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
