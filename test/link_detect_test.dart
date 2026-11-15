// 链接识别矩阵 —— 「各种链接都能识别」这条承诺的自动化守门人。
//
// 【为什么需要这一份】
// App 的第一道关卡是 `LocalRegistry.detect(url)`：它认不出平台，后面写得再好
// 也全都白搭。而「认不出」很容易发生 —— 平台会不断换分享域名（短链、移动站、
// 分享域），加平台时也容易只加主域名忘了短链。
// 这类问题在功能测试里抓不到（功能测试用的是固定几条链接），只能靠**枚举形态**。
//
// 这份测试不碰网络、不碰 WebView，纯字符串判断，所以能在 CI 的桌面环境跑
// （`flutter test` 里就有它），改一行 hosts 就会立刻报警。
//
// 分三组：
//   1. 应该识别的：每个平台的分享短链 / 网页版 / 移动站 / 图文与视频两种形态
//   2. 不应该识别的：图片 CDN、视频 CDN、无关站点、空串 —— 识别错了比识别不出更糟
//   3. 一致性：`kPlatforms`（界面用）与 `LocalRegistry`（解析用）必须是同一套平台

import 'package:flutter_test/flutter_test.dart';
import 'package:flashsave/data/platforms.dart';
import 'package:flashsave/local/registry.dart';

/// 应该被识别成指定平台的链接
const _shouldMatch = <String, String>{
  // ---- 抖音 ----
  'https://v.douyin.com/iRNBho6u/': 'douyin',
  'https://v.douyin.com/dhQYBJNQZis/': 'douyin',
  'https://www.douyin.com/video/7682785097179364069': 'douyin',
  'https://www.douyin.com/note/7683036663006886479': 'douyin',
  'https://www.iesdouyin.com/share/video/7682785097179364069/': 'douyin',
  'https://www.iesdouyin.com/share/note/7683036663006886479/': 'douyin',
  'https://www.iesdouyin.com/share/slides/7683036663006886479/': 'douyin',
  'https://m.douyin.com/share/video/7682785097179364069': 'douyin',
  'https://www.douyin.com/discover?modal_id=7682785097179364069': 'douyin',

  // ---- 小红书 ----
  'https://xhslink.com/a/abc123': 'xhs',
  'https://xhslink.cn/o/1AejNnW65yA': 'xhs',
  'https://www.xiaohongshu.com/explore/65a1b2c3d4e5f6a7b8c9d0e1': 'xhs',
  'https://www.xiaohongshu.com/discovery/item/65a1b2c3d4e5f6a7b8c9d0e1': 'xhs',
  'https://www.xiaohongshu.com/user/profile/5f1a2b3c': 'xhs',

  // ---- 哔哩哔哩 ----
  'https://b23.tv/abc123': 'bilibili',
  'https://b23.tv/AbCdEfG': 'bilibili',
  'https://www.bilibili.com/video/BV1emaA6SE3q': 'bilibili',
  'https://m.bilibili.com/video/BV1emaA6SE3q': 'bilibili',
  'https://www.bilibili.com/video/av123456': 'bilibili',
  'https://www.bilibili.com/read/cv27142128': 'bilibili',
  'https://www.bilibili.com/opus/123456789': 'bilibili',
  'https://t.bilibili.com/123456789': 'bilibili',
  'https://www.bilibili.com/bangumi/play/ep123456': 'bilibili',
  'https://www.acg.tv/video/BV1emaA6SE3q': 'bilibili',

  // ---- 微博 ----
  'https://m.weibo.cn/detail/5345389245106119': 'weibo',
  'https://weibo.com/1234567890/AbCdEfGhI': 'weibo',
  'https://weibo.cn/status/1234567890': 'weibo',
  'https://t.cn/abc123': 'weibo',
  'https://video.weibo.com/show?fid=1034:123456': 'weibo',

  // ---- 快手 ----
  'https://v.kuaishou.com/JjikGmiZ': 'kuaishou',
  'https://www.kuaishou.com/short-video/3xabc123': 'kuaishou',
  'https://v.m.chenzhongtech.com/fw/photo/3xabc123': 'kuaishou',
  'https://www.gifshow.com/s/abc123': 'kuaishou',

  // ---- 知乎 ----
  'https://zhuanlan.zhihu.com/p/28852607': 'zhihu',
  'https://www.zhihu.com/question/12345678/answer/87654321': 'zhihu',
  'https://www.zhihu.com/pin/123456789': 'zhihu',
  'https://www.zhihu.com/zvideo/123456789': 'zhihu',

  // ---- v0.2.0 新增（通用适配器）----
  'https://www.acfun.cn/v/ac41234567': 'acfun',
  'https://m.acfun.cn/v/?ac=41234567': 'acfun',
  'https://h5.pipix.com/s/abc123': 'pipix',
  'https://www.pipix.com/item/7123456789012345678': 'pipix',
  'https://www.izuiyou.com/detail/123456789': 'izuiyou',
  'https://share.izuiyou.com/hybrid/zhi/detail?id=123': 'izuiyou',
  'https://www.miaopai.com/show/abc123.htm': 'miaopai',
  'https://m.miaopai.com/show/abc123.htm': 'miaopai',

  // ---- v0.3.0：HLS 播放列表（没有固定域名，按 .m3u8 后缀识别）----
  'https://example.com/video/index.m3u8': 'hls',
  'https://cdn.example.com/a/b/playlist.M3U8?token=x': 'hls',
  // 即便域名属于别的平台，只要后缀是 .m3u8 就该归 HLS（它是播放列表不是作品页）
  'https://tx-safety-video.acfun.cn/mediacloud/acfun/video-hls_1080p.m3u8?pkey=abc': 'hls',
};

