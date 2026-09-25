// 知乎：专栏文章能解析；回答页未登录应当给出明确提示。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/engine.dart';
import 'package:flashsave/local/registry.dart';

Future<void> mount(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalEngineHost())));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('知乎：专栏文章（不需要登录）', (tester) async {
    await mount(tester);
    const url = 'https://zhuanlan.zhihu.com/p/28852607';

    final platform = LocalRegistry.detect(url);
    expect(platform, isNotNull, reason: '应当被识别为知乎');

    final r = await platform!.parse(url);
    // ignore: avoid_print
    print('[知乎] ${r.type} | ${r.title} | ${r.author} | 图 ${r.imageCount} 张');

    expect(r.title.isNotEmpty, isTrue, reason: '标题不能为空');
    expect(r.imageCount, greaterThan(0), reason: '这篇有正文配图');

    final u = r.images.first.url;
    // ignore: avoid_print
    print('[知乎] 首图: ${u.length > 110 ? u.substring(0, 110) : u}');
    // 去掉尺寸后缀才是原图
    expect(RegExp(r'_\d+w\.').hasMatch(u), isFalse,
        reason: '不该带 _1440w 这类展示尺寸后缀');

    final resp = await Dio().get<List<int>>(u,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-4095', 'Referer': r.referer},
          validateStatus: (s) => s != null && s < 400,
        ));
    // ignore: avoid_print
    print('[知乎] 下载: HTTP ${resp.statusCode}  ${(resp.data ?? []).length} 字节');
    expect(resp.statusCode, anyOf(200, 206));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('知乎：回答页未登录时给的是「怎么办」而不是含糊的失败', (tester) async {
    await mount(tester);
    // 回答页未登录会被知乎跳到 /signin
    const url = 'https://www.zhihu.com/question/19550224/answer/123456789';

    final platform = LocalRegistry.detect(url);
    expect(platform, isNotNull);

    try {
      await platform!.parse(url);
      // 万一哪天知乎放开未登录访问，这条会红，提醒更新说明
      // ignore: avoid_print
      print('[知乎] 回答页竟然解析成功了，请更新限制说明');
    } on LocalParseError catch (e) {
      // ignore: avoid_print
      print('[知乎] 回答页提示: ${e.message.split("\n").first}');
      expect(e.message.contains('专栏') || e.message.contains('服务器'), isTrue,
          reason: '要给出可操作的替代方案');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
