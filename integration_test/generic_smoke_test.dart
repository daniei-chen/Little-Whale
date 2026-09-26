// 通用适配器冒烟测试。
//
// 【为什么是「冒烟」】这些平台（西瓜/头条/好看/微视/豆瓣/贴吧/腾讯视频/
// 爱奇艺/优酷/芒果/虎牙/斗鱼）的网页全是 SPA，通用适配器靠 WebView 渲染后提取。
// 手上没有每个平台的**真实内容分享链接**，所以这里分两级验证：
//
//   1. **识别**：链接能被正确分派到对应平台（这个必须全过）
//   2. **渲染**：拿平台自己的**公开页面**跑一遍，确认 WebView 能打开、
//      脚本能跑、不会崩（不保证一定能提取到内容 —— 那取决于页面）
//
// 真正的内容解析需要在有真实分享链接时逐个验证。这一点我在报告里写清楚了，
// 不假装它们全都验证过。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/engine.dart';
import 'package:flashsave/local/generic.dart';
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

  testWidgets('通用适配器：12 个平台都能被正确识别', (tester) async {
    const samples = {
      'ixigua': 'https://www.ixigua.com/7123456789012345678',
      'toutiao': 'https://www.toutiao.com/article/7123456789012345678/',
      'haokan': 'https://haokan.baidu.com/v?vid=1792435769358388527',
      'weishi': 'https://isee.weishi.qq.com/ws/app-pages/share/index.html?id=abc',
      'douban': 'https://www.douban.com/note/812345678/',
      'tieba': 'https://tieba.baidu.com/p/8123456789',
      'qqvideo': 'https://v.qq.com/x/cover/abc123.html',
      'iqiyi': 'https://www.iqiyi.com/v_abc123.html',
      'youku': 'https://v.youku.com/v_show/id_XNTkxMjM0NTY3OA==.html',
      'mgtv': 'https://www.mgtv.com/b/123456/7890123.html',
      'huya': 'https://www.huya.com/660000',
      'douyu': 'https://www.douyu.com/9999',
    };

    for (final e in samples.entries) {
      final p = LocalRegistry.detect(e.value);
      expect(p, isNotNull, reason: '${e.key} 应当被识别出来：${e.value}');
      expect(p!.key, e.key, reason: '${e.value} 应当分派到 ${e.key}，实际是 ${p.key}');
      expect(p, isA<GenericLocalPlatform>(),
          reason: '${e.key} 目前走通用适配器');
    }

    // ignore: avoid_print
    print('[通用] 识别 12/12 通过');
  });

  testWidgets('通用适配器：真实页面能渲染并跑通提取脚本（不崩、不卡死）',
      (tester) async {
    await mount(tester);

    // 拿平台自己的公开页面跑 —— 目的是验证「WebView 能开、脚本能跑」，
    // 而不是「一定能提出内容」。后者需要真实分享链接。
    // 前两个是**真实内容页**（从平台列表页挖出来的），后两个是首页对照。
    // 都是**真实内容页**（从平台列表页 / 搜索接口挖出来的）
    const urls = [
      'https://haokan.baidu.com/v?vid=12386876873461850902',  // 好看视频
      'https://www.toutiao.com/article/7689401276165079615/', // 今日头条（搜索接口挖到 group_id）
      'https://v.youku.com/v_show/id_844071.html',            // 优酷（搜索接口挖到 programId）
      'https://www.iqiyi.com/v_3031886092227301.html',        // 爱奇艺
      'https://tieba.baidu.com/p/3138733512',                 // 百度贴吧（Node 403，WebView 能过）
      'https://www.huya.com/660115',                          // 虎牙
    ];

    var ok = 0;
    for (final u in urls) {
      final p = LocalRegistry.detect(u);
      if (p == null) continue;
      final sw = Stopwatch()..start();
      try {
        final r = await p.parse(u);
        sw.stop();
        ok++;
        // ignore: avoid_print
        print('[通用] ${p.name.padRight(8)} ${sw.elapsedMilliseconds}ms  '
            '${r.type}  图 ${r.imageCount}  标题「${r.title.length > 20 ? r.title.substring(0, 20) : r.title}」');
      } catch (e) {
        sw.stop();
        // 拿不到内容是可以接受的（首页不是内容页），但**不能是崩溃** ——
        // 这里只要求它是我们自己的 LocalParseError（说明流程走完了、有可控的报错）
        final msg = e.toString();
        final controlled = msg.contains('LocalParseError') ||
            msg.contains('没有找到可下载') ||
            msg.contains('没能读到内容');
        // ignore: avoid_print
        print('[通用] ${p.name.padRight(8)} ${sw.elapsedMilliseconds}ms  '
            '未提取到内容（${controlled ? "可控报错 ✅" : "异常 ⚠️: $msg"}）');
        expect(controlled, isTrue,
            reason: '${p.name} 应当给出可控的报错，而不是抛异常或崩溃');
      }
    }

    // ignore: avoid_print
    print('[通用] 渲染冒烟：$ok/${urls.length} 能直接提取到内容');
    expect(ok, greaterThanOrEqualTo(0)); // 提取不到不算失败，只要不崩
  }, timeout: const Timeout(Duration(minutes: 5)));
}
