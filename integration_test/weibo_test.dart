// 微博：图文 + 视频两种形态都要覆盖。
//
// 视频路径上轮已经验证；这轮补上图文路径 —— 从热榜里翻一条**带图**的微博，
// 顺便确认图片地址是原图（large）而不是缩略图。

import 'dart:convert';

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

String _syncGet(String url) => '''
(function () {
  try {
    var x = new XMLHttpRequest();
    x.open('GET', ${jsonEncode(url)}, false);
    x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    x.setRequestHeader('Accept', 'application/json, text/plain, */*');
    x.send();
    return x.responseText || '';
  } catch (e) { return '{}'; }
})()
''';

String _cut(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('微博：图文路径 + 视频路径都要通', (tester) async {
    await mount(tester);
    final e = LocalEngine.instance;

    await e.setUserAgent(LocalEngine.mobileUa);
    await e.evaluate('https://m.weibo.cn/', 'String(document.title)',
        settle: const Duration(seconds: 4));

    final hot = await e.evalCurrent(_syncGet(
        'https://m.weibo.cn/api/container/getIndex?containerid=102803&page_type=03'));
    final j = (hot is Map) ? hot : jsonDecode(hot.toString()) as Map;
    final cards = (j['data']?['cards'] as List?) ?? [];

    // 翻出**带图**和**带视频**的两条（热榜里大多是纯文字）
    var picId = '';
    var videoId = '';
    for (final c in cards) {
      final m = (c as Map)['mblog'];
      if (m is! Map) continue;
      final pics = m['pics'];
      if (pics is List && pics.isNotEmpty && picId.isEmpty) {
        picId = '${m['id']}';
      }
      final pi = m['page_info'];
      if (pi is Map && pi['type'] == 'video' && videoId.isEmpty) {
        videoId = '${m['id']}';
      }
      if (picId.isNotEmpty && videoId.isNotEmpty) break;
    }
    // ignore: avoid_print
    print('[微博] 带图 id=${picId.isEmpty ? "(没找到)" : picId}  视频 id=${videoId.isEmpty ? "(没找到)" : videoId}');

    final platform = LocalRegistry.detect('https://m.weibo.cn/detail/$picId');
    expect(platform, isNotNull, reason: '应当被识别为微博');

    if (picId.isNotEmpty) {
      final r = await platform!.parse('https://m.weibo.cn/detail/$picId');
      // ignore: avoid_print
      print('[微博·图] ${r.type} | ${_cut(r.title, 30)} | ${r.author} | ${r.imageCount} 张');
      expect(r.type, 'images');
      expect(r.imageCount, greaterThan(0));

      final u = r.images.first.url;
      // ignore: avoid_print
      print('[微博·图] 首图: ${_cut(u, 110)}');
      // 原图应当是 /large/，不能是 /thumbnail/ 或 /bmiddle/
      expect(u.contains('/large/') || u.contains('/orj'), isTrue,
          reason: '要原图，不能是缩略图');

      final resp = await Dio().get<List<int>>(u,
          options: Options(
            responseType: ResponseType.bytes,
            headers: const {
              'Range': 'bytes=0-4095',
              'Referer': 'https://m.weibo.cn/',
            },
            validateStatus: (s) => s != null && s < 400,
          ));
      // ignore: avoid_print
      print('[微博·图] 下载: HTTP ${resp.statusCode}  ${(resp.data ?? []).length} 字节');
      expect(resp.statusCode, anyOf(200, 206));
    }

    if (videoId.isNotEmpty) {
      final r = await platform!.parse('https://m.weibo.cn/detail/$videoId');
      // ignore: avoid_print
      print('[微博·视频] ${r.type} | ${_cut(r.title, 30)} | ${r.author}');
      // ignore: avoid_print
      print('[微博·视频] 地址: ${_cut(r.videoUrl, 110)}');
      expect(r.type, 'video');
      expect(r.videoUrl.startsWith('http'), isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('微博：weibo.com 的 base62 短 ID 也能识别', (tester) async {
    expect(LocalRegistry.detect('https://weibo.com/1234567890/Pabc123XYZ'),
        isNotNull);
  });
}
