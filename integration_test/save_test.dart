// 设备上验证「**真的保存进相册**」这条只有真机才跑得通的链路。
//
// 【为什么要重写这个文件】
// 它原来是给「服务器模式」写的：先请求 `http://10.0.2.2:8787` 的后端，
// 拿到带签名的 `/media?...` 代理地址再下载。而服务器模式在 v0.0.9 之前
// 就已经整体移除了（App 现在是纯本地解析，不需要任何后端）。
// 于是这个文件成了一份**永远跑不过、也没人再跑**的死代码 ——
// 更要命的是它给了后来者一个错误的印象：「保存链路有测试守着」。
//
// 现在改成验证真实的产品路径：
//   本地解析 → 下载直链（带 Referer）→ 写进系统相册 → 临时文件清理
//
// 跑法：
//   FLUTTER_TEST_X64=1 flutter test integration_test/save_test.dart -d emulator-5554

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/local/engine.dart';
import 'package:flashsave/local/registry.dart';
import 'package:flashsave/services/download_service.dart';

/// 把隐藏 WebView 挂进 widget 树 —— 不挂载的话页面根本不会加载
Future<void> mountEngine(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalEngineHost())));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (LocalEngine.instance.isReady) break;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('保存到相册（纯本地，不经过任何服务器）', () {
    testWidgets('抖音视频：下载后真的写进系统相册', (tester) async {
      await mountEngine(tester);
      const url = 'https://v.douyin.com/dhQYBJNQZis/';

      final platform = LocalRegistry.detect(url);
      expect(platform, isNotNull);
      final r = await platform!.parse(url);

      expect(r.type, 'video');
      expect(r.videoUrl.startsWith('http'), isTrue);
      expect(r.referer.isNotEmpty, isTrue, reason: '本地模式必须带 Referer，否则 CDN 403');

      final outcome = await DownloadService.instance.fetchAndSave(
        proxyUrl: r.videoUrl,
        isVideo: true,
        referer: r.referer,
        fileHint: 'e2e_video',
      );
      // ignore: avoid_print
      print('[保存] 视频: saved=${outcome.saved} msg=${outcome.message}');
      expect(outcome.saved, isTrue, reason: '保存失败: ${outcome.message}');
    }, timeout: const Timeout(Duration(minutes: 6)));

    testWidgets('抖音图文：首图下载后真的写进系统相册', (tester) async {
      await mountEngine(tester);
      const url = 'https://v.douyin.com/mCz8g6jiLjE/';

      final r = await LocalRegistry.detect(url)!.parse(url);
      expect(r.type, 'images');
      expect(r.images.isNotEmpty, isTrue);

      final outcome = await DownloadService.instance.fetchAndSave(
        proxyUrl: r.images.first.url,
        isVideo: false,
        referer: r.referer,
        fileHint: 'e2e_image',
      );
      // ignore: avoid_print
      print('[保存] 图片: saved=${outcome.saved} msg=${outcome.message}');
      expect(outcome.saved, isTrue, reason: '保存失败: ${outcome.message}');
    }, timeout: const Timeout(Duration(minutes: 6)));

    testWidgets('临时文件不残留（相册拿到副本后就该删掉）', (tester) async {
      final dir = Directory.systemTemp;
      final leftovers = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('e2e_video') || f.path.contains('e2e_image'))
          .toList();
      expect(leftovers, isEmpty,
          reason: '保存成功后临时文件应该被清掉: ${leftovers.map((e) => e.path)}');
    });
  });

  group('扩展名判定（纯函数，但直接决定相册能不能识别）', () {
    // 【为什么这几条重要】各平台的无水印直链**往往没有扩展名**，
    // 早期兜底返回 .mp4，于是图片被存成 .mp4 文件，媒体库不认 ——
    // 用户看到「提示保存成功，但相册里找不到」。这里把每个分支都钉住。
    test('MP4 / QuickTime / WebM / 常见图片都能认出来', () {
      expect(
        DownloadService.extFromMagicBytes([0, 0, 0, 0x14, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]),
        '.mp4',
        reason: 'ftyp isom → mp4',
      );
      expect(
        DownloadService.extFromMagicBytes([0, 0, 0, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74, 0x20, 0x20]),
        '.mov',
        reason: 'ftyp qt   → QuickTime（小红书常这么报）',
      );
      expect(
        DownloadService.extFromMagicBytes([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0, 0, 0, 0, 0]),
        '.webm',
      );
      expect(
        DownloadService.extFromMagicBytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]),
        '.jpg',
      );
      expect(
        DownloadService.extFromMagicBytes([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0]),
        '.png',
      );
      expect(
        DownloadService.extFromMagicBytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]),
        '.webp',
      );
      expect(
        DownloadService.extFromMagicBytes([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0, 0, 0, 0, 0]),
        '.gif',
      );
    });

    test('认不出来的字节返回 null（让上层按 content-type / 提示类型兜底）', () {
      expect(DownloadService.extFromMagicBytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]), isNull);
      expect(DownloadService.extFromMagicBytes([0, 0]), isNull, reason: '太短也不能崩');
    });
  });
}
