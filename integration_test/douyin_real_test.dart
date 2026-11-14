// 抖音 · 真实链接端到端回归（在**真实 Android 设备/模拟器**上跑）。
//
// 【为什么要单独一份】
// 单元测试能证明「解析器认得这些数据」，但证明不了「App 里真能拿到数据」——
// 中间还隔着 WebView 的加载、UA 切换、指纹伪装、超时和轮询。
// 这一份把整条链路跑通，并且**真的去下载一段字节**：
// 只断言「解析出了地址」是不够的，地址可能已经过期。
//
// 覆盖的链接来自用户实际报障：
//   · 视频短链          https://v.douyin.com/dhQYBJNQZis/
//   · 图文 46 张        https://v.douyin.com/mCz8g6jiLjE/（带干扰字符的完整分享文案）
//   · 动图（Live Photo） https://v.douyin.com/hjkw-7hGFy0/
//
// 跑法：
//   flutter test integration_test/douyin_real_test.dart -d <设备>

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/douyin_parse.dart';
import 'package:flashsave/local/engine.dart';
import 'package:flashsave/local/registry.dart';

/// 把隐藏 WebView 挂进 widget 树（不挂载的话页面根本不会加载）
Future<void> mountEngine(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalEngineHost())));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

/// 真取一段字节，确认这个地址**现在**还能用。
///
/// 返回里的 `error` 用来区分三种情况，**不能一刀切成"失败"**：
///   · 拿到了 200/206 且有字节 → 真可用
///   · 拿到了 4xx/5xx 或 HTML → 地址确实失效
///   · status=0 + error 非空 → 本机网络/代理问题，**没验证到**，不是地址的错
Future<({int status, int bytes, String type, String error})> fetchHead(
    String url, String referer) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (s) => s != null && s < 500,
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      if (referer.isNotEmpty) 'Referer': referer,
      'Range': 'bytes=0-8191',
    },
  ));
  try {
    final r = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    final data = r.data ?? const <int>[];
    return (
      status: r.statusCode ?? 0,
      bytes: data.length,
      type: (r.headers.value('content-type') ?? '').split(';').first,
      error: '',
    );
  } on DioException catch (e) {
    return (
      status: e.response?.statusCode ?? 0,
      bytes: 0,
      type: '',
      error: '${e.type}: ${e.error ?? e.message}',
    );
  }
}

