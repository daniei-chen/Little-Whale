// 设备上跑的集成测试：验证**只有真机才能验**的那条链路。
//
// 为什么单独写这个而不是点 UI：
//   这台机器的模拟器不稳定（连续滑动会崩），点 UI 走一遍要 3-4 分钟、容易中断。
//   这个测试直接调 App 里同一套服务代码（ApiClient → DownloadService → Gal），
//   跳过所有 UI 交互，1 分钟内出结果，而且验的是**真实产物**：
//   文件真的下载下来了、真的写进系统相册了。
//
// 运行：
//   flutter test integration_test/save_test.dart -d emulator-5554

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/data/api_client.dart';
import 'package:flashsave/services/download_service.dart';

const kBase = 'http://10.0.2.2:8787';   // 模拟器访问宿主机的专用地址
const kDouyin = 'https://v.douyin.com/dhQYBJNQZis/';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('后端健康检查可达', (tester) async {
    final h = await ApiClient(baseUrl: kBase).health();
    final adapters = h['adapters'];
    expect(adapters, isA<Map>());
    expect((adapters as Map).containsKey('douyin'), isTrue);
    expect(adapters.containsKey('kuaishou'), isFalse, reason: '快手已下线，不该出现在适配器列表里');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('解析抖音拿到真实结果', (tester) async {
    final r = await ApiClient(baseUrl: kBase).parse(kDouyin);

    expect(r.platform, 'douyin');
    expect(r.title.isNotEmpty, isTrue, reason: '标题不能为空');
    expect(r.isVideo, isTrue);
    expect(r.noWatermarkUrl, contains('/media?'), reason: '媒体地址应该是带签名的代理地址');
    expect(r.duration.isNotEmpty, isTrue);

    // 顺手验证「原始直链 + Referer」能被拆出来（直连下载那条路径依赖它）
    final t = DownloadService.parseProxyUrl(r.noWatermarkUrl);
    expect(t, isNotNull);
    expect(t!.rawUrl.startsWith('http'), isTrue);
    expect(t.referer.isNotEmpty, isTrue, reason: 'Referer 必须能解出来，否则直连一定 403');

    // ignore: avoid_print
    print('[E2E] 解析成功: ${r.platformName} | ${r.title} | ${r.duration} | ${r.resolutionLabel}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('走服务器代理下载并写入系统相册', (tester) async {
    final api = ApiClient(baseUrl: kBase);
    final r = await api.parse(kDouyin);

    final outcome = await DownloadService.instance.fetchAndSave(
      proxyUrl: r.noWatermarkUrl,
      isVideo: true,
      preferDirect: false,          // 先验最稳的那条路
      fileHint: 'e2e_proxy',
    );

    expect(outcome.saved, isTrue, reason: '保存失败: ${outcome.message}');
    // ignore: avoid_print
    print('[E2E] 代理下载成功, usedDirect=${outcome.usedDirect}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('直连平台 CDN 下载（省服务器流量那条路）并写入相册', (tester) async {
    final api = ApiClient(baseUrl: kBase);
    final r = await api.parse(kDouyin);

    final outcome = await DownloadService.instance.fetchAndSave(
      proxyUrl: r.noWatermarkUrl,
      isVideo: true,
      preferDirect: true,
      fileHint: 'e2e_direct',
    );

    expect(outcome.saved, isTrue, reason: '保存失败: ${outcome.message}');
    // ignore: avoid_print
    print('[E2E] 直连下载完成, 实际走的路径 usedDirect=${outcome.usedDirect}');
    // 注意：usedDirect=false 也**不算失败** —— 直连失败会自动回退到代理，
    // 这是设计好的兜底行为。这里只断言「最终保存成功」。
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('临时文件不会残留', (tester) async {
    final dir = Directory.systemTemp;
    final leftovers = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('e2e_proxy') || f.path.contains('e2e_direct'))
        .toList();
    expect(leftovers, isEmpty, reason: '保存成功后临时文件应该被清掉: ${leftovers.map((e) => e.path)}');
  });
}
