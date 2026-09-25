import 'dart:convert';

/// 一张图文图片（也可能是「动图」）
class ResultImage {
  final String url; // 已带签名的代理地址
  final String? thumb;
  final int width;
  final int height;
  final int index;

  /// **动图**对应的短视频地址。非动图时为空。
  /// 抖音的图文作品里，动图每张都挂着一个带音轨的短视频 ——
  /// 有它才能「存成动图」而不是一张死图。
  final String videoUrl;

  /// 动图视频时长（秒）
  final int durationSec;

  const ResultImage({
    required this.url,
    this.thumb,
    this.width = 0,
    this.height = 0,
    this.index = 0,
    this.videoUrl = '',
    this.durationSec = 0,
  });

  /// 是不是动图
  bool get isLive => videoUrl.isNotEmpty;

  factory ResultImage.fromJson(Map<String, dynamic> j) => ResultImage(
        url: (j['url'] ?? '') as String,
        thumb: j['thumb'] as String?,
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        index: (j['index'] as num?)?.toInt() ?? 0,
        videoUrl: (j['videoUrl'] ?? '') as String,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'thumb': thumb,
        'width': width,
        'height': height,
        'index': index,
        if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
        if (durationSec > 0) 'durationSec': durationSec,
      };
}

/// 解析结果 —— 与后端 `POST /parse` 的 data 字段一一对应
class ParseResult {
  final String id;
  final String platform;
  final String platformName;
  final String platformShort;
  final String platformColor; // #RRGGBB
  final String platformSoft; // rgba(...)
  final String type; // video | images
  final String title;
  final String author;
  final String authorInitial;
  final String duration;
  final String resolution;
  final String size;
  final String publishTime;
  final String music;
  final String coverUrl;
  final String noWatermarkUrl;
  final String watermarkUrl;
  final List<ResultImage> images;
  final int imageCount;
  final String sourceUrl;

  /// 下载媒体时要带的 Referer。
  ///
  /// 服务器模式不用管它（代理地址里已经签了 Referer）；
  /// **本地解析模式必须要** —— 拿到的是平台原始直链，各平台 CDN 都有防盗链，
  /// 不带 Referer 会直接 403。
  final String referer;

  /// 这条结果是本地解析出来的（没经过服务器）
  final bool local;

  final int parsedAt;
  final bool cached;

  const ParseResult({
    required this.id,
    required this.platform,
    required this.platformName,
    this.platformShort = '',
    this.platformColor = '#4D6BFE',
    this.platformSoft = 'rgba(77,107,254,0.08)',
    required this.type,
    required this.title,
    this.author = '',
    this.authorInitial = '',
    this.duration = '',
    this.resolution = '',
    this.size = '',
    this.publishTime = '',
    this.music = '',
    this.coverUrl = '',
    this.noWatermarkUrl = '',
    this.watermarkUrl = '',
    this.images = const [],
    this.imageCount = 0,
    this.sourceUrl = '',
    this.referer = '',
    this.local = false,
    this.parsedAt = 0,
    this.cached = false,
  });

