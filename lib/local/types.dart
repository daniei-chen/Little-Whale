/// 本地解析的公共类型。
///
/// 单独一个文件是为了避免 `registry.dart` 和各个平台实现互相 import 造成循环。
library;

/// 一张图（也可能是"动图"）
class LocalImage {
  final String url;
  final int width;
  final int height;

  /// **动图**对应的短视频地址。非动图时为空字符串。
  ///
  /// 抖音的图文作品里，动图（Live Photo）每张都挂着一个**带音轨的短视频** ——
  /// 存成静态图就把动效和声音丢了。有这个字段，用户就能选「存成动图」。
  final String videoUrl;

  /// 动图视频的时长（秒），非动图为 0
  final int durationSec;

  const LocalImage({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.videoUrl = '',
    this.durationSec = 0,
  });

  /// 是不是动图
  bool get isLive => videoUrl.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'url': url,
        'width': width,
        'height': height,
        if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
        if (durationSec > 0) 'durationSec': durationSec,
      };
}

/// 一次本地解析的结果
///
/// 与服务器模式的根本区别：这里拿到的是**平台原始直链**，不是带签名的代理地址。
/// 所以下载时必须自己带 Referer —— 好在 Android 可以自由设置请求头，
/// 这正是 App 能甩开服务器、省掉全部中转流量的原因。
class LocalResult {
  final String platform;
  final String platformName;
  final String type; // video | images
  final String title;
  final String author;
  final String cover;
  final int durationSec;
  final String resolution;
  final String size;
  final String publishTime;
  final String music;

  /// type = video 时的原始直链
  final String videoUrl;

  /// 下载时必须带的 Referer（各平台 CDN 的防盗链就靠它）
  final String referer;

  /// type = images 时的图片列表
  final List<LocalImage> images;

  final String sourceUrl;

  const LocalResult({
    required this.platform,
    required this.platformName,
    required this.type,
    required this.title,
    this.author = '',
    this.cover = '',
    this.durationSec = 0,
    this.resolution = '',
    this.size = '',
    this.publishTime = '',
    this.music = '',
    this.videoUrl = '',
    this.referer = '',
    this.images = const [],
    this.sourceUrl = '',
  });

  bool get isImages => type == 'images';
  int get imageCount => images.length;

  /// 这条作品里有没有动图
  bool get hasLivePhotos => images.any((e) => e.isLive);
}

/// 一个平台的本地解析能力
abstract class LocalPlatform {
  /// 内部标识，与服务器模式保持一致
  String get key;

  /// 展示名
  String get name;

  /// 命中这些域名就归它管
  List<String> get hosts;

  /// 下载该平台媒体时要带的 Referer
  String get referer;

  bool matches(String url) {
    final u = url.toLowerCase();
    for (final h in hosts) {
      if (u.contains(h)) return true;
    }
    return false;
  }

  Future<LocalResult> parse(String url);
}

/// 本地解析失败
class LocalParseError implements Exception {
  final String message;
  const LocalParseError(this.message);
  @override
  String toString() => message;
}
