// 完整 HLS 链路：真实线上 m3u8 → 下载分片 → 拼接 → 原生转封装 → MP4。
//
// 【AcFun 的 pkey 是一次性签名 —— 这正是这条路走不通的原因】
// 实测（2026-11-15）：
//   · hls_probe 内部拿到 m3u8 后立刻 GET → 200
//   · 同一个 URL 隔 1 秒再用 curl / node fetch / App 请求 → 全是 403
// 也就是说播放列表地址**只能用一次**，拿给别人（或稍后再用）就废了。
// 再加上隐藏 WebView 里又拿不到它（明文被禁、播放器不初始化），
// AcFun 这类「一次性签名」的流在 App 侧确实做不了 —— 这是环境事实，不是实现缺陷。
//
// 保留这份测试是为了**将来**：换成一个公开可复用的 m3u8（无签名或长效签名）
// 就能直接跑通，用来确认整条链路。
//
// 要重跑：用 audit/probe/hls_probe.mjs 现取一条，替换下面的 _liveM3u8 ——
// 但注意它对 AcFun 一定失败（上面那条结论），只有换成别的源才有意义。
//
// 链接失效时这份测试会 skip 而不是 fail —— 过期是时间问题，不是代码问题。
// 要重跑：用 audit/probe/hls_probe.mjs 现取一条，替换下面的 _liveM3u8。
//
// 跑法：FLUTTER_TEST_X64=1 flutter test integration_test/hls_live_test.dart -d emulator-5554

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flashsave/services/hls_service.dart';

/// 2026-11-15 16:25 现取，pkey 有时效
const _liveM3u8 = 'PLACEHOLDER';

const _referer = 'https://www.acfun.cn/';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('完整链路：线上 m3u8 → 可播放的 MP4', (tester) async {
    final sw = Stopwatch()..start();

    HlsFetchResult? result;
    try {
      result = await HlsService.fetch(
        m3u8Url: _liveM3u8,
        referer: _referer,
        onProgress: (p, note) {
          // 只打关键节点，不然 41 个分片会刷屏
          if (p >= 0.79 || note.startsWith('转封装') || note == '完成') {
            // ignore: avoid_print
            print('[HLS] ${(p * 100).toStringAsFixed(0)}% $note');
          }
        },
      );
    } on HlsException catch (e) {
      final msg = e.toString();
      // ignore: avoid_print
      print('[HLS] 失败：$msg');
      if (msg.contains('HTTP 403') || msg.contains('HTTP 404') || msg.contains('空的')) {
        markTestSkipped('这条 pkey 链接已过期 —— 需要重新取一条再跑');
        return;
      }
      rethrow;
    }
    sw.stop();

    expect(result, isNotNull);
    final r = result;
    // ignore: avoid_print
    print('[HLS] 完成：${r.segments} 片 / ${r.bytes ~/ 1024}KB / '
        '${r.durationMs}ms / 总耗时 ${sw.elapsedMilliseconds}ms');

    expect(r.segments, greaterThan(30), reason: '这条流有 41 片');
    expect(r.bytes, greaterThan(10 * 1024 * 1024), reason: '20 秒 1080P 至少有十几 MB');
    expect(r.durationMs, greaterThan(18000));
    expect(r.durationMs, lessThan(22000));

    final f = File(r.mp4Path);
    expect(await f.exists(), isTrue);
    final head = await f.openRead(0, 12).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final marker = String.fromCharCodes(head.sublist(4, 8));
    // ignore: avoid_print
    print('[HLS] 文件头 4..8 = "$marker"');
    expect(marker, 'ftyp');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
