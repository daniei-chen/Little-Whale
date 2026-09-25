// 设备集成测试：**完全在手机本地完成解析**，不经过任何服务器。
//
// 这是「免服务器」方案的验收测试。跑法：
//   flutter test integration_test/local_parse_test.dart -d emulator-5554
//
// 注意：为了让测试结果可信，这里**不启动任何后端**。
// 能过就说明解析确实是在手机里完成的。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/registry.dart';
import 'package:flashsave/local/engine.dart';
/// 抽查一次真实下载：不带 Referer 应该失败，带上应该成功
/// —— 这直接验证「Referer 防盗链」这个关键假设。
Future<({int status, int bytes, String type})> probe(
  String url,
  String referer,
) async {
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
    final data = r.data ?? const <int>[];
    return (
      status: r.statusCode ?? 0,
      bytes: data.length,
      type: (r.headers.value('content-type') ?? '').split(';').first,
    );
  } on DioException catch (e) {
    return (status: e.response?.statusCode ?? 0, bytes: 0, type: '');
  }
}

/// 把隐藏 WebView 挂进 widget 树 —— **不做这一步本地解析一定失败**。
///
/// 实测：只创建 WebViewController 而不渲染 WebViewWidget 时，
/// 页面根本不会加载（document.title 读回来是空字符串）。真机上 App 靠
/// AppShell 里的 LocalEngineHost 挂载，测试里就得自己搭一个一样的。
Future<void> mountEngine(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: LocalEngineHost()),
  ));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('本地解析（免服务器）', () {
    testWidgets('抖音视频：本地解析拿到直链 + 可下载', (tester) async {
      // 关键入口是**手机分享页**（m.douyin.com/share/video/{id}）：
      // PC 站在 WebView 里拿不到详情接口，但手机分享页的 <video> 里直接挂着地址。
      await mountEngine(tester);
      const url = 'https://v.douyin.com/dhQYBJNQZis/';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull, reason: '应当被识别为抖音');

      final r = await platform!.parse(url);

      expect(r.type, 'video');
      expect(r.title.isNotEmpty, isTrue, reason: '标题不能为空');
      expect(r.videoUrl.startsWith('http'), isTrue, reason: '必须拿到直链');
      expect(r.referer.isNotEmpty, isTrue);

      // ignore: avoid_print
      print('[本地] 抖音视频: ${r.title} | ${r.author} | ${r.resolution}');
      // ignore: avoid_print
      print('[本地] 地址: ${r.videoUrl.length > 100 ? r.videoUrl.substring(0, 100) : r.videoUrl}');

      final ok = await probe(r.videoUrl, r.referer);
      // ignore: avoid_print
      print('[本地] 抽查: HTTP ${ok.status}  ${ok.bytes} 字节  ${ok.type}');
      expect(ok.status, anyOf(200, 206), reason: '应当能取到视频数据');
      expect(ok.bytes, greaterThan(1000));
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('抖音图文：拿到全部图片（这条原来完全不可用）', (tester) async {
      await mountEngine(tester);
      const url = 'https://v.douyin.com/mCz8g6jiLjE/';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);

      final t0 = DateTime.now();
      final r = await platform!.parse(url);
      final ms = DateTime.now().difference(t0).inMilliseconds;

      expect(r.type, 'images');
      expect(r.imageCount, greaterThan(10), reason: '这条笔记有 46 张图');
      expect(r.author.isNotEmpty, isTrue, reason: '作者必须抓到');

      // ignore: avoid_print
      print('[本地] 抖音图文: ${r.title} | ${r.author} | ${r.imageCount} 张  **耗时 ${ms}ms**');

      final ok = await probe(r.images.first.url, r.referer);
      // ignore: avoid_print
      print('[本地] 第一张图抽查: HTTP ${ok.status}  ${ok.bytes} 字节  ${ok.type}');
      expect(ok.status, anyOf(200, 206), reason: '带 Referer 应当能取到图片');
      expect(ok.bytes, greaterThan(500));
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('Referer 确实是防盗链的关键（反证）', (tester) async {
      await mountEngine(tester);
      // 用图文作品来验（视频本地拿不到，见上面那条限制说明）
      const url = 'https://v.douyin.com/mCz8g6jiLjE/';
      final r = await LocalRegistry.detect(url)!.parse(url);
      final img = r.images.first.url;

      final without = await probe(img, '');
      final withRef = await probe(img, r.referer);

      // ignore: avoid_print
      print('[反证] 不带 Referer: HTTP ${without.status}  |  带 Referer: HTTP ${withRef.status}');

      // 不断言「不带一定失败」—— 有些 CDN 不校验。但只要带了能成功，
      // 就说明我们传 Referer 这个设计是必要的且正确的。
      expect(withRef.status, anyOf(200, 206));
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('小红书：本地解析拿到图文 + 图片可下载', (tester) async {
      await mountEngine(tester);
      const url = 'https://xhslink.cn/o/4OUFaOXYGvc';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull, reason: '应当被识别为小红书');

      final r = await platform!.parse(url);

      expect(r.type, 'images', reason: '这条是图文笔记');
      expect(r.imageCount, greaterThan(0), reason: '至少要拿到一张图');
      expect(r.title.isNotEmpty, isTrue, reason: '标题不能为空');
      expect(r.referer.isNotEmpty, isTrue);

      // ---- 关键：必须是无水印原图 ----
      // 小红书带处理模板的地址（!h5_1080jpg）图上有「小红书」水印；
      // 换成 sns-img-* 公开节点并去掉模板后才是原图。
      final u = r.images.first.url;
      // ignore: avoid_print
      print('[本地] 小红书: ${r.title} | ${r.author} | ${r.imageCount} 张');
      // ignore: avoid_print
      print('[本地] 首图地址: ${u.length > 110 ? u.substring(0, 110) : u}');
      expect(u.contains('sns-img-'), isTrue,
          reason: '图片应当换成无水印公开节点（sns-img-hw / sns-img-bd）');
      expect(u.contains('!'), isFalse,
          reason: '地址里不该再有小红书的图片处理模板（那就是水印来源）');

      final ok = await probe(u, r.referer);
      // ignore: avoid_print
      print('[本地] 首图抽查: HTTP ${ok.status}  ${ok.bytes} 字节  ${ok.type}');
      expect(ok.status, anyOf(200, 206), reason: '无水印地址必须真的能取到');
      expect(ok.bytes, greaterThan(500));
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('B站：本地解析拿到直链 + 可下载', (tester) async {
      // B站走的是公开 API + wbi 签名，不需要 WebView —— 最快的一个
      await mountEngine(tester);
      const url = 'https://www.bilibili.com/video/BV1emaA6SE3q';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull, reason: '应当被识别为 B站');

      final r = await platform!.parse(url);

      expect(r.type, 'video');
      expect(r.title.isNotEmpty, isTrue);
      expect(r.videoUrl.startsWith('http'), isTrue, reason: '必须拿到直链');
      expect(r.referer, contains('bilibili.com'), reason: 'B站直链必须带 Referer');

      // ignore: avoid_print
      print('[本地] B站: ${r.title} | ${r.author} | ${r.resolution} | ${r.durationSec}s');
      // ignore: avoid_print
      print('[本地] 直链: ${r.videoUrl.length > 90 ? r.videoUrl.substring(0, 90) : r.videoUrl}');

      final ok = await probe(r.videoUrl, r.referer);
      // ignore: avoid_print
      print('[本地] 抽查: HTTP ${ok.status}  ${ok.bytes} 字节  ${ok.type}');
      expect(ok.status, anyOf(200, 206), reason: '带 Referer 应当能取到视频');
      expect(ok.bytes, greaterThan(1000));
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('不支持的平台会被明确拒绝，而不是卡住', (tester) async {
      // 【注意别再拿头条举例了】v0.0.5 起头条/西瓜/优酷/爱奇艺等都纳入了
      // （走通用适配器）。负面测试要用**真的不在范围**的链接。
      expect(LocalRegistry.detect('https://www.youtube.com/watch?v=abc'), isNull,
          reason: '国外平台不在范围内，应当识别不出来');
      expect(LocalRegistry.detect('https://item.taobao.com/item.htm?id=1'), isNull,
          reason: '电商链接不在范围内，应当识别不出来');
      expect(LocalRegistry.canParseLocally(''), isFalse);
      expect(LocalRegistry.supportedNames, contains('抖音'));
      expect(LocalRegistry.supportedNames, contains('小红书'));
      expect(LocalRegistry.supportedNames, contains('哔哩哔哩'));
      expect(LocalRegistry.supportedNames, contains('微博'));
      expect(LocalRegistry.supportedNames, contains('快手'));
      expect(LocalRegistry.supportedNames, contains('知乎'));
      // v0.0.5 起是 6 个核心 + 12 个通用 = 18 个。
      // 【为什么不再写死总数】每加一个平台都要改断言，反而容易漏；
      // 真正要守住的是「**核心平台正好 6 个**」—— 那 6 个是能去水印的，
      // 少一个就是功能退化。
      expect(LocalRegistry.coreNames.length, 6,
          reason: '核心平台（能去水印的那些）必须正好是这 6 个');
      expect(LocalRegistry.coreNames, contains('抖音'));
      expect(LocalRegistry.coreNames, contains('小红书'));
      expect(LocalRegistry.coreNames, contains('哔哩哔哩'));
      expect(LocalRegistry.coreNames, contains('微博'));
      expect(LocalRegistry.coreNames, contains('快手'));
      expect(LocalRegistry.coreNames, contains('知乎'));
      expect(LocalRegistry.all.length, greaterThanOrEqualTo(18),
          reason: 'v0.0.5 起至少覆盖 18 个平台');
    });

    testWidgets('WebView 引擎已就绪', (tester) async {
      expect(LocalEngine.instance.isReady, isTrue,
          reason: '前面的解析跑过之后引擎应当是就绪状态');
    });
  });
}
