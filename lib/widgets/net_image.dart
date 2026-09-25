import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 带 `Referer` 的网络图片。
///
/// 【为什么必须带 Referer —— 这是一个查了很久的 bug】
///
/// 各平台的图片 CDN 都有**防盗链**：请求没带 `Referer` 直接返回 403。
/// 而 `Image.network` 拿到 403 只会**安静地走 errorBuilder** ——
/// 不报错、不打日志、不抛异常，表现就是「解析明明成功了，封面却是空白的」。
/// 用户以为是解析失败，其实是图下不来。
///
/// 用 `dio` 下载时我们一直是带 Referer 的（所以保存到相册没问题），
/// 但界面上的预览图用的是 `Image.network`，漏了这一步 —— 于是「能存下来却看不见」。
///
/// 所以界面上一律用这个组件，不要再直接用 `Image.network`。
/// 按「要显示多宽」算出该解码多少像素。
///
/// 有些地方（比如结果卡里的各个 build 方法）拿不到 BuildContext，
/// 用它就不必为了一个像素密度把 context 一层层传下去。
///
/// 上限 720：再大对列表缩略图没有意义，只会白占内存。
int imageCacheWidth(double logicalWidth) {
  final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  final px = (logicalWidth * dpr).round();
  return px.clamp(64, 720);
}

class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.referer = '',
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.placeholder,
    this.error,
  });

  final String url;

  /// 防盗链要的来路。传作品所属平台的首页即可。
  final String referer;

  final BoxFit fit;
  final double? width;
  final double? height;

  /// 按这个像素宽度解码。
  ///
  /// 【这是最划算的一处优化】抖音的原图宽 1440px，而列表里的缩略图只有
  /// 150 逻辑像素宽。不设这个参数，Flutter 会把 1440px 的位图整个解到内存里
  /// 再缩到 150 —— 一张就占约 8MB 显存，46 张的图文作品滑动时会疯狂 GC，
  /// 既卡又费电。
  ///
  /// 传 `150 * devicePixelRatio` 之后，解码器直接按目标尺寸解 ——
  /// 内存降到约 1/9，滑动明显跟手。
  final int? cacheWidth;

  /// 加载中显示什么（默认什么都不显示，避免闪烁）
  final Widget? placeholder;

  /// 失败显示什么
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return error ?? const SizedBox.shrink();

    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      // 关键 1：带上 Referer，否则平台 CDN 一律 403
      headers: referer.isNotEmpty ? {'Referer': referer} : null,
      // 关键 2：按显示尺寸解码，别把 1440px 原图整个解到内存
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.low,
      loadingBuilder: (_, child, p) =>
          p == null ? child : (placeholder ?? const SizedBox.shrink()),
      errorBuilder: (_, _, _) =>
          error ??
          const Center(
            child: Icon(Icons.image_not_supported_outlined,
                size: 20, color: AppColors.muted),
          ),
    );
  }
}
