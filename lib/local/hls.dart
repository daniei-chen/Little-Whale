// HLS（m3u8）播放列表解析 —— 纯函数，不碰网络、不碰文件。
//
// 【为什么要做 HLS】AcFun 这类站的 `<video src>` 是一份 m3u8 播放列表，
// 里面列着几十个 .ts 分片。直接把 m3u8 下下来是个几 KB 的文本，相册打不开。
// 真正能用需要：解析列表 → 下载分片 → 拼成整段 TS → 转封装成 MP4。
//
// 这份文件只负责第一步（解析），所以它能在桌面 `flutter test` 里被单测覆盖；
// 网络与转换分别由 HlsDownloader 和原生层负责。
//
// 【覆盖范围，以及为什么先只做这些】
//   ✅ 普通 TS 分片（AcFun / 大多数国内站的形态）
//   ✅ 主播放列表 → 选一个子流（按带宽优先，或第一个）
//   ✅ 相对路径 / 绝对路径
//   ⛔ AES-128 加密（`#EXT-X-KEY`）—— 需要解密，暂不支持，**明确报错**
//   ⛔ fMP4（`#EXT-X-MAP`）—— 分片是 .m4s，拼接规则不同，暂不支持
// 后面两种一旦遇到就直接说清楚，不会下出一堆碎文件。

/// 一条 HLS 播放列表的解析结果
class HlsPlaylist {
  /// 分片地址（已解析成绝对 URL，按播放顺序）
  final List<String> segments;

  /// 每个分片的时长（秒），与 [segments] 一一对应；解析不到时为 0
  final List<double> durations;

  /// 主播放列表里的子流地址（自己不是主列表时为空）
  final List<String> variants;

  /// 是否带 `#EXT-X-KEY`（AES 加密）
  final bool encrypted;

  /// 是否带 `#EXT-X-MAP`（fMP4 分片）
  final bool fmp4;

  /// 这个对象是不是「主播放列表」（只有子流、没有分片）
  final bool isMaster;

  /// 解析时用到的原始行（去掉空行），pickBestVariant 靠它对带宽
  final List<String> rawLines;

  const HlsPlaylist({
    required this.segments,
    required this.durations,
    required this.variants,
    required this.encrypted,
    required this.fmp4,
    required this.isMaster,
    required this.rawLines,
  });

  /// 估算总时长（秒）
  double get totalDurationSec =>
      durations.fold<double>(0, (a, b) => a + b);

  /// 能直接下载吗
  bool get downloadable =>
      !isMaster && segments.isNotEmpty && !encrypted && !fmp4;

  /// 不能下载时的可读原因（能下载返回空串）
  String get unsupportedReason {
    if (isMaster) return '这是主播放列表，需要先选一条子流';
    if (segments.isEmpty) return '播放列表里没有分片';
    if (encrypted) return '这条流是 AES 加密的（#EXT-X-KEY），App 暂不支持解密';
    if (fmp4) return '这条流是 fMP4 分片（#EXT-X-MAP），拼接规则不同，暂不支持';
    return '';
  }
}

/// 解析 m3u8 文本。
///
/// [baseUrl] 用来把相对路径解析成绝对 URL（必须传**播放列表自己的地址**，
/// 不是页面地址 —— 分片的相对路径是相对于 m3u8 的）。
///
/// 不是 m3u8（没有 `#EXTM3U`）时返回 null。
HlsPlaylist? parseHlsPlaylist(String text, String baseUrl) {
  final src = text.trimLeft();
  if (!src.startsWith('#EXTM3U')) return null;

  final lines = src
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  final segments = <String>[];
  final durations = <double>[];
  final variants = <String>[];
  var encrypted = false;
  var fmp4 = false;

  double pendingDuration = 0;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (line.startsWith('#EXT-X-KEY')) {
      // `METHOD=NONE` 不算加密（有些站会显式写一条 NONE 覆盖前面的 KEY）
      final m = RegExp(r'METHOD=([A-Z0-9-]+)', caseSensitive: false).firstMatch(line);
      final method = (m?.group(1) ?? '').toUpperCase();
      if (method.isNotEmpty && method != 'NONE') encrypted = true;
      continue;
    }
    if (line.startsWith('#EXT-X-MAP')) {
      fmp4 = true;
      continue;
    }
    if (line.startsWith('#EXTINF')) {
      // `#EXTINF:5.000000,` 或 `#EXTINF:5,`（也可能带标题）
      final m = RegExp(r'#EXTINF:\s*([0-9.]+)').firstMatch(line);
      pendingDuration = double.tryParse(m?.group(1) ?? '') ?? 0;
      continue;
    }
    if (line.startsWith('#')) continue;

    // 非 `#` 开头的行 = URI（分片或子流）
    final abs = _resolve(baseUrl, line);
    if (abs == null) continue;

    // 紧跟在 `#EXT-X-STREAM-INF` 后面的是子流
    if (_prevIsStreamInf(lines, i)) {
      variants.add(abs);
      continue;
    }
    segments.add(abs);
    durations.add(pendingDuration);
    pendingDuration = 0;
  }

  // 判断是不是主播放列表：有 STREAM-INF 且没有分片
  final isMaster = variants.isNotEmpty && segments.isEmpty;

  return HlsPlaylist(
    segments: segments,
    durations: durations,
    variants: variants,
    encrypted: encrypted,
    fmp4: fmp4,
    isMaster: isMaster,
    rawLines: lines,
  );
}

/// 往上找最近一条非空、非注释的行，看它是不是 `#EXT-X-STREAM-INF`
bool _prevIsStreamInf(List<String> lines, int index) {
  for (var j = index - 1; j >= 0; j--) {
    final l = lines[j];
    if (l.startsWith('#EXT-X-STREAM-INF')) return true;
    // 中间允许夹着别的标签（比如 #EXT-X-MEDIA），但遇到 EXTINF 就说明不是子流
    if (l.startsWith('#EXTINF') || (!l.startsWith('#'))) return false;
  }
  return false;
}

/// 把 URI 解析成绝对地址；解析不出来返回 null
String? _resolve(String baseUrl, String uri) {
  try {
    final base = Uri.parse(baseUrl);
    final r = base.resolve(uri);
    if (r.scheme != 'http' && r.scheme != 'https') return null;
    return r.toString();
  } catch (_) {
    return null;
  }
}

/// 从主播放列表里挑一条子流。
///
/// 优先挑**带宽最高**的那条（用户来存视频，当然要最清晰的），
/// 读不到 BANDWIDTH 时退回第一条。
///
/// 返回的是 [parsed.variants] 里的元素（绝对 URL），不是原始行。
String? pickBestVariant(HlsPlaylist parsed) {
  if (parsed.variants.isEmpty) return null;
  if (parsed.variants.length == 1) return parsed.variants.first;

  var bestBw = -1;
  var bestIdx = 0;
  var variantIdx = 0;
  var pendingBw = -1;

  for (final line in parsed.rawLines) {
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      final m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      pendingBw = int.tryParse(m?.group(1) ?? '') ?? 0;
      continue;
    }
    if (line.startsWith('#')) continue;

    if (pendingBw >= 0) {
      if (pendingBw > bestBw) {
        bestBw = pendingBw;
        bestIdx = variantIdx;
      }
      pendingBw = -1;
    }
    variantIdx++;
  }

  if (bestIdx >= parsed.variants.length) return parsed.variants.first;
  return parsed.variants[bestIdx];
}
