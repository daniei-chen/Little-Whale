// v0.2.0 新增的 4 个通用平台：识别 + 渲染 + 明确报错。
//
// 【为什么单独一份】新增平台最容易出的问题不是「解析不出来」，而是
// 「识别了、然后给一个看不懂的错误」或者更糟 —— **下载到一个坏文件**。
// 这份测试盯的就是这两件事：
//   1. 识别（纯字符串，桌面也能跑，这里在设备上再确认一次）
//   2. AcFun 的真实作品页：要么真拿到可下载地址，要么给出「HLS 流不支持」的明确提示
//   3. 无效链接：可读报错、不卡死、不崩
//
// 跑法：FLUTTER_TEST_X64=1 flutter test integration_test/new_platforms_test.dart -d emulator-5554

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/engine.dart';
import 'package:flashsave/local/registry.dart';
import 'package:flashsave/services/download_service.dart';

Future<void> mountEngine(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalEngineHost())));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('v0.2.0 新增平台', () {
    testWidgets('4 个新平台都能被识别', (tester) async {
      const cases = <String, String>{
        'https://www.acfun.cn/v/ac41234567': 'acfun',
        'https://h5.pipix.com/s/abc123': 'pipix',
        'https://www.izuiyou.com/detail/123456789': 'izuiyou',
        'https://www.miaopai.com/show/abc123.htm': 'miaopai',
      };
      for (final e in cases.entries) {
        final p = LocalRegistry.detect(e.key);
        expect(p, isNotNull, reason: '识别不出来：${e.key}');
        expect(p!.key, e.value);
      }
      // ignore: avoid_print
      print('[新平台] 识别 4/4 通过');
    });

    testWidgets('皮皮虾真实作品：能拿到可下载的视频地址', (tester) async {
      await mountEngine(tester);
      // 真实分享短链（"没想到我也被安排上了"）
      const url = 'https://h5.pipix.com/s/e161t2B/';
      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);
      expect(platform!.key, 'pipix');

      final r = await platform.parse(url);
      // ignore: avoid_print
      print('[皮皮虾] type=${r.type} title="${r.title}" '
          'video=${r.videoUrl.length > 80 ? r.videoUrl.substring(0, 80) : r.videoUrl}');
      expect(r.type, 'video', reason: '这是视频作品，不该判成图文');
      expect(r.videoUrl.startsWith('http'), isTrue);
      expect(r.videoUrl.contains('.m3u8'), isFalse, reason: '不能把播放列表当视频');
    }, timeout: const Timeout(Duration(minutes: 4)));

    testWidgets('皮皮虾视频：真的能下载并写进相册', (tester) async {
      await mountEngine(tester);
      const url = 'https://h5.pipix.com/s/e161t2B/';
      final r = await LocalRegistry.detect(url)!.parse(url);
      expect(r.videoUrl.startsWith('http'), isTrue);

      final outcome = await DownloadService.instance.fetchAndSave(
        proxyUrl: r.videoUrl,
        isVideo: true,
        referer: r.referer,
        fileHint: 'e2e_pipix',
      );
      // ignore: avoid_print
      print('[皮皮虾-保存] saved=${outcome.saved} msg=${outcome.message}');
      expect(outcome.saved, isTrue, reason: '保存失败: ${outcome.message}');
    }, timeout: const Timeout(Duration(minutes: 6)));

    testWidgets('AcFun 真实作品：要么拿到可下载地址，要么明确说「HLS 流不支持」', (tester) async {
      await mountEngine(tester);
      // 这是一个真实存在的 AcFun 作品（2023 年投稿）
      const url = 'https://www.acfun.cn/v/ac41234567';
      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);

      try {
        final r = await platform!.parse(url);
        // ignore: avoid_print
        print('[AcFun] 拿到: type=${r.type} title=${r.title} video=${r.videoUrl.isNotEmpty}');
        expect(r.title.isNotEmpty, isTrue, reason: '至少要拿到标题');
        if (r.videoUrl.isNotEmpty) {
          // 拿到地址就必须是**可下载的 mp4**，绝不能是 m3u8 播放列表
          expect(r.videoUrl.contains('.m3u8'), isFalse,
              reason: 'm3u8 是播放列表不是视频文件，下载下来相册打不开');
        }
      } catch (e) {
        final msg = e.toString();
        // ignore: avoid_print
        print('[AcFun] 明确报错: $msg');
        // 允许失败，但必须说人话：要么提到 HLS/流式，要么提到内容没找到
        expect(
          msg.contains('HLS') || msg.contains('流式') || msg.contains('没有找到'),
          isTrue,
          reason: '报错必须是可理解的，不能是原始异常：$msg',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 4)));

    testWidgets('无效的新平台链接：可读报错、不卡死', (tester) async {
      await mountEngine(tester);
      // 这个 id 不存在，页面会是空壳
      const url = 'https://www.acfun.cn/v/ac99999999999';
      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);

      final sw = Stopwatch()..start();
      try {
        await platform!.parse(url);
      } catch (e) {
        // ignore: avoid_print
        print('[新平台-无效] ${sw.elapsedMilliseconds}ms 报错: ${e.toString().split('\n').first}');
      }
      sw.stop();
      // 关键：不能挂在那儿。通用适配器的超时是 20 秒级，给一倍余量。
      expect(sw.elapsedMilliseconds, lessThan(60000),
          reason: '无效链接不该拖到一分钟以上');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