  /// 由「本地解析结果」构造出一条标准结果。
  ///
  /// 媒体地址存的是**平台原始直链**，下载时靠 [referer] 过防盗链。
  factory ParseResult.fromLocal(
    String platform,
    String platformName,
    String type,
    String title, {
    String author = '',
    String cover = '',
    int durationSec = 0,
    String resolution = '',
    String publishTime = '',
    String music = '',
    String videoUrl = '',
    String referer = '',
    List<Map<String, dynamic>> images = const [],
    String sourceUrl = '',
  }) {
    String two(int v) => v.toString().padLeft(2, '0');
    final dur = durationSec <= 0
        ? ''
        : '${two(durationSec ~/ 60)}:${two(durationSec % 60)}';

    final cleanAuthor = author.replaceAll('@', '');

    return ParseResult(
      id: '${platform}_local_${DateTime.now().millisecondsSinceEpoch}',
      platform: platform,
      platformName: platformName,
      type: type,
      title: title.isEmpty ? '未命名作品' : title,
      author: author.isNotEmpty && !author.startsWith('@') ? '@$author' : author,
      authorInitial: cleanAuthor.isEmpty ? '未' : cleanAuthor.substring(0, 1),
      duration: dur,
      resolution: resolution,
      publishTime: publishTime,
      music: music,
      coverUrl: cover,
      noWatermarkUrl: videoUrl,
      watermarkUrl: videoUrl,
      referer: referer,
      local: true,
      images: images
          .map((e) => ResultImage(
                url: (e['url'] ?? '') as String,
                thumb: (e['url'] ?? '') as String,
                width: (e['width'] as num?)?.toInt() ?? 0,
                height: (e['height'] as num?)?.toInt() ?? 0,
                // 动图：把带音轨的短视频地址也带上，UI 才能给「存成动图」的选项
                videoUrl: (e['videoUrl'] ?? '') as String,
                durationSec: (e['durationSec'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
      imageCount: images.length,
      sourceUrl: sourceUrl,
      parsedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 这条作品里有没有动图
  bool get hasLivePhotos => images.any((e) => e.isLive);

  bool get isVideo => type == 'video';
  bool get isImages => type == 'images';

  /// 平台色（后端给的是 #RRGGBB，这里解析成 int）
  int get platformColorValue {
    final hex = platformColor.replaceFirst('#', '');
    final v = int.tryParse(hex, radix: 16);
    return v == null ? 0xFF4D6BFE : (0xFF000000 | v);
  }

  /// 平台浅底色（后端给 rgba(r,g,b,a)）
  int get platformSoftValue {
    final m = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)')
        .firstMatch(platformSoft);
    if (m == null) return 0x14107BFE;
    final r = int.parse(m.group(1)!);
    final g = int.parse(m.group(2)!);
    final b = int.parse(m.group(3)!);
    final a = ((double.tryParse(m.group(4) ?? '1') ?? 1) * 255).round().clamp(0, 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// 清晰度展示值。
  ///
  /// 后端对抖音返回的是内部标识（例如 `normal_1080_0`），直接显示很难看。
  /// 这里统一抽成 `1080P` 这种人类可读的形式；识别不出来就原样返回，不猜。
  String get resolutionLabel {
    if (resolution.isEmpty) return '';
    final m = RegExp(r'(\d{3,4})').firstMatch(resolution);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null && n >= 240 && n <= 4320) return '${n}P';
    }
    return resolution;
  }

  factory ParseResult.fromJson(Map<String, dynamic> j) {
    final rawImages = (j['images'] as List?) ?? const [];
    final images = rawImages
        .whereType<Map>()
        .map((e) => ResultImage.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return ParseResult(
      id: (j['id'] ?? '') as String,
      platform: (j['platform'] ?? '') as String,
      platformName: (j['platformName'] ?? '') as String,
      platformShort: (j['platformShort'] ?? '') as String,
      platformColor: (j['platformColor'] ?? '#4D6BFE') as String,
      platformSoft: (j['platformSoft'] ?? 'rgba(77,107,254,0.08)') as String,
      type: (j['type'] ?? 'video') as String,
      title: (j['title'] ?? '') as String,
      author: (j['author'] ?? '') as String,
      authorInitial: (j['authorInitial'] ?? '') as String,
      duration: (j['duration'] ?? '') as String,
      resolution: (j['resolution'] ?? '') as String,
      size: (j['size'] ?? '') as String,
      publishTime: (j['publishTime'] ?? '') as String,
      music: (j['music'] ?? '') as String,
      coverUrl: (j['coverUrl'] ?? '') as String,
      noWatermarkUrl: (j['noWatermarkUrl'] ?? '') as String,
      watermarkUrl: (j['watermarkUrl'] ?? '') as String,
      images: images,
      imageCount: (j['imageCount'] as num?)?.toInt() ?? images.length,
      sourceUrl: (j['sourceUrl'] ?? '') as String,
      referer: (j['referer'] ?? '') as String,
      local: j['local'] == true,
      parsedAt: (j['parsedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      cached: j['cached'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'platform': platform,
        'platformName': platformName,
        'platformShort': platformShort,
        'platformColor': platformColor,
        'platformSoft': platformSoft,
        'type': type,
        'title': title,
        'author': author,
        'authorInitial': authorInitial,
        'duration': duration,
        'resolution': resolution,
        'size': size,
        'publishTime': publishTime,
        'music': music,
        'coverUrl': coverUrl,
        'noWatermarkUrl': noWatermarkUrl,
        'watermarkUrl': watermarkUrl,
        'images': images.map((e) => e.toJson()).toList(),
        'imageCount': imageCount,
        'sourceUrl': sourceUrl,
        'referer': referer,
        'local': local,
        'parsedAt': parsedAt,
        'cached': cached,
      };

  String encode() => jsonEncode(toJson());

  static ParseResult decode(String s) =>
      ParseResult.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
}

/// 解析失败
class ParseFailure implements Exception {
  final String code;
  final String message;
  const ParseFailure(this.code, this.message);

  @override
  String toString() => message;
}
