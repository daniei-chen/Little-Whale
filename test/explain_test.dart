// 「粘错链接时说什么」的集中测试。
//
// 【为什么单独一份】这类文案是**用户唯一能看到的东西**。解析失败本身不可怕，
// 可怕的是失败得莫名其妙 —— 用户会觉得软件坏了，而不是「我粘错了页面的类型」。
//
// 六个核心平台各有一个 `explainNonContentUrl`（小红书叫 `explainNonNoteUrl`），
// 它们都是**纯字符串判断**，所以能在桌面 `flutter test` 里全覆盖。
//
// 每个平台都有两组断言：
//   1. 非内容页 → 提到该页面的类型（用户一看就懂）
//   2. 正常内容链接 → 返回 null（不能误伤，否则正常链接会被拦下来）

import 'package:flutter_test/flutter_test.dart';

import 'package:flashsave/local/bilibili.dart';
import 'package:flashsave/local/douyin.dart';
import 'package:flashsave/local/kuaishou.dart';
import 'package:flashsave/local/weibo.dart';
import 'package:flashsave/local/xiaohongshu.dart';

void main() {
  group('B站', () {
    String? e(String u) => BilibiliLocalPlatform.explainNonContentUrl(u);

    test('直播间', () => expect(e('https://live.bilibili.com/12345'), contains('直播')));
    test('用户空间', () => expect(e('https://space.bilibili.com/123456'), contains('用户空间')));
    test('收藏夹', () => expect(e('https://www.bilibili.com/list/ml123456'), contains('收藏夹')));
    test('番剧索引页', () => expect(e('https://www.bilibili.com/bangumi/'), contains('番剧')));

    test('番剧具体一集不算非内容页', () {
      expect(e('https://www.bilibili.com/bangumi/play/ep123456'), isNull);
      expect(e('https://www.bilibili.com/bangumi/play/ss12345'), isNull);
    });

    test('正常内容链接不误伤', () {
      expect(e('https://www.bilibili.com/video/BV1emaA6SE3q'), isNull);
      expect(e('https://www.bilibili.com/read/cv27142128'), isNull);
      expect(e('https://b23.tv/abc123'), isNull);
    });
  });

  group('微博', () {
    String? e(String u) => WeiboLocalPlatform.explainNonContentUrl(u);

    test('用户主页', () {
      expect(e('https://weibo.com/u/1234567890'), contains('用户主页'));
      expect(e('https://weibo.com/n/%E6%9F%90%E4%BA%BA'), contains('用户主页'));
    });
    test('话题页', () => expect(e('https://weibo.com/p/100808abc'), contains('话题')));
    test('视频列表页', () {
      expect(e('https://weibo.com/tv/videos'), contains('视频列表'));
    });

    test('正常内容链接不误伤', () {
      expect(e('https://m.weibo.cn/detail/5345389245106119'), isNull);
      expect(e('https://weibo.com/1234567890/AbCdEfGhI'), isNull);
      expect(e('https://video.weibo.com/show?fid=1034:123456'), isNull);
      expect(e('https://t.cn/abc123'), isNull);
    });
  });

  group('快手', () {
    String? e(String u) => KuaishouLocalPlatform.explainNonContentUrl(u);

    test('直播间', () => expect(e('https://live.kuaishou.com/u/abc123'), contains('直播')));
    test('用户主页', () => expect(e('https://www.kuaishou.com/profile/3xabc'), contains('用户主页')));

    test('正常内容链接不误伤', () {
      expect(e('https://v.kuaishou.com/JjikGmiZ'), isNull);
      expect(e('https://www.kuaishou.com/short-video/3xabc123'), isNull);
    });
  });

  group('抖音（回归：确认没被后面的改动带坏）', () {
    String? e(String u) => DouyinLocalPlatform.explainNonWorkUrl(u);

    test('用户主页 / 合集 / 直播 / 搜索 / 首页', () {
      expect(e('https://www.douyin.com/user/MS4wLjAB'), contains('用户主页'));
      expect(e('https://www.douyin.com/collection/123'), contains('合集'));
      expect(e('https://live.douyin.com/123'), contains('直播'));
      expect(e('https://www.douyin.com/search/x'), contains('搜索结果'));
      expect(e('https://www.douyin.com/discover'), contains('首页'));
    });

    test('正常作品链接不误伤', () {
      expect(e('https://www.douyin.com/video/7682785097179364069'), isNull);
      expect(e('https://www.douyin.com/discover?modal_id=7682785097179364069'), isNull);
      expect(e('https://v.douyin.com/dhQYBJNQZis/'), isNull);
    });
  });

  group('小红书（回归）', () {
    String? e(String u) => XiaohongshuLocalPlatform.explainNonNoteUrl(u);

    test('用户主页 / 合辑 / 商品页', () {
      expect(e('https://www.xiaohongshu.com/user/profile/5f0a'), contains('用户主页'));
      expect(e('https://www.xiaohongshu.com/board/abc'), contains('合辑'));
      expect(e('https://www.xiaohongshu.com/goods/123'), contains('商品'));
    });

    test('正常笔记链接不误伤', () {
      expect(e('https://www.xiaohongshu.com/explore/65a1b2c3d4e5f6a7b8c9d0e1'), isNull);
      expect(e('https://xhslink.com/a/abc123'), isNull);
    });
  });
}
