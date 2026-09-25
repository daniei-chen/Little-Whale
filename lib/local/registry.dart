/// 平台注册表：新增一个平台，只要实现 [LocalPlatform] 再在这里加一行。
library;

import 'bilibili.dart';
import 'douyin.dart';
import 'kuaishou.dart';
import 'types.dart';
import 'weibo.dart';
import 'xiaohongshu.dart';
import 'zhihu.dart';

export 'types.dart';

class LocalRegistry {
  LocalRegistry._();

  /// 已实现的平台
  static final List<LocalPlatform> all = <LocalPlatform>[
    DouyinLocalPlatform(),
    XiaohongshuLocalPlatform(),
    BilibiliLocalPlatform(),
    WeiboLocalPlatform(),
    KuaishouLocalPlatform(),
    ZhihuLocalPlatform(),
  ];

  /// 按链接识别平台；识别不到返回 null
  static LocalPlatform? detect(String url) {
    for (final p in all) {
      if (p.matches(url)) return p;
    }
    return null;
  }

  /// 本地模式支持的所有平台名（给 UI 展示）
  static List<String> get supportedNames => all.map((e) => e.name).toList();

  /// 这个链接能不能本地解析
  static bool canParseLocally(String url) =>
      url.isNotEmpty && detect(url) != null;
}
