// 通用适配器的探针脚本必须是**合法 JS**。
//
// 【为什么需要这条测试】v0.3.8 我把探针写崩了两次：
//
//   1. `var __sn = '''+ name + r''';`
//      —— Dart 的 `r'''` 是 raw 字符串，**不会补引号**，
//      生成出来是 `var __sn = 微视;` → 整个脚本语法错误
//   2. 改成 `final sn = "var __sn = '...';"` 后，模板里还留着 `var __sn = ` 前缀
//      → 生成 `var __sn = var __sn = '微视';;`
//
// 两次的表现都是「13 个平台全线报『页面没能读到内容』」，
// 而 `flutter analyze` 全绿、单元测试全过 —— 因为**Dart 侧看不出 JS 的问题**。
//
// 这条测试把「生成出来的 JS」交给宿主机的 node 做语法检查，
// 让这类错误在桌面阶段就暴露，而不是等设备端一个平台一个平台失败。
//
// 【前提】宿主机需要有 `node`。没有的话这条测试会 skip（不阻塞 CI 之外的本地开发）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flashsave/local/generic.dart';

/// 造几个不同配置的通用平台，覆盖「有/无选择器」「有/无图片白名单」这些分支，
/// 因为 debugScript() 里对它们是条件拼接的 —— 只测一种配置会漏掉另外几种。
List<GenericLocalPlatform> _variants() => [
      GenericLocalPlatform(
        key: 'plain',
        name: '无配置平台',
        hosts: const ['example.com'],
        referer: 'https://example.com/',
      ),
      GenericLocalPlatform(
        key: 'full',
        name: '全配置平台',
        hosts: const ['example.org'],
        referer: 'https://example.org/',
        videoSelector: 'video.main, div.player video',
        imageAllow: const ['cdn.example.org', 'img.example.org'],
        minImageWidth: 400,
        titleSelector: 'h1.article-title',
        authorSelector: 'a.author-name',
        settle: const Duration(milliseconds: 500),
        timeout: const Duration(seconds: 8),
        failHint: '这个站的作品只在 App 里',
        expectVideo: true,
      ),
      GenericLocalPlatform(
        key: 'quoted',
        name: "带'单引号\"和\\反斜杠", // 名字里塞危险字符，确认注入没把它带进 JS
        hosts: const ['example.net'],
        referer: 'https://example.net/',
      ),
    ];

Future<bool> _nodeAvailable() async {
  try {
    final r = await Process.run('node', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('probe_js_');
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('三种配置生成的探针脚本都能通过 node 语法检查', () async {
    if (!await _nodeAvailable()) {
      markTestSkipped('宿主机没有 node，跳过 JS 语法检查');
      return;
    }

    for (final p in _variants()) {
      final js = p.debugScript();
      expect(js.length, greaterThan(1000), reason: '${p.name} 生成的脚本太短，拼接可能断了');

      // 基本形态检查：必须是一个完整 IIFE
      expect(js.contains('(function'), isTrue, reason: '${p.name} 缺少 IIFE 开头');
      expect(js.trimRight().endsWith('})()'), isTrue,
          reason: '${p.name} 结尾不是 })()，拼接可能被截断');

      final f = File('${tmp.path}/probe_${p.key}.js');
      await f.writeAsString(js);
      final r = await Process.run('node', ['--check', f.path]);
      expect(
        r.exitCode,
        0,
        reason: '${p.name} 的探针脚本有 JS 语法错误：\n${r.stderr}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Dart 变量注入不会把引号带进 JS（v0.3.8 的两次事故）', () async {
    final p = GenericLocalPlatform(
      key: 'quoted',
      name: "带'单引号",
      hosts: const [],
      referer: '',
      titleSelector: "h1.title'with-quote",
      authorSelector: "a.author'x",
      videoSelector: "video'broken",
    );
    final js = p.debugScript();

    // 每个注入点都应该是「'…'」包好的字符串字面量，
    // 且里面的引号已经被处理掉 —— 出现 `''` 之外的裸引号就说明注入没转义
    expect(js.contains("var __ts = 'h1.title'"), isFalse,
        reason: '选择器里的单引号没有被清理，会提前结束 JS 字符串');
    // 至少要能跑过 node --check（这是最终判据）
    if (await _nodeAvailable()) {
      final f = File('${tmp.path}/probe_quoted2.js');
      await f.writeAsString(js);
      final r = await Process.run('node', ['--check', f.path]);
      expect(r.exitCode, 0, reason: '带引号的配置把 JS 写坏了：\n${r.stderr}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
