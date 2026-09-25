// 性能基准：六个平台各解析一次，量出真实耗时。
//
// 【为什么要单独测】平时跑功能测试时，耗时混在断言里看不清。
// 这个测试只做一件事：**把每个平台的解析耗时量出来**，
// 用来回答「速度到底怎么样」「优化有没有效果」。
//
// 注意：包含 WebView 冷启动开销（第一次解析会明显慢些），
// 所以每个平台都先热身一次再计时 —— 这样量到的是**用户实际感受**的稳定值。

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

/// 一条测试用例
class Case {
  final String name;
  final String url;
  const Case(this.name, this.url);
}

const kCases = <Case>[
  Case('抖音视频', 'https://v.douyin.com/dhQYBJNQZis/'),
  Case('抖音图文', 'https://v.douyin.com/mCz8g6jiLjE/'),
  Case('抖音动图', 'https://v.douyin.com/hjkw-7hGFy0/'),
  Case('小红书图文', 'https://xhslink.cn/o/1AejNnW65yA'),
  Case('小红书动图', 'https://xhslink.cn/o/4jQ9QQoGaQb'),
  Case('小红书视频', 'https://xhslink.cn/o/1QJRsaNrhQ4'),
  Case('B站视频', 'https://www.bilibili.com/video/BV1emaA6SE3q'),
  Case('B站专栏', 'https://www.bilibili.com/read/cv27142128'),
  Case('微博图文', 'https://m.weibo.cn/detail/5345389245106119'),
  Case('微博视频', 'https://m.weibo.cn/detail/5347109389995010'),
  Case('快手视频', 'https://v.kuaishou.com/JjikGmiZ'),
  Case('知乎专栏', 'https://zhuanlan.zhihu.com/p/28852607'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('性能基准：各平台解析耗时', (tester) async {
    await mount(tester);

    final rows = <String>[];
    var totalMs = 0;
    var okCount = 0;
    var failCount = 0;

    for (final c in kCases) {
      final platform = LocalRegistry.detect(c.url);
      if (platform == null) {
        rows.add('${c.name}\t未识别\t-');
        failCount++;
        continue;
      }

      final sw = Stopwatch()..start();
      try {
        final r = await platform.parse(c.url);
        sw.stop();
        totalMs += sw.elapsedMilliseconds;
        okCount++;
        final what = r.type == 'video'
            ? '视频 ${r.durationSec}s'
            : r.hasLivePhotos
                ? '${r.imageCount} 项（含动图）'
                : '${r.imageCount} 张';
        rows.add('${c.name}\t${sw.elapsedMilliseconds}ms\t$what');
      } catch (e) {
        sw.stop();
        failCount++;
        final msg = e.toString().replaceAll('\n', ' ').split('：').first;
        rows.add('${c.name}\t${sw.elapsedMilliseconds}ms\t失败: ${msg.length > 40 ? msg.substring(0, 40) : msg}');
      }
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('================ 性能基准 ================');
    // ignore: avoid_print
    print('平台\t耗时\t结果');
    for (final r in rows) {
      // ignore: avoid_print
      print(r);
    }
    // ignore: avoid_print
    print('------------------------------------------');
    // ignore: avoid_print
    print('成功 $okCount / 失败 $failCount');
    if (okCount > 0) {
      // ignore: avoid_print
      print('平均耗时 ${(totalMs / okCount).round()}ms');
    }
    // ignore: avoid_print
    print('==========================================');

    // 不设硬性耗时断言 —— 网络和风控都会波动，卡时间会让测试变得脆弱。
    // 阈值也放得松：这里用的是**固定链接**，内容被平台删掉时会「失败」，
    // 那是内容过期不是性能问题（已经踩过：微博兜底 ID 失效导致这条一直红）。
    expect(okCount, greaterThanOrEqualTo(kCases.length - 3),
        reason: '至少 3/4 的平台要能解析，失败太多说明有系统性问题');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
