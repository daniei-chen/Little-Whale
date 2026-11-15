// 原生转封装（MPEG-TS → MP4）的设备端验证。
//
// 【为什么要单独验这一环】
// HLS 那条链路上，其它部分都已经被覆盖：
//   · 播放列表解析 → test/hls_test.dart 的 12 条单测
//   · 分片下载 + 拼接 → 代码就绪（HTTP 逻辑，与平台无关）
//   · **TS → MP4 转封装 → 只有这一环必须在真机上跑**（MediaExtractor/MediaMuxer）
//
// 因为拿不到"有时效的线上 m3u8"，这里用一个**已经被宿主机 ffmpeg 验证过**的
// TS 文件当输入：
//   来源：AcFun ac41234567 的前 4 个分片拼接（16.7MB）
//   宿主机 ffprobe 确认：mpegts / h264 1920x1072 / aac / 20.05 秒
//   宿主机 ffmpeg 转封装确认：16.2MB mp4，时长一致
//
// 如果设备上的 MediaExtractor/MediaMuxer 也能得到同样结果，就说明
// 「同一份 TS → 可播放的 MP4」这条路在 Android 上成立。
//
// 【测试文件怎么来的】
//   adb push test.ts /sdcard/Android/data/cn.flashsave.flashsave/files/test.ts
// 文件不存在时这条测试会 skip（推送是手动步骤，不该让 CI 变红）。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _ch = MethodChannel('xiaojingyu/media');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('原生转封装（TS → MP4）', () {
    testWidgets('真实 TS 能转成 MP4，且时长/编码正确', (tester) async {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        markTestSkipped('拿不到 App 私有外部目录');
        return;
      }
      final ts = File('${dir.path}/test.ts');
      if (!await ts.exists()) {
        // ignore: avoid_print
        print('[remux] 跳过的原因：${ts.path} 不存在。'
            '推送方式：adb push test.ts /sdcard/Android/data/cn.flashsave.flashsave/files/test.ts');
        markTestSkipped('测试用 TS 未推送到设备');
        return;
      }
      final tsSize = await ts.length();
      // ignore: avoid_print
      print('[remux] 输入 TS: ${tsSize ~/ 1024}KB');

      final out = File('${dir.path}/remuxed.mp4');
      if (await out.exists()) await out.delete();

      final sw = Stopwatch()..start();
      Map<dynamic, dynamic>? r;
      try {
        r = await _ch.invokeMethod<Map<dynamic, dynamic>>('remuxTs', {
          'tsPath': ts.path,
          'outPath': out.path,
        });
      } on PlatformException catch (e) {
        fail('转封装抛错：${e.code} / ${e.message}');
      }
      sw.stop();
      expect(r, isNotNull);

      final bytes = (r!['bytes'] as num?)?.toInt() ?? 0;
      final durationMs = (r['durationMs'] as num?)?.toInt() ?? 0;
      final vTracks = (r['videoTracks'] as num?)?.toInt() ?? 0;
      final aTracks = (r['audioTracks'] as num?)?.toInt() ?? 0;
      // ignore: avoid_print
      print('[remux] 输出 MP4: ${bytes ~/ 1024}KB / 时长 ${durationMs}ms / '
          '视频轨 $vTracks / 音频轨 $aTracks / 耗时 ${sw.elapsedMilliseconds}ms');

      expect(bytes, greaterThan(100 * 1024), reason: 'MP4 太小');
      expect(vTracks, 1, reason: '必须有一条视频轨');
      expect(aTracks, 1, reason: '必须有一条音频轨（AcFun 的流带 AAC）');
      // 输入是 20.05 秒，允许 5% 误差
      expect(durationMs, greaterThan(18000), reason: '时长应接近输入的 20 秒');
      expect(durationMs, lessThan(22000));

      // 产物文件头必须是 ftyp（否则相册认不出）
      expect(await out.exists(), isTrue);
      final head = await out.openRead(0, 12).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final marker = String.fromCharCodes(head.sublist(4, 8));
      // ignore: avoid_print
      print('[remux] 文件头 4..8 = "$marker"');
      expect(marker, 'ftyp', reason: '必须是 MP4 容器');

      // 产物应比 TS 略小（去掉 TS 的包头/填充），但不会小太多
      expect(bytes, greaterThan(tsSize * 0.8), reason: '不该丢帧丢到这个程度');
      expect(bytes, lessThan(tsSize + 1024 * 1024), reason: '不该比输入还大');

      // ignore: avoid_print
      print('[remux] ✅ 转封装成功：$tsSize → $bytes 字节');
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('输入不存在时给出明确错误，不会崩', (tester) async {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        markTestSkipped('拿不到 App 私有外部目录');
        return;
      }
      try {
        await _ch.invokeMethod('remuxTs', {
          'tsPath': '${dir.path}/not-exist.ts',
          'outPath': '${dir.path}/x.mp4',
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
