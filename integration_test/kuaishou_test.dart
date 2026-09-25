// 快手：本地解析验证。

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

  testWidgets('快手：短链 → 手机分享页 → 视频直链', (tester) async {
    await mount(tester);
    const url = 'https://v.kuaishou.com/JjikGmiZ';

    final platform = LocalRegistry.detect(url);
    expect(platform, isNotNull, reason: '应当被识别为快手');

    final r = await platform!.parse(url);
    // ignore: avoid_print
    print('[快手] ${r.type} | ${r.title} | ${r.author} | 图 ${r.imageCount} 张');
    // ignore: avoid_print
    print('[快手] 地址: ${r.videoUrl.length > 120 ? r.videoUrl.substring(0, 120) : r.videoUrl}');

    // 【断言要严】原来写的是「视频非空 **或** 图 > 0」，太松 ——
    // 快手视频一度退化成「图集 1 张」，测试照样绿，回归被放过去了。
    // 这条链接是**视频**作品，就必须解析成视频。
    expect(r.type, 'video', reason: '这条链接是视频作品，不该退化成图集');
    expect(r.videoUrl, isNotEmpty, reason: '必须拿到视频直链');
    expect(r.videoUrl, contains('http'));

    final resp = await Dio().get<List<int>>(r.videoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-2047', 'Referer': r.referer},
          validateStatus: (s) => s != null && s < 400,
        ));
    // ignore: avoid_print
    print('[快手] 抽查: HTTP ${resp.statusCode}  ${(resp.data ?? []).length} 字节');
    expect(resp.statusCode, anyOf(200, 206));
    expect((resp.data ?? []).length, greaterThan(500));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
