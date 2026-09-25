// B站图文：专栏（cv）+ 图文动态（opus）。

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

Future<({int status, int bytes, String type})> probe(
    String url, String referer) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (s) => s != null && s < 500,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      if (referer.isNotEmpty) 'Referer': referer,
      'Range': 'bytes=0-8191',
    },
  ));
  try {
    final r = await dio.get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes));
    final d = r.data ?? const <int>[];
    return (
      status: r.statusCode ?? 0,
      bytes: d.length,
      type: (r.headers.value('content-type') ?? '').split(';').first,
    );
  } on DioException catch (e) {
    return (status: e.response?.statusCode ?? 0, bytes: 0, type: '');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('B站专栏：解析出正文原图', (tester) async {
    await mount(tester);
    const url = 'https://www.bilibili.com/read/cv27142128';

    final p = LocalRegistry.detect(url);
    expect(p, isNotNull, reason: '专栏链接应当被识别为 B站');

    final r = await p!.parse(url);
    // ignore: avoid_print
    print('[B站专栏] ${r.type} | ${r.title} | ${r.author} | 图 ${r.imageCount} 张');
    expect(r.type, 'images');
    expect(r.imageCount, greaterThan(0), reason: '专栏正文里有图');
    expect(r.title.isNotEmpty, isTrue);

    // 地址必须是原图（不能带 @ 处理后缀）
    for (final img in r.images.take(3)) {
      // ignore: avoid_print
      print('[B站专栏] ${img.url.length > 90 ? img.url.substring(0, 90) : img.url}');
      expect(img.url.contains('@'), isFalse,
          reason: '带 @ 的是处理过的展示版，不是原图');
      expect(img.url, startsWith('https://'));
    }

    final ok = await probe(r.images.first.url, r.referer);
    // ignore: avoid_print
    print('[B站专栏] 抽查: HTTP ${ok.status}  ${ok.bytes} 字节  ${ok.type}');
    expect(ok.status, anyOf(200, 206));
    expect(ok.type, contains('image'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('B站图文动态（opus）：解析出动态里的图', (tester) async {
    await mount(tester);
    const url = 'https://www.bilibili.com/opus/1219805570066808839';

    final p = LocalRegistry.detect(url);
    expect(p, isNotNull, reason: 'opus 链接应当被识别为 B站');

    final r = await p!.parse(url);
    // ignore: avoid_print
    print('[B站动态] ${r.type} | ${r.title} | ${r.author} | 图 ${r.imageCount} 张');
    expect(r.type, 'images');
    expect(r.imageCount, greaterThan(0), reason: '这条动态里有图');

    for (final img in r.images.take(2)) {
      // ignore: avoid_print
      print('[B站动态] ${img.url.length > 95 ? img.url.substring(0, 95) : img.url}');
      expect(img.url.contains('@'), isFalse, reason: '必须是原图');
    }

    final ok = await probe(r.images.first.url, r.referer);
    // ignore: avoid_print
    print('[B站动态] 抽查: HTTP ${ok.status}  ${ok.bytes} 字节  ${ok.type}');
    expect(ok.status, anyOf(200, 206));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('B站：视频链接仍然走视频分支（没有被图文逻辑抢走）',
      (tester) async {
    await mount(tester);
    const url = 'https://www.bilibili.com/video/BV1emaA6SE3q';

    final p = LocalRegistry.detect(url);
    expect(p, isNotNull);

    final r = await p!.parse(url);
    // ignore: avoid_print
    print('[B站视频] ${r.type} | ${r.title} | ${r.resolution} | ${r.durationSec}s');
    expect(r.type, 'video', reason: '视频链接必须还是解析成视频');
    expect(r.videoUrl, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