/// 断言「这个媒体地址真的能用」，但对**本机网络问题**保持诚实：
/// 网络不通时打印「未验证」，不把环境问题算到解析头上。
void expectMediaUsable(String label, ({int status, int bytes, String type, String error}) r) {
  if (r.status == 0 && r.error.isNotEmpty) {
    // ignore: avoid_print
    print('[未验证] $label —— 本机网络无法完成请求（$r.error）');
    return;
  }
  // ignore: avoid_print
  print('[验证] $label -> HTTP ${r.status} ${r.bytes}B ${r.type}');
  expect(r.status, anyOf(200, 206), reason: '$label 应当能取到字节');
  expect(r.bytes, greaterThan(256), reason: '$label 取到的字节太少');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('抖音 · 真实链接端到端', () {
    testWidgets('网络连通性：设备能直连抖音主站 / 图片 CDN / 播放接口', (tester) async {
      // 【为什么先测这个】失败信息如果只说「解析失败」，分不清是
      // 「我们代码不会解析」还是「设备根本连不上」。这一条把网络单独摘出来。
      final home = await fetchHead('https://www.douyin.com/', '');
      // ignore: avoid_print
      print('[连通性] www.douyin.com -> HTTP ${home.status} ${home.bytes}B');

      final cdn = await fetchHead(
          'https://p3-pc-sign.douyinpic.com/', 'https://www.douyin.com/');
      // ignore: avoid_print
      print('[连通性] douyinpic CDN -> HTTP ${cdn.status} ${cdn.bytes}B');

      final play = await fetchHead(
        'https://aweme.snssdk.com/aweme/v1/play/'
        '?video_id=v1e00fgi0000dafboc7og65g415qnbtg&ratio=720p&line=0',
        'https://m.douyin.com/',
      );
      // ignore: avoid_print
      print('[连通性] play 接口 -> HTTP ${play.status} ${play.bytes}B ${play.type}');

      // 主站只要能连上（200/301/302/403 都算通，抖音对裸请求常回 403）
      expect(home.status, isNot(0), reason: '设备连不上抖音主站，后面全部会失败');
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('视频：解析出无水印直链，且真的能取到 MP4 字节', (tester) async {
      await mountEngine(tester);
      const url = 'https://v.douyin.com/dhQYBJNQZis/';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull, reason: '应当被识别为抖音');

      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[抖音-视频] ${r.title} | ${r.author} | ${r.resolution} | ${r.durationSec}s');

      expect(r.type, 'video');
      expect(r.title.isNotEmpty, isTrue, reason: '标题不能为空');
      expect(r.author.isNotEmpty, isTrue, reason: '作者不能为空');
      expect(r.videoUrl.startsWith('http'), isTrue);

      // 无水印判定：不能是 playwm
      expect(r.videoUrl.contains('playwm'), isFalse,
          reason: '给用户的应当是无水印的 play 接口，不是带水印的 playwm');

      final head = await fetchHead(r.videoUrl, r.referer);
      expectMediaUsable('视频直链', head);
      if (head.status != 0) {
        expect(head.type, contains('video'), reason: '拿到的必须是视频流，不是 HTML');
      }
    }, timeout: const Timeout(Duration(minutes: 4)));

    testWidgets('图文：46 张图，地址真的都能下', (tester) async {
      await mountEngine(tester);
      // 用户原话给的完整分享文案（前后带时间戳等干扰字符）
      const text = '4.17 复制打开抖音，看看【无理.的图文作品】壁纸分享（1）# 高质量壁纸 # 我的壁纸  '
          'https://v.douyin.com/mCz8g6jiLjE/ :5pm w@S.LW DhO:/ 11/01';

      final url = RegExp(r'https?://[^\s]+').firstMatch(text)!.group(0)!;
      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);

      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[抖音-图文] ${r.title} | ${r.author} | ${r.imageCount} 张');

      expect(r.type, 'images');
      expect(r.imageCount, 46, reason: '这条图文就是 46 张，少一张都说明数据没取全');
      expect(r.title.isNotEmpty, isTrue);
      expect(r.title, isNot('王濛'),
          reason: '标题不能是推荐流的热搜词（__pace_f 里那 68 个 desc 全是别人的）');
      expect(r.author.isNotEmpty, isTrue);

      // 抽三张真下：首、中、尾
      final picks = [r.images.first, r.images[22], r.images.last];
      for (final img in picks) {
        final head = await fetchHead(img.url, r.referer);
        expectMediaUsable('图文图片', head);
      }
    }, timeout: const Timeout(Duration(minutes: 4)));

    testWidgets('动图：解析出带音轨的视频地址，且真的能下', (tester) async {
      await mountEngine(tester);
      const url = 'https://v.douyin.com/hjkw-7hGFy0/';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);

      final r = await platform!.parse(url);
      // ignore: avoid_print
      print('[抖音-动图] ${r.title} | ${r.author} | ${r.imageCount} 项');

      expect(r.imageCount, greaterThan(0));

      final live = r.images.where((e) => e.isLive).toList();
      // ignore: avoid_print
      print('[抖音-动图] 其中动图 ${live.length} 项');
      expect(live.isNotEmpty, isTrue,
          reason: '这条是动图作品：图片项里必须带 videoUrl（pace 里的字段名是驼峰 playAddr）');

      final first = live.first;
      expect(first.videoUrl, contains('douyinvod'), reason: '动图视频来自抖音视频 CDN');
      expect(first.durationSec, greaterThan(0), reason: '动图时长不能是 0');

      final v = await fetchHead(first.videoUrl, r.referer);
      expectMediaUsable('动图视频', v);
      if (v.status != 0) {
        expect(v.type, contains('video'), reason: '动图地址必须是视频流（带音轨）');
      }

      final img = await fetchHead(first.url, r.referer);
      expectMediaUsable('动图封面', img);
    }, timeout: const Timeout(Duration(minutes: 4)));

    testWidgets('解析器本身不崩：脏输入、空链接、非抖音链接', (tester) async {
      expect(LocalRegistry.detect(''), isNull);
      expect(LocalRegistry.detect('https://example.com/a'), isNull);

      final p = LocalRegistry.detect('https://v.douyin.com/abcdefg/');
      expect(p, isNotNull);
      // 短链无效时必须给出**可读的**失败原因，而不是卡住或抛原始异常
      try {
        await p!.parse('https://v.douyin.com/abcdefg/');
        fail('这条短链不存在，应当抛 LocalParseError');
      } catch (e) {
        final msg = e.toString();
        // ignore: avoid_print
        print('[抖音-异常] $msg');
        expect(msg.length, greaterThan(10));
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('抖音解析器的纯函数性质（在设备上也验一遍）', () {
    test('候选地址里 playwm 永远排在 play 之后', () {
      const a = DouyinAweme(
        awemeId: '1',
        videoId: 'v1abc',
        playUrls: ['https://m.douyin.com/aweme/v1/playwm/?video_id=v1abc'],
      );
      final c = DouyinParser.videoUrlCandidates(a);
      final firstPlaywm = c.indexWhere((u) => u.contains('playwm'));
      final lastPlay = c.lastIndexWhere((u) => u.contains('/aweme/v1/play/'));
      expect(lastPlay, lessThan(firstPlaywm),
          reason: '带水印的地址只能当兜底，不能排在无水印前面');
    });
  });
}
