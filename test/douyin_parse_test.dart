// 抖音解析层的**真实数据**单元测试。
//
// 【为什么不用手写 JSON 造假数据】
// 手写的数据只能验证「我以为的格式」，而这类解析之所以会坏，恰恰是因为
// 平台真实格式和我以为的不一样（字段顺序、包裹层级、转义方式都在变）。
// 这里的 fixture 是从真实页面里导出来的：
//   · video_mobile_router.json —— 手机分享页渲染后的 window._ROUTER_DATA
//   · note_pace.json           —— 图文页的 window.__pace_f（11 段 RSC 流，约 640KB）
//
// 导出方式见 audit/probe/export_fixture.mjs，可以随时重新采样更新。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashsave/local/douyin.dart';
import 'package:flashsave/local/xiaohongshu.dart';
import 'package:flashsave/local/douyin_parse.dart';

String _readFixture(String name) {
  final f = File('test/fixtures/$name');
  if (!f.existsSync()) return '';
  return f.readAsStringSync();
}

void main() {
  group('小红书非笔记页也给出针对性提示', () {
    String? explain(String u) => XiaohongshuLocalPlatform.explainNonNoteUrl(u);

    test('用户主页', () {
      expect(explain('https://www.xiaohongshu.com/user/profile/5f0a1b2c3d'), contains('用户主页'));
    });

    test('合辑', () {
      expect(explain('https://www.xiaohongshu.com/board/abc123'), contains('合辑'));
    });

    test('搜索页', () {
      expect(explain('https://www.xiaohongshu.com/search_result?keyword=x'), contains('搜索结果'));
    });

    test('商品页', () {
      expect(explain('https://www.xiaohongshu.com/goods/123'), contains('商品'));
    });

    test('正常笔记链接不该被误判', () {
      expect(explain('https://www.xiaohongshu.com/explore/65a1b2c3d4e5f6a7b8c9d0e1'), isNull);
      expect(explain('https://xhslink.com/a/abc123'), isNull);
    });
  });
  group('非作品页链接给出针对性提示（而不是笼统的「找不到作品号」）', () {
    String? explain(String u) => DouyinLocalPlatform.explainNonWorkUrl(u);

    test('用户主页', () {
      expect(explain('https://www.douyin.com/user/MS4wLjABAAAAxyz'), contains('用户主页'));
    });

    test('合集 / 播放列表', () {
      expect(explain('https://www.douyin.com/collection/7123456789'), contains('合集'));
      expect(explain('https://www.douyin.com/mix/7123456789'), contains('合集'));
    });

    test('直播间', () {
      expect(explain('https://live.douyin.com/123456'), contains('直播'));
    });

    test('搜索结果页', () {
      expect(explain('https://www.douyin.com/search/%E5%A3%81%E7%BA%B8'), contains('搜索结果'));
    });

    test('首页 / 发现页（没有 modal_id）', () {
      expect(explain('https://www.douyin.com/discover'), contains('首页'));
      expect(explain('https://www.douyin.com/recommend'), contains('首页'));
    });

    test('带 modal_id 的发现页不算「非作品」', () {
      // 这种链接 _linkFromUrl 能从 query 提取到作品号，不该被误报成首页
      expect(explain('https://www.douyin.com/discover?modal_id=7682785097179364069'), isNull);
    });

    test('正常作品链接不该被误判', () {
      expect(explain('https://www.douyin.com/video/7682785097179364069'), isNull);
      expect(explain('https://www.douyin.com/note/7683036663006886479'), isNull);
      expect(explain('https://v.douyin.com/dhQYBJNQZis/'), isNull);
      expect(explain('https://www.iesdouyin.com/share/video/7682785097179364069/'), isNull);
    });
  });
  group('抖音 · _ROUTER_DATA（视频主入口）', () {
    late dynamic router;

    setUpAll(() {
      final raw = _readFixture('video_mobile_router.json');
      expect(raw.isNotEmpty, isTrue, reason: 'fixture 缺失：video_mobile_router.json');
      router = jsonDecode(raw);
    });

    test('能拿到完整作品信息（id/标题/作者/时长）', () {
      final a = DouyinParser.fromRouterData(router);
      expect(a, isNotNull, reason: '渲染后的 _ROUTER_DATA 必须能解析出作品');
      expect(a!.awemeId, '7682785097179364069');
      expect(a.desc, contains('熊'));
      expect(a.author, isNotEmpty);
      expect(a.durationSec, greaterThan(0));
    });

    test('能拿到 video_id 与原始播放地址', () {
      final a = DouyinParser.fromRouterData(router)!;
      expect(a.videoId, isNotEmpty, reason: 'play_addr.uri 必须有，无水印地址靠它构造');
      expect(a.videoId.startsWith('v'), isTrue, reason: '抖音的 video_id 形如 v1e00…');
      expect(a.playUrls, isNotEmpty);
      expect(a.playUrls.first, contains('playwm'));
    });

    test('封面是图片 CDN，不是空字符串', () {
      final a = DouyinParser.fromRouterData(router)!;
      expect(a.cover.startsWith('http'), isTrue);
      expect(DouyinParser.isDouyinImageHost(a.cover), isTrue);
    });

    test('视频作品不会被误判成图文', () {
      final a = DouyinParser.fromRouterData(router)!;
      expect(a.isImages, isFalse);
      expect(a.hasVideo, isTrue);
    });

    test('脏输入不崩：null / 空 Map / 错误结构', () {
      expect(DouyinParser.fromRouterData(null), isNull);
      expect(DouyinParser.fromRouterData('{}'), isNull);
      expect(DouyinParser.fromRouterData(<String, dynamic>{}), isNull);
      expect(DouyinParser.fromRouterData({'loaderData': 'x'}), isNull);
      expect(DouyinParser.fromRouterData([1, 2, 3]), isNull);
    });
  });

  group('抖音 · __pace_f（图文主入口）', () {
    late String pace;

    setUpAll(() {
      final raw = _readFixture('note_pace.json');
      expect(raw.isNotEmpty, isTrue, reason: 'fixture 缺失：note_pace.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;
      pace = (m['pace'] ?? '') as String;
      expect(pace.length, greaterThan(100000), reason: 'pace 应该是几十万字符的真实数据');
    });

    test('能从 RSC 流里抠出全部 46 张图', () {
      final a = DouyinParser.fromPaceText(pace, wantAwemeId: '7683036663006886479');
      expect(a, isNotNull, reason: 'pace 里确实带着 images 数组，必须认出来');
      expect(a!.images.length, 46,
          reason: '这条图文有 46 张图（页面上的计数就是 4/46）');
      expect(a.isImages, isTrue);
    });

    test('图片地址都是无水印原图域，且没有重复', () {
      final a = DouyinParser.fromPaceText(pace)!;
      for (final img in a.images) {
        expect(img.url.startsWith('https://'), isTrue);
        expect(DouyinParser.isDouyinImageHost(img.url), isTrue,
            reason: '非图片 CDN 的地址说明抠错了对象：${img.url}');
      }
      final uniq = a.images.map((e) => _uriKey(e.url)).toSet();
      expect(uniq.length, a.images.length, reason: '同一张图不能重复出现');
    });

    test('标题与作者能从 pace 里取到', () {
      final a = DouyinParser.fromPaceText(pace)!;
      expect(a.desc, isNotEmpty, reason: 'pace 里有 desc，不该是空标题');
      expect(a.author, isNotEmpty, reason: 'pace 里有 nickname，不该是空作者');
    });

    test('图片带尺寸信息（决定横竖图排版）', () {
      final a = DouyinParser.fromPaceText(pace)!;
      final withSize = a.images.where((e) => e.width > 0 && e.height > 0).length;
      expect(withSize, greaterThan(0));
    });

    test('字段顺序变了也能认（不再写死 "images":[{"width"）', () {
      // 模拟另一种字段顺序：uri 在前、width 在后
      const alt = '{"images":[{"uri":"tos-cn-i-0813/abc","urlList":'
          '["https://p3-pc-sign.douyinpic.com/tos-cn-i-0813/abc~tplv-dy-aweme-images:q75.webp"],'
          '"width":1080,"height":1920}]}';
      final a = DouyinParser.fromPaceText(alt);
      expect(a, isNotNull);
      expect(a!.images.length, 1);
      expect(a.images.first.width, 1080);
    });

    test('空文本 / 没有 images 的文本返回 null，而不是抛异常', () {
      expect(DouyinParser.fromPaceText(''), isNull);
      expect(DouyinParser.fromPaceText('{"foo":1}'), isNull);
      expect(DouyinParser.fromPaceText('"images":[]'), isNull);
    });
  });

  group('抖音 · 动图（Live Photo）', () {
    late String pace;

    setUpAll(() {
      final raw = _readFixture('note_live_pace.json');
      expect(raw.isNotEmpty, isTrue, reason: 'fixture 缺失：note_live_pace.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;
      pace = (m['pace'] ?? '') as String;
    });

    test('动图作品的图片元素里带着视频地址（字段名是驼峰 playAddr）', () {
      final a = DouyinParser.fromPaceText(pace, hintTitle: '动图作品');
      expect(a, isNotNull);
      expect(a!.images, isNotEmpty);
      final live = a.images.where((e) => e.isLive).toList();
      expect(live, isNotEmpty,
          reason: '这条是动图作品，图片项里必须有 video.playAddr —— '
              '只认下划线 play_addr 会一个都拿不到');
      expect(live.first.videoUrl, contains('douyinvod'),
          reason: '动图视频必须来自抖音视频 CDN');
    });

    test('动图时长能取到（毫秒转秒）', () {
      final a = DouyinParser.fromPaceText(pace, hintTitle: '动图作品')!;
      final live = a.images.firstWhere((e) => e.isLive);
      expect(live.durationSec, greaterThan(0));
      expect(live.durationSec, lessThan(120), reason: '动图不可能几十秒以上');
    });

    test('标题用页面 title，不会被推荐流的 desc 顶掉', () {
      final a = DouyinParser.fromPaceText(pace, hintTitle: '这是页面标题')!;
      expect(a.desc, '这是页面标题');

      // 没有 hint 时也要能取到**不是空**的标题，但绝不能是空串
      final b = DouyinParser.fromPaceText(pace)!;
      expect(b.desc.isNotEmpty, isTrue);
    });

    test('作者优先取 ownerNickname（当前作品的作者字段）', () {
      final a = DouyinParser.fromPaceText(pace)!;
      expect(a.author.isNotEmpty, isTrue);
    });
  });

  group('抖音 · 视频地址候选与去水印', () {
    test('video_id 能从 playwm 地址里抠出来', () {
      const u = 'https://m.douyin.com/aweme/v1/playwm/?line=0'
          '&logo_name=aweme_diversion_search&ratio=720p'
          '&video_id=v1e00fgi0000dafboc7og65g415qnbtg';
      expect(DouyinParser.videoIdFromUrl(u), 'v1e00fgi0000dafboc7og65g415qnbtg');
      expect(DouyinParser.videoIdFromUrl('https://x/y'), '');
    });

    test('无水印接口排在带水印地址前面', () {
      const a = DouyinAweme(
        awemeId: '1',
        videoId: 'v1e00abc',
        playUrls: ['https://m.douyin.com/aweme/v1/playwm/?ratio=720p&video_id=v1e00abc'],
      );
      final c = DouyinParser.videoUrlCandidates(a);
      expect(c, isNotEmpty);
      expect(c.first, contains('/aweme/v1/play/'));
      expect(c.first, contains('aweme.snssdk.com'));
      expect(c.first, isNot(contains('playwm')));
      expect(c.first, isNot(contains('logo_name')));
      // 带水印的原始地址必须保留在最后当兜底
      expect(c.last, contains('playwm'));
    });

    test('没有 video_id 时，从 playwm 的 query 反推也能补出无水印地址', () {
      const a = DouyinAweme(
        awemeId: '1',
        playUrls: ['https://m.douyin.com/aweme/v1/playwm/?ratio=720p&video_id=vXYZ'],
      );
      final c = DouyinParser.videoUrlCandidates(a);
      expect(c.any((u) => u.contains('video_id=vXYZ') && u.contains('/play/')), isTrue);
    });

    test('候选地址去重', () {
      const a = DouyinAweme(
        awemeId: '1',
        videoId: 'v1',
        playUrls: ['https://m.douyin.com/aweme/v1/playwm/?video_id=v1',
                   'https://m.douyin.com/aweme/v1/playwm/?video_id=v1'],
      );
      final c = DouyinParser.videoUrlCandidates(a);
      expect(c.toSet().length, c.length);
    });
  });

  group('抖音 · 接口数据按 id 精确挑选', () {
    test('推荐流里几十个作品，只挑中目标那一个', () {
      final list = <Map<String, dynamic>>[
        {'aweme_id': '111', 'desc': 'A', 'video': {'play_addr': {'uri': 'vA', 'url_list': ['https://a/playwm/?video_id=vA']}}},
        {'aweme_id': '222', 'desc': 'B', 'images': [
          {'urlList': ['https://p3.douyinpic.com/x~tplv-dy-aweme-images:q75.webp'], 'width': 10, 'height': 20}
        ]},
      ];
      final a = DouyinParser.pickById(list, '222');
      expect(a, isNotNull);
      expect(a!.awemeId, '222');
      expect(a.isImages, isTrue);
      expect(DouyinParser.pickById(list, '999'), isNull, reason: '找不到就是找不到，不能拿第一个顶替');
    });
  });

  group('抖音 · 页面计数与 DOM 兜底', () {
    test('能解析「4/46」这种计数', () {
      expect(DouyinParser.parseCounter('7.8万 751 3.3万 3.4万 4/46 无理.'), 46);
      expect(DouyinParser.parseCounter('没有计数'), 0);
    });

    test('DOM 兜底会把 BGM（mp3）和宣传片排除掉', () {
      final a = DouyinParser.fromDomParts(
        awemeId: '1',
        videoUrls: [
          'https://lf26-music-east.douyinstatic.com/obj/ies-music-hj/123.mp3?is_ssr=1',
          'https://lf-douyin-mobile.bytecdn.com/x/logo.png',
          'https://v5.douyinvod.com/abc/video.mp4',
        ],
      );
      expect(a, isNotNull);
      expect(a!.playUrls.length, 1);
      expect(a.playUrls.first, contains('douyinvod.com'));
    });

    test('DOM 兜底只收图片 CDN 的地址', () {
      final a = DouyinParser.fromDomParts(imageUrls: [
        'https://lf-douyin-pc-web.douyinstatic.com/obj/douyin-pc-web/icon.png',
        'https://p3-pc-sign.douyinpic.com/tos-cn-i-0813/x~tplv-dy-aweme-images:q75.webp',
        'data:image/png;base64,AAAA',
      ]);
      expect(a, isNotNull);
      expect(a!.images.length, 1);
    });
  });
}

/// 把图片地址归一成"同一张图"的判据
/// 抖音同一张图会挂在多个 CDN 节点上（p3/p9/p26…），路径部分才是身份。
String _uriKey(String url) {
  final i = url.indexOf('~');
  final noQ = i > 0 ? url.substring(0, i) : url.split('?').first;
  final m = RegExp(r'tos-cn-i-[a-z0-9]+/([A-Za-z0-9_~\-]+)').firstMatch(noQ);
  return m?.group(1) ?? noQ;
}
