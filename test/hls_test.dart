// HLS 播放列表解析的单测。
//
// 这份覆盖的是「AcFun 这类站到底能不能变成可保存的 MP4」的第一步 —— 解析。
// 用真实抓到的 m3u8 形态做样本（2026-11，AcFun 作品页 ac41234567 的 1080P 流）：
//   41 个 .ts 分片、每段 5 秒、相对路径、带 pkey 查询串、无加密、非 fMP4
//
// 另外把「暂不支持的两种形态」（AES 加密 / fMP4）也钉住 ——
// 它们必须给出明确原因，而不是下出一堆碎文件。

import 'package:flutter_test/flutter_test.dart';
import 'package:flashsave/local/hls.dart';

const _base = 'https://tx-safety-video.acfun.cn/mediacloud/acfun/acfun_video/'
    '09af70ad9843b682-hls_1080p_h264_60_1.m3u8?pkey=ABC123';

/// 真实形态：相对路径 + pkey 沿用（Segment 的相对路径不带 pkey 时也能解析）
const _plainTs = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:5
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:5.000000,
09af70ad9843b682-hls_1080p_h264_60_1.00000.ts?pkey=ABC123
#EXTINF:5.000000,
09af70ad9843b682-hls_1080p_h264_60_1.00001.ts?pkey=ABC123
#EXTINF:5.033011,
09af70ad9843b682-hls_1080p_h264_60_1.00002.ts?pkey=ABC123
#EXT-X-ENDLIST
''';

/// 主播放列表：两条子流，高带宽在后
const _master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080
high/index.m3u8
''';

/// AES-128 加密
const _encrypted = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="https://example.com/key.bin"
#EXTINF:5,
seg0.ts
#EXT-X-ENDLIST
''';

/// fMP4 分片
const _fmp4 = '''
#EXTM3U
#EXT-X-MAP:URI="init.mp4"
#EXTINF:5,
seg0.m4s
#EXT-X-ENDLIST
''';

void main() {
  group('普通 TS 播放列表（AcFun 的实际形态）', () {
    test('分片数量、时长、绝对地址都对', () {
      final p = parseHlsPlaylist(_plainTs, _base)!;
      expect(p.segments.length, 3);
      expect(p.durations, [5.0, 5.0, 5.033011]);
      expect(p.totalDurationSec, closeTo(15.033, 0.01));
      expect(p.isMaster, isFalse);
      expect(p.encrypted, isFalse);
      expect(p.fmp4, isFalse);
      expect(p.downloadable, isTrue);
      expect(p.unsupportedReason, isEmpty);
    });

    test('相对路径被解析成绝对地址，并保留查询串', () {
      final p = parseHlsPlaylist(_plainTs, _base)!;
      expect(p.segments.first.startsWith('https://tx-safety-video.acfun.cn/'), isTrue);
      expect(p.segments.first.endsWith('.00000.ts?pkey=ABC123'), isTrue);
      // 目录部分要跟着 base 走（这是相对路径解析最容易出错的地方）
      expect(p.segments.first, contains('/mediacloud/acfun/acfun_video/'));
    });

    test('绝对地址原样保留', () {
      const text = '#EXTM3U\n#EXTINF:5,\nhttps://cdn.example.com/a.ts\n#EXT-X-ENDLIST\n';
      final p = parseHlsPlaylist(text, _base)!;
      expect(p.segments.single, 'https://cdn.example.com/a.ts');
    });
  });

  group('暂不支持的两种形态：必须说清楚，不能下碎文件', () {
    test('AES-128 加密 → downloadable=false 且原因提到 AES', () {
      final p = parseHlsPlaylist(_encrypted, _base)!;
      expect(p.encrypted, isTrue);
      expect(p.downloadable, isFalse);
      expect(p.unsupportedReason, contains('AES'));
    });

    test('fMP4（EXT-X-MAP）→ downloadable=false 且原因提到 fMP4', () {
      final p = parseHlsPlaylist(_fmp4, _base)!;
      expect(p.fmp4, isTrue);
      expect(p.downloadable, isFalse);
      expect(p.unsupportedReason, contains('fMP4'));
    });

    test('METHOD=NONE 不算加密（有些站用它覆盖前面的 KEY）', () {
      const text = '#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:5,\nseg0.ts\n';
      final p = parseHlsPlaylist(text, _base)!;
      expect(p.encrypted, isFalse);
      expect(p.downloadable, isTrue);
    });
  });

  group('主播放列表', () {
    test('识别为 master，并把子流列出来', () {
      final p = parseHlsPlaylist(_master, _base)!;
      expect(p.isMaster, isTrue);
      expect(p.variants.length, 2);
      expect(p.segments, isEmpty);
      expect(p.downloadable, isFalse, reason: '主列表本身没有分片，不能直接下');
      expect(p.variants.first, endsWith('low/index.m3u8'));
    });

    test('选带宽最高的那条子流', () {
      final p = parseHlsPlaylist(_master, _base)!;
      final best = pickBestVariant(p);
      expect(best, isNotNull);
      expect(best, endsWith('high/index.m3u8'),
          reason: 'BANDWIDTH=3000000 比 800000 高，应该选它');
    });

    test('只有一条子流时直接返回它', () {
      const text = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nonly/index.m3u8\n';
      final p = parseHlsPlaylist(text, _base)!;
      expect(pickBestVariant(p), endsWith('only/index.m3u8'));
    });
  });

  group('边界', () {
    test('不是 m3u8 → null（不能把任意文本当播放列表）', () {
      expect(parseHlsPlaylist('<html>404</html>', _base), isNull);
      expect(parseHlsPlaylist('', _base), isNull);
      expect(parseHlsPlaylist('#EXTM3U', _base)?.segments, isEmpty);
    });

    test('前导空行/空白不影响识别', () {
      final p = parseHlsPlaylist('\n\n  $_plainTs', _base);
      expect(p, isNotNull);
      expect(p!.segments.length, 3);
    });

    test('坏 URL 被跳过，不会让整条流解析失败', () {
      const text = '#EXTM3U\n#EXTINF:5,\nmagnet:?xt=abc\n#EXTINF:5,\nok.ts\n';
      final p = parseHlsPlaylist(text, _base)!;
      expect(p.segments.length, 1, reason: '非 http(s) 的分片应当被丢弃');
      expect(p.segments.single, endsWith('ok.ts'));
    });
  });
}
