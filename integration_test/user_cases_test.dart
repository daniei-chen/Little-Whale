// 用户实际反馈的问题回归测试。
//
// 这些链接是用户真实报障时给的，必须一直能过 —— 它们覆盖了
// 「无水印地址没有扩展名 → 被存成 .mp4 → 相册不显示」这个坑。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/data/platforms.dart';
import 'package:flashsave/local/engine.dart';
import 'package:flashsave/local/registry.dart';
import 'package:flashsave/services/download_service.dart';

Future<void> mount(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalEngineHost())));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('用户报障回归', () {
    testWidgets('小红书A：4 张图，解析 + 真的能保存进相册', (tester) async {
      await mountEngineFor(tester);
      const url = 'https://xhslink.cn/o/1AejNnW65yA';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);

      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[回归A] ${r.title} | ${r.imageCount} 张');
      expect(r.imageCount, greaterThan(0));

      // 关键：无水印地址没有扩展名，以前会被存成 .mp4 导致相册不认
      final u = r.images.first.url;
      // ignore: avoid_print
      print('[回归A] 首图: $u');
      expect(u.contains('sns-img-'), isTrue, reason: '应当是无水印节点');

      final outcome = await DownloadService.instance.fetchAndSave(
        proxyUrl: u,
        isVideo: false,
        referer: r.referer,
        fileHint: 'regression_a',
      );
      // ignore: avoid_print
      print('[回归A] 保存结果: saved=${outcome.saved}  msg=${outcome.message}');
      expect(outcome.saved, isTrue, reason: '必须真的存进相册');
    }, timeout: const Timeout(Duration(minutes: 4)));

    testWidgets('小红书B：视频笔记，解析出无水印原始视频', (tester) async {
      await mountEngineFor(tester);
      const url = 'https://xhslink.cn/o/1QJRsaNrhQ4';

      final platform = LocalRegistry.detect(url);
      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[回归B] ${r.title} | type=${r.type} | 视频=${r.videoUrl.isNotEmpty}');
      // ignore: avoid_print
      print('[回归B] 视频地址: ${r.videoUrl}');

      // 无水印视频走公开节点（原始上传对象），不是带水印的成品流
      expect(r.videoUrl, contains('sns-video'), reason: '应当是原始对象、无水印');
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('小红书视频：真的存进相册（扩展名按真实容器判定）', (tester) async {
      // 用户报障：文件管理里能看到，相册不显示。
      // 根因是小坏书把 QuickTime(ftyp qt) 文件报成 video/mp4，
      // 存成 .mp4 后媒体库解不出元数据就不入库。
      await mountEngineFor(tester);
      const url = 'https://xhslink.cn/o/1QJRsaNrhQ4';

      final r = await LocalRegistry.detect(url)!.parse(url);
      expect(r.type, 'video');
      // ignore: avoid_print
      print('[回归D] 视频地址: ${r.videoUrl}');

      final sw = Stopwatch()..start();
      final outcome = await DownloadService.instance.fetchAndSave(
        proxyUrl: r.videoUrl,
        isVideo: true,
        referer: r.referer,
        fileHint: 'regression_d',
      );
      sw.stop();
      // ignore: avoid_print
      print('[回归D] 保存: saved=${outcome.saved}  msg=${outcome.message}  '
          '耗时=${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
      expect(outcome.saved, isTrue, reason: '必须真的存进相册');
    }, timeout: const Timeout(Duration(minutes: 8)));

    testWidgets('小红书动图：解析出封面 + 带音轨的动图视频', (tester) async {
      await mountEngineFor(tester);
      const url = 'https://xhslink.cn/o/4jQ9QQoGaQb';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull, reason: '应当被识别为小红书');

      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[回归F] ${r.type} | ${r.title} | ${r.author} | ${r.imageCount} 项');
      expect(r.imageCount, greaterThan(0));

      final live = r.images.where((e) => e.isLive).toList();
      // ignore: avoid_print
      print('[回归F] 其中动图 ${live.length} 项（共 ${r.imageCount}）');
      expect(live.isNotEmpty, isTrue,
          reason: '这条是 18 张动图的作品，必须能识别出动图');

      final first = live.first;
      // ignore: avoid_print
      print('[回归F] 封面: ${first.url.length > 80 ? first.url.substring(0, 80) : first.url}');
      // ignore: avoid_print
      print('[回归F] 动图视频: ${first.videoUrl.length > 90 ? first.videoUrl.substring(0, 90) : first.videoUrl}');
      // ignore: avoid_print
      print('[回归F] 时长 ${first.durationSec}s');

      expect(first.videoUrl, contains('xhscdn'), reason: '动图视频应当来自小红书 CDN');
      expect(first.durationSec, greaterThan(0), reason: '应当拿到时长');

      // 两个都要能下
      final img = await probe(first.url, r.referer);
      // ignore: avoid_print
      print('[回归F] 封面抽查: HTTP ${img.status}  ${img.bytes} 字节  ${img.type}');
      expect(img.status, anyOf(200, 206));

      final vid = await probe(first.videoUrl, r.referer);
      // ignore: avoid_print
      print('[回归F] 动图视频抽查: HTTP ${vid.status}  ${vid.bytes} 字节  ${vid.type}');
      expect(vid.status, anyOf(200, 206));
      expect(vid.type, contains('video'), reason: '动图地址必须是视频');
    }, timeout: const Timeout(Duration(minutes: 3)));
    testWidgets('抖音动图：解析出图片 + 动图视频（带音轨）', (tester) async {
      await mountEngineFor(tester);
      const url = 'https://v.douyin.com/hjkw-7hGFy0/';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);

      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[回归E] ${r.type} | ${r.title} | ${r.author} | ${r.imageCount} 项');

      expect(r.imageCount, greaterThan(0));

      // 动图作品：至少有一项带 videoUrl（带音轨的短视频）
      final live = r.images.where((e) => e.isLive).toList();
      // ignore: avoid_print
      print('[回归E] 其中动图 ${live.length} 项');
      for (final it in live.take(2)) {
        // ignore: avoid_print
        print('[回归E]   图: ${it.url.length > 70 ? it.url.substring(0, 70) : it.url}');
        // ignore: avoid_print
        print('[回归E]   动图视频: ${it.videoUrl.length > 90 ? it.videoUrl.substring(0, 90) : it.videoUrl}');
        // ignore: avoid_print
        print('[回归E]   时长 ${it.durationSec}s');
      }

      expect(live.isNotEmpty, isTrue, reason: '这条是动图作品，应当解析出视频地址');
      expect(live.first.videoUrl, contains('douyinvod'),
          reason: '动图视频应当来自抖音 CDN');

      // 静态图也要能下
      final ok = await probe(r.images.first.url, r.referer);
      // ignore: avoid_print
      print('[回归E] 静态图抽查: HTTP ${ok.status}  ${ok.bytes} 字节  ${ok.type}');
      expect(ok.status, anyOf(200, 206));

      // 动图视频也要能下
      final v = await probe(live.first.videoUrl, r.referer);
      // ignore: avoid_print
      print('[回归E] 动图视频抽查: HTTP ${v.status}  ${v.bytes} 字节  ${v.type}');
      expect(v.status, anyOf(200, 206));
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('抖音：图文分享文案里带干扰字符也能解析', (tester) async {
      await mountEngineFor(tester);
      // 用户给的完整分享文案（前后带表情和时间戳等干扰）
      const text = '4.17 复制打开抖音，看看【无理.的图文作品】壁纸分享（1）# 高质量壁纸 # 我的壁纸  '
          'https://v.douyin.com/ASPqqIDj8ew/ :5pm w@S.LW DhO:/ 11/01';

      // App 真实入口是先提取链接再解析，这里保持一致
      final url = extractUrl(text);
      // ignore: avoid_print
      print('[回归C] 从文案里提取到: $url');
      expect(url, isNotNull, reason: '要能从一堆干扰字符里认出链接');

      final platform = LocalRegistry.detect(url!);
      expect(platform, isNotNull);

      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[回归C] ${r.type} | ${r.title} | ${r.imageCount} 张');
      expect(r.title.isNotEmpty, isTrue);
      expect(r.type, 'images', reason: '这条是图文作品');
      expect(r.imageCount, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// 与 App 里同名的辅助（mountEngine 在另一个测试文件里，这里独立一份）
Future<void> mountEngineFor(WidgetTester tester) => mount(tester);

/// 抽查一个地址是否能取到数据（只取前 8KB）
Future<({int status, int bytes, String type})> probe(String url, String referer) async {
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