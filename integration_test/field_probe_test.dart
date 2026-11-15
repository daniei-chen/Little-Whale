// 解析结果字段完整性探测：把每个平台真实解析出来的**所有字段**打出来，
// 看哪些是空的。
//
// 【为什么要做这个】「能解析」只是下限。历史记录卡片、分享文案、保存后的文件名
// 都要用这些字段 —— 空着不影响下载，但会让界面显得残缺（比如时长显示 --:--、
// 作者显示「未知」）。这类问题单看功能测试是发现不了的。
//
// 这份测试**只打印、不硬断言**：平台不给的字段（比如微博不给时长）补不出来，
// 断言它非空只会让测试变脆。真正要看的是「哪些字段本该有却没有」。
//
// 跑法：FLUTTER_TEST_X64=1 flutter test integration_test/field_probe_test.dart -d emulator-5554

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/engine.dart';
import 'package:flashsave/local/registry.dart';

Future<void> mountEngine(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalEngineHost())));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

const _cases = <String, String>{
  '抖音视频': 'https://v.douyin.com/dhQYBJNQZis/',
  '抖音图文': 'https://v.douyin.com/mCz8g6jiLjE/',
  '小红书': 'https://xhslink.cn/o/1AejNnW65yA',
  'B站视频': 'https://www.bilibili.com/video/BV1emaA6SE3q',
  'B站专栏': 'https://www.bilibili.com/read/cv27142128',
  '微博': 'https://m.weibo.cn/detail/5345389245106119',
  '知乎专栏': 'https://zhuanlan.zhihu.com/p/28852607',
  '快手': 'https://v.kuaishou.com/JjikGmiZ',
  '皮皮虾': 'https://h5.pipix.com/s/e161t2B/',
};

void _report(String name, LocalResult r) {
  final fields = <String, String>{
    'platform': r.platform,
    'type': r.type,
    'title': r.title,
    'author': r.author,
    'cover': r.cover,
    'durationSec': r.durationSec.toString(),
    'resolution': r.resolution,
    'size': r.size,
    'publishTime': r.publishTime,
    'music': r.music,
    'videoUrl': r.videoUrl.isEmpty ? '' : '✓',
    'referer': r.referer.isEmpty ? '' : r.referer,
    'images': r.images.length.toString(),
  };
  final missing = fields.entries
      .where((e) => e.value.isEmpty || e.value == '0')
      .map((e) => e.key)
      .toList();
  // ignore: avoid_print
  print('[字段] $name → ${fields.entries.map((e) => '${e.key}=${e.value}').join(' | ')}');
  // ignore: avoid_print
  print('[字段] $name 缺失：${missing.isEmpty ? '(无)' : missing.join(', ')}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('各平台解析字段完整性（只打印）', (tester) async {
    await mountEngine(tester);
    for (final e in _cases.entries) {
      final platform = LocalRegistry.detect(e.value);
      if (platform == null) {
        // ignore: avoid_print
        print('[字段] ${e.key} → 未识别');
        continue;
      }
      try {
        final r = await platform.parse(e.value);
        _report(e.key, r);
      } catch (err) {
        // ignore: avoid_print
        print('[字段] ${e.key} → 解析失败：${err.toString().split('\n').first}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
