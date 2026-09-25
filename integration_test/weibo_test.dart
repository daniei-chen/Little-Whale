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

    // 【为什么要兜底 ID】热榜里大多是纯文字微博，「翻一条带图的」经常翻不到 ——
    // 原来那样写，翻不到就 if 跳过，测试照样绿。**等于图文路径根本没被测**。
    // 实测就撞到过：三次运行里有两次 (没找到)，却都是 All tests passed。
    // 所以这里给一条固定的带图微博做兜底，并且最后断言「两条路径都必须真的跑到」。
    // 【这个 ID 会过期】微博内容会被删除，硬编码的兜底 ID 迟早失效 ——
    // 实测就撞到过：原来填的 5339732289520397 后来返回「没返回这条内容」，
    // 于是性能基准里微博一直失败。
    // 正常路径是**从热榜翻一条当时的带图微博**（下面那段），
    // 这个常量只在热榜恰好没有图时兜底；失效了就换一个（随便找条带图的微博）。
    const fallbackPicId = '5345389245106119';

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
    final fromFeed = picId.isNotEmpty;
    if (!fromFeed) picId = fallbackPicId;

    // ignore: avoid_print
    print('[微博] 带图 id=$picId（${fromFeed ? "热榜翻到的" : "用兜底 ID"}）  视频 id=${videoId.isEmpty ? "(没找到)" : videoId}');

    final platform = LocalRegistry.detect('https://m.weibo.cn/detail/$picId');
    expect(platform, isNotNull, reason: '应当被识别为微博');

    // 图文路径 —— 必须真的跑到，不允许静默跳过
    final r = await platform!.parse('https://m.weibo.cn/detail/$picId');
    // ignore: avoid_print
    print('[微博·图] ${r.type} | ${_cut(r.title, 30)} | ${r.author} | ${r.imageCount} 张');
    expect(r.type, 'images',
        reason: '这条微博是带图的，必须解析成图文（id=$picId）');
    expect(r.imageCount, greaterThan(0), reason: '至少要有一张图');

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

    // 视频路径 —— 热榜偶尔没有视频微博，那就用固定 ID 兜底，同样不允许跳过。
    // 这个 ID 也会过期（微博内容会被删），失效了就换一条。
    const fallbackVideoId = '5347109389995010';
    if (videoId.isEmpty) videoId = fallbackVideoId;

    final vr = await platform.parse('https://m.weibo.cn/detail/$videoId');
    // ignore: avoid_print
    print('[微博·视频] ${vr.type} | ${_cut(vr.title, 30)} | ${vr.author}');
    // ignore: avoid_print
    print('[微博·视频] 地址: ${_cut(vr.videoUrl, 110)}');
    expect(vr.type, 'video', reason: '这条是视频微博（id=$videoId）');
    expect(vr.videoUrl.startsWith('http'), isTrue);
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('微博：weibo.com 的 base62 短 ID 也能识别', (tester) async {
    expect(LocalRegistry.detect('https://weibo.com/1234567890/Pabc123XYZ'),
        isNotNull);
  });
}
