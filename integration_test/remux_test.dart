// 原生转封装（MPEG-TS → MP4）的设备端验证。
//
// 【为什么不靠外部 push 测试数据】`flutter test` 每次都重装 App，
// App 私有目录会被清空 —— 手动 `adb push` 进去的文件一律消失。
// 所以这份测试**自己去下载**一段真实的 HLS 流（Apple 的公开测试流，
// 标准 TS 分片，不需要签名、不会过期），拼成 TS 再测转封装。
//
// 覆盖的正是 `TsRemuxer` 最容易出错的地方：
//   · MediaExtractor 能不能读 TS
//   · MediaMuxer 能不能写出可被系统识别的 MP4（ftyp）
//   · AAC 的 ADTS 头剥离 + csd-0 构造对不对（音频轨必须还在）
//   · 时长算得对不对（进度条靠它）
//
// 跑法：FLUTTER_TEST_X64=1 flutter test integration_test/remux_test.dart -d emulator-5554

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _ch = MethodChannel('xiaojingyu/media');

/// Apple 的公开 HLS 测试流（TS 分片，多年稳定）。
/// 【必须用 gear4】gear0 是**纯音频**流（分片是 .aac，一片才 7KB），
/// 拿它测转封装会得到「只有音频轨」的结果，验证不到视频那条路。
/// gear4 是真正的 h264 视频流（一片约 1.8MB）。
const _appleM3u8 =
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear4/prog_index.m3u8';

/// 只取前几片 —— 够验证转封装，又不至于让测试跑几分钟
const _maxSegments = 3;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('原生转封装（TS → MP4）', () {
    testWidgets('真实 HLS 分片拼成 TS，能转成可识别的 MP4', (tester) async {
      final dir = await getTemporaryDirectory();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (s) => s != null && s < 400,
      ));

      // ---- 1) 拉播放列表 ----
      final plRes = await dio.get<String>(
        _appleM3u8,
        options: Options(responseType: ResponseType.plain),
      );
      final playlist = plRes.data ?? '';
      if (playlist.contains('#EXT-X-KEY')) {
        markTestSkipped('这个测试流变成加密的了，换一个源');
        return;
      }
      final baseUri = Uri.parse(_appleM3u8);
      final segs = playlist
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && !e.startsWith('#'))
          .take(_maxSegments)
          .map((e) => baseUri.resolve(e).toString())
          .toList();
      expect(segs, isNotEmpty, reason: '播放列表里没有分片');

      // ---- 2) 下载并顺序拼接 ----
      final ts = File('${dir.path}/probe_joined.ts');
      final sink = ts.openWrite();
      var total = 0;
      for (final u in segs) {
        final r = await dio.get<List<int>>(
          u,
          // 【必须显式指定 bytes】BaseOptions 的默认 responseType 是 json，
          // 拿二进制会被当字符串解析然后类型转换炸掉
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = r.data ?? const <int>[];
        expect(bytes, isNotEmpty, reason: '分片是空的: $u');
        sink.add(bytes);
        total += bytes.length;
      }
      await sink.flush();
      await sink.close();
      // ignore: avoid_print
      print('[remux] 拼出 TS: ${total ~/ 1024}KB（${segs.length} 片）');
      expect(total, greaterThan(100 * 1024), reason: 'TS 太小，分片可能没下全');

      // ---- 3) 原生转封装 ----
      final out = File('${dir.path}/probe_remuxed.mp4');
      if (await out.exists()) await out.delete();

      final sw = Stopwatch()..start();
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('remuxTs', {
        'tsPath': ts.path,
        'outPath': out.path,
      });
      sw.stop();
      expect(r, isNotNull);

      final bytes = (r!['bytes'] as num?)?.toInt() ?? 0;
      final durationMs = (r['durationMs'] as num?)?.toInt() ?? 0;
      final vTracks = (r['videoTracks'] as num?)?.toInt() ?? 0;
      final aTracks = (r['audioTracks'] as num?)?.toInt() ?? 0;
      // ignore: avoid_print
      print('[remux] 输出 MP4: ${bytes ~/ 1024}KB / 时长 ${durationMs}ms / '
          '视频轨 $vTracks / 音频轨 $aTracks / 耗时 ${sw.elapsedMilliseconds}ms');

      // ---- 4) 逐项校验 ----
      expect(bytes, greaterThan(100 * 1024), reason: 'MP4 太小');
      expect(vTracks, 1, reason: '必须有一条视频轨');
      expect(aTracks, 1, reason: '必须有一条音频轨（Apple 测试流是 h264+aac）');
      expect(durationMs, greaterThan(1000), reason: '时长读不出来 = 容器无效');

      expect(await out.exists(), isTrue);
      final head =
          await out.openRead(0, 12).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final marker = String.fromCharCodes(head.sublist(4, 8));
      // ignore: avoid_print
      print('[remux] 文件头 4..8 = "$marker"');
      expect(marker, 'ftyp', reason: '必须是 MP4 容器，否则相册认不出');

      // 产物不该比 TS 小太多（只去掉了 TS 包头/填充）
      expect(bytes, greaterThan(total * 0.5), reason: '丢得太多了');

      // 清理
      try {
        await ts.delete();
        await out.delete();
      } catch (_) {}
    }, timeout: const Timeout(Duration(minutes: 6)));

    testWidgets('输入不存在时给出明确错误，不会崩', (tester) async {
      try {
        await _ch.invokeMethod('remuxTs', {
          'tsPath': '/data/local/tmp/definitely-not-here.ts',
          'outPath': '/data/local/tmp/x.mp4',
        });
        fail('不存在的输入应当报错');
      } on PlatformException catch (e) {
        // ignore: avoid_print
        print('[remux] 预期报错：${e.code} / ${e.message}');
        expect(e.message, isNotEmpty);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