/// 不应该被识别的链接
///
/// 【识别错了比识别不出更糟】用户把一张图片地址、一个不相关站点粘进来，
/// 如果 App 说「已识别到抖音链接」然后解析失败，用户会以为软件坏了；
/// 更糟的是把 CDN 上的素材当成作品去解析，白等十几秒。
const _shouldNotMatch = <String>[
  // 图片 CDN（这些是内容本身，不是作品页）
  'https://p3-sign.douyinpic.com/tos-cn-i-0813/o8FEQArq.webp',
  'https://p1.douyinpic.com/aweme/100x100/aweme-avatar/xxx.jpeg',
  'https://pic1.zhimg.com/v2-178d2d967f20ca74f021c9a117770e0a.jpg',
  'https://i0.hdslb.com/bfs/article/cffce5b4b8d3478233b1c9cfd373123ef381e1e6.jpg',
  'https://sns-img-hw.xhscdn.com/notes_pre_post/1040g3k8324pirqb2go005nhaasvg8bevsq89kdo',
  // 视频 CDN
  'https://v5-hl-mly-ov.zjcdn.com/bbbb0ae1/video/tos/cn/xxx.mp4',
  'https://cn-jsnt-ct-01-01.bilivideo.com/upgcxcode/23/89/xxx.mp4',
  // 无关站点
  'https://github.com/daniei-chen/Little-Whale',
  'https://example.com/video/123',
  'https://www.google.com/',
  // 脏输入
  '',
  '   ',
  '这不是链接',
  'douyin',
  'v.douyin',
];

void main() {
  group('链接识别：应该识别的形态', () {
    for (final entry in _shouldMatch.entries) {
      test('${entry.value} ← ${entry.key}', () {
        final p = LocalRegistry.detect(entry.key);
        expect(p, isNotNull, reason: '这条链接应该被识别为 ${entry.value}，但没识别出来：${entry.key}');
        expect(p!.key, entry.value,
            reason: '${entry.key} 应该归 ${entry.value}，实际归 ${p.key}（${p.name}）');
      });
    }
  });

  group('链接识别：不应该识别的形态', () {
    for (final url in _shouldNotMatch) {
      test('不该识别：${url.isEmpty ? '(空串)' : url}', () {
        final p = LocalRegistry.detect(url);
        expect(p, isNull, reason: '这条不该被识别成任何平台，实际识别成了 ${p?.name}：$url');
      });
    }
  });

  group('两套平台表必须一致', () {
    test('LocalRegistry 里每个平台在 kPlatforms 里都有对应项', () {
      for (final p in LocalRegistry.all) {
        final meta = kPlatforms.where((m) => m.key == p.key).toList();
        expect(meta.length, 1,
            reason: '${p.name}（key=${p.key}）在 kPlatforms 里应当正好有一条，实际 ${meta.length} 条');
      }
    });

    test('kPlatforms 里每个平台在 LocalRegistry 里都有对应项', () {
      for (final m in kPlatforms) {
        final p = LocalRegistry.all.where((e) => e.key == m.key).toList();
        expect(p.length, 1,
            reason: '${m.name}（key=${m.key}）在 LocalRegistry 里应当正好有一条，实际 ${p.length} 条');
      }
    });

    test('两边数量一致（加平台时不会只改一边）', () {
      expect(LocalRegistry.all.length, kPlatforms.length,
          reason: 'kPlatforms=${kPlatforms.length}，LocalRegistry=${LocalRegistry.all.length}');
    });

    test('每个平台的 hosts 都不为空（否则永远识别不到）', () {
      for (final p in LocalRegistry.all) {
        // hls 是例外：它没有固定域名，由 detect() 按 `.m3u8` 后缀单独识别
        if (p.key == 'hls') continue;
        expect(p.hosts, isNotEmpty, reason: '${p.name} 没有配置 hosts');
      }
    });

    test('两个表的 hosts 必须逐项一致', () {
      // 【为什么这条重要】`kPlatforms` 决定界面上那句「已识别到 XX 链接」，
      // `LocalRegistry` 决定真正能不能解析。两边不一致时，
      // 用户会看到「识别到了」然后解析失败 —— 这是最伤体验的一种 bug。
      // 实测就踩过：知乎的 `zhimg.com` 只在 kPlatforms 里，粘一张知乎图会
      // 提示识别成功但解析说「不支持」。
      for (final p in LocalRegistry.all) {
        final meta = kPlatforms.where((m) => m.key == p.key).toList();
        expect(meta.length, 1, reason: '${p.name} 在 kPlatforms 里条数不对');
        final a = p.hosts.map((e) => e.toLowerCase()).toSet();
        final b = meta.single.hosts.map((e) => e.toLowerCase()).toSet();
        expect(a, b,
            reason: '${p.name} 的 hosts 两边不一致：'
                'LocalRegistry=${a.toList()}，kPlatforms=${b.toList()}');
      }
    });

    test('hosts 里不该出现内容 CDN 域名', () {
      // 这些是「图片/视频本体」的域名，粘进来不应该被当成作品页
      const cdnSuffixes = ['douyinpic.com', 'zhimg.com', 'hdslb.com', 'bilivideo.com', 'xhscdn.com'];
      for (final p in LocalRegistry.all) {
        for (final h in p.hosts) {
          for (final cdn in cdnSuffixes) {
            expect(h, isNot(contains(cdn)),
                reason: '${p.name} 的 hosts 里不该有 CDN 域名 $h —— 用户粘贴图片地址会被误识别成作品');
          }
        }
      }
    });
  });
}
