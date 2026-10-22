/// 动图（Live Photo）的保存方式。
///
/// 【背景】各平台的「动图」本质是 **一张静态封面 + 一段 2~3 秒带音轨的短视频**
/// （抖音叫 `clipType == 5`，小红书是 `livePhoto: true`）。所以「存成什么」
/// 是一个真实的选择题，不是非黑即白：
///
///   · [video] 存那段短视频 —— 保真，有动效也有声音，但相册里归到「视频」
///   · [gif]   转成 GIF —— 相册归到「图片」，能当表情/动图直接发微信；代价是
///             没有声音、体积明显变大（GIF 只有 256 色且无帧间压缩）
///   · [cover] 只存静态封面 —— 最省空间，适合只想留个图的场景
///
/// 【为什么不做动图 WebP】Android 的 Bitmap.compress 不支持编码动图 WebP，
/// 必须内置 libwebp 的 native 库；本项目刚经历过病毒库误报整改，为动图功能
/// 重新引入 .so 不划算。GIF 是唯一零原生依赖、且所有相册和微信都能直接播的格式。
enum MotionMode {
  /// 存带音轨的短视频（默认，保真）
  video,

  /// 转成 GIF 动图
  gif,

  /// 只存静态封面
  cover;

  /// 设置页与保存按钮上的短标签
  String get label => switch (this) {
        MotionMode.video => '短视频',
        MotionMode.gif => 'GIF 动图',
        MotionMode.cover => '静态封面',
      };

  /// 设置页里的一行说明
  String get description => switch (this) {
        MotionMode.video => '存带音轨的短视频，动效和声音都在',
        MotionMode.gif => '图片格式的动图，可直接发微信；无声音、体积较大',
        MotionMode.cover => '只存第一帧，最省空间',
      };

  /// 从持久化的字符串还原。认不出来一律回落到默认值，
  /// 绝不会因为配置文件里写了个奇怪的值就崩掉设置页。
  static MotionMode fromName(String? name) {
    switch (name) {
      case 'gif':
        return MotionMode.gif;
      case 'cover':
        return MotionMode.cover;
      case 'video':
      default:
        return MotionMode.video;
    }
  }

  String get storageName => switch (this) {
        MotionMode.video => 'video',
        MotionMode.gif => 'gif',
        MotionMode.cover => 'cover',
      };
}
