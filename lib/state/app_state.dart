import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/local_store.dart';
import '../data/platforms.dart';
import '../local/registry.dart';
import '../local/types.dart' as lt;
import '../models/parse_result.dart';
import '../services/download_service.dart';

/// 全局应用状态。
///
/// 这个 app 的规模用不上 Provider/Riverpod 那套，用一个 ChangeNotifier 单例 +
/// ListenableBuilder 就够了，少一层依赖少一份出问题的可能。
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  /* ---------------- 基础设施 ---------------- */

  AppSettings settings = const AppSettings();

  List<ParseResult> history = const [];
  AppStat stat = const AppStat();
  int cacheKb = 0;

  bool ready = false;

  /// 当前 tab（0 解析 / 1 记录 / 2 我的）。放进状态里是为了让页面内部
  /// 也能切 tab，例如「记录」页空状态里的「去解析」按钮。
  int tabIndex = 0;
  void requestTab(int i) {
    if (i == tabIndex) return;
    tabIndex = i;
    notifyListeners();
  }

  /* ---------------- 首页状态 ---------------- */

  String rawText = '';
  PlatformMeta? detected;
  bool parsing = false;

  /* ---------------- 动图偏好 ---------------- */

  /// 动图存成视频还是静态图（跟设置里的开关同步）
  bool get saveLiveAsVideo => settings.saveLiveAsVideo;

  void setSaveLiveAsVideo(bool v) {
    updateSettings(settings.copyWith(saveLiveAsVideo: v));
  }

  /* ---------------- 图片多选 ---------------- */

  /// 图文作品里被勾选要下载的下标。解析成功后默认全选。
  final Set<int> pickedImages = <int>{};

  int get pickedCount => pickedImages.length;

  bool get allPicked =>
      result != null &&
      result!.images.isNotEmpty &&
      pickedImages.length == result!.images.length;

  bool isPicked(int i) => pickedImages.contains(i);

  /// 解析出新结果时重置为「全选」——
  /// 大多数人的诉求还是「全都要」，让他自己一张张勾反而费事。
  void _resetPicked() {
    pickedImages.clear();
    final n = result?.images.length ?? 0;
    for (var i = 0; i < n; i++) {
      pickedImages.add(i);
    }
  }

  void togglePick(int i) {
    if (pickedImages.contains(i)) {
      pickedImages.remove(i);
    } else {
      pickedImages.add(i);
    }
    notifyListeners();
  }

  void pickAll() {
    final n = result?.images.length ?? 0;
    pickedImages
      ..clear()
      ..addAll(List<int>.generate(n, (i) => i));
    notifyListeners();
  }

  void pickNone() {
    pickedImages.clear();
    notifyListeners();
  }
  int progress = 0;
  String progressLabel = '';
  String? error;
  ParseResult? result;

  bool downloading = false;
  double downloadProgress = 0;
  String downloadLabel = '';

  /* ---------------- 初始化 ---------------- */

  Future<void> bootstrap() async {
    settings = await LocalStore.instance.getSettings();
    history = await LocalStore.instance.getHistory();
    stat = await LocalStore.instance.getStat();
    cacheKb = await LocalStore.instance.cacheSizeKb();
    ready = true;
    notifyListeners();
  }

  Future<void> refreshDerived() async {
    history = await LocalStore.instance.getHistory();
    stat = await LocalStore.instance.getStat();
    cacheKb = await LocalStore.instance.cacheSizeKb();
    notifyListeners();
  }

  /* ---------------- 输入 ---------------- */

  void setText(String text) {
    rawText = text;
    detected = extractUrl(text) != null ? detectPlatform(text) : null;
    error = null;
    if (result != null && result!.sourceUrl != extractUrl(text)) {
      result = null;
    }
    notifyListeners();
  }

  void clearInput() {
    rawText = '';
    detected = null;
    error = null;
    result = null;
    progress = 0;
    progressLabel = '';
    notifyListeners();
  }

  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) {
      throw const ParseFailure('EMPTY_CLIP', '剪贴板是空的');
    }
    if (extractUrl(text) == null) {
      throw const ParseFailure('NO_LINK', '剪贴板里没找到链接');
    }
    setText(text);
  }

  /* ---------------- 进 App 自动识别剪贴板 ---------------- */

  /// 上一次已经自动处理过的剪贴板内容。
  /// 用来避免「切 tab / 前后台来回」时对同一条链接反复触发解析。
  String? _lastAutoHandled;

  /// 上一次由自动粘贴写进输入框的内容。
  /// 用来区分输入框里的字是「用户手打的」还是「我们自动填的」——前者不能被覆盖。
  String? _autoFilledText;

  /// 进 App 时调用（冷启动、以及从后台切回来）。
  ///
  /// 四条守卫，缺一条都会让用户觉得这功能很烦：
  ///   1. 剪贴板里得能解析出链接，**而且属于支持的三个平台之一**，否则静默不作声
  ///   2. 同一条内容只处理一次（切 tab、切前后台不该反复解析）
  ///   3. 用户已经在输入框里手打过东西，就不覆盖他的输入
  ///   4. 当前展示的结果就是这条链接，不重复解析
  ///
  /// @returns 是否真的触发了自动解析
  Future<bool> tryAutoParseFromClipboard() async {
    if (!settings.autoPaste) return false;
    if (parsing || downloading) return false;

    String text = '';
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = (data?.text ?? '').trim();
    } catch (_) {
      return false;    // 某些系统/权限下读剪贴板会抛异常，静默即可
    }
    if (text.isEmpty) return false;

    // 守卫 2：同一条只处理一次
    if (text == _lastAutoHandled) return false;

    final url = extractUrl(text);
    if (url == null) return false;

    // 守卫 1：不是支持的平台就别打扰用户
    if (detectPlatform(text) == null) return false;

    // 守卫 3：用户手打过内容，别覆盖
    final typedByUser = rawText.trim();
    if (typedByUser.isNotEmpty && typedByUser != _autoFilledText) return false;

    // 守卫 4：已经在展示这条的结果了
    if (result != null && result!.sourceUrl == url) {
      _lastAutoHandled = text;
      return false;
    }

    _lastAutoHandled = text;
    _autoFilledText = text;
    setText(text);
    await parse();
    return true;
  }

  /// 用户手动清空/改动输入框时调用，让自动填充的痕迹失效
  void forgetAutoFill() {
    _autoFilledText = null;
  }

  /* ---------------- 解析 ---------------- */

  Timer? _progressTimer;

  Future<void> parse() async {
    if (parsing) return;

    final text = rawText.trim();
    if (text.isEmpty) {
      error = '请先粘贴分享链接';
      notifyListeners();
      return;
    }
    if (extractUrl(text) == null) {
      error = '没找到链接，请粘贴完整的分享文案';
      notifyListeners();
      return;
    }
    if (detectPlatform(text) == null) {
      // 从 kPlatforms 动态生成，不写死 ——
      // 写死的话以后加平台又忘了改这里，用户会看到一份过期的「支持列表」。
      final names = kPlatforms.map((p) => p.name).join(' / ');
      error = '暂不支持这个平台。目前支持：$names';
      notifyListeners();
      return;
    }

    parsing = true;
    progress = 0;
    progressLabel = '准备中';
    error = null;
    result = null;
    notifyListeners();

    // 后端不推流式进度，这里用「阶段式推进」给用户反馈：
    // 真实完成前最多走到 90%，拿到结果才跳到 100%，不假装知道真实百分比。
    _startFakeProgress();

    try {
      // 只有一条路：手机本地解析。
      // 原来还有个「服务器模式」和自动回退，其实从来没真正做过服务端解析，
      // 摆着只会让用户以为链接会被上传 —— 已整体移除。
      final r = await _parseLocally(text);

      _stopFakeProgress();
      progress = 100;
      progressLabel = '解析完成';
      parsing = false;
      result = r;
      _resetPicked(); // 新结果一律默认全选
      notifyListeners();

      await LocalStore.instance.addHistory(r);
      await LocalStore.instance.bumpStat();
      await refreshDerived();

      HapticFeedback.lightImpact();
    } catch (e) {
      _stopFakeProgress();
      parsing = false;
      progress = 0;
      progressLabel = '';
      error = e is ParseFailure
          ? e.message
          : (e is lt.LocalParseError ? e.message : '解析失败，请稍后重试');
      notifyListeners();
    }
  }

  void _startFakeProgress() {
    _progressTimer?.cancel();
    // 文案要跟着解析方式走 —— 本地解析却写「等待服务端返回」会让人以为
    // 链接被上传了，那正是用户最在意的事。
    final steps = <List<Object>>[
      [18, '识别分享链接'],
      [42, '在手机里打开作品页'],
      [66, '提取原片地址'],
      [86, '生成下载链接'],
    ];
    var i = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 450), (t) {
      if (i < steps.length) {
        progress = steps[i][0] as int;
        progressLabel = steps[i][1] as String;
        notifyListeners();
        i++;
      } else {
        // 到 90% 就停住等真实结果，不再往上爬
        progress = 90;
        progressLabel = '正在解析，请稍候';
        notifyListeners();
        t.cancel();
      }
    });
  }

  void _stopFakeProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /* ---------------- 本地解析（不经过服务器） ---------------- */

  /// 全程在手机里完成：内置 WebView 跑平台自己的 JS，我们拦截响应。
  /// 不需要服务器，也不需要任何 Cookie 维护。
  Future<ParseResult> _parseLocally(String text) async {
    final url = extractUrl(text);
    if (url == null) throw const lt.LocalParseError('没找到链接，请粘贴完整的分享文案');

    final platform = LocalRegistry.detect(url);
    if (platform == null) {
      throw lt.LocalParseError(
        '暂不支持这个链接。\n'
        '目前已支持：${LocalRegistry.supportedNames.join(' / ')}',
      );
    }

    final r = await platform.parse(url);

    return ParseResult.fromLocal(
      r.platform,
      r.platformName,
      r.type,
      r.title,
      author: r.author,
      cover: r.cover,
      durationSec: r.durationSec,
      resolution: r.resolution,
      publishTime: r.publishTime,
      music: r.music,
      videoUrl: r.videoUrl,
      referer: r.referer,
      images: r.images.map((e) => e.toJson()).toList(),
      sourceUrl: r.sourceUrl,
    );
  }

  String get activeMediaUrl {
    final r = result;
    if (r == null) return '';
    // 只提供原片（无水印）。不再做「带水印版本」的二选一 ——
    // 用户装这个 App 就是为了拿干净原片，给他一个水印选项等于白问。
    return r.noWatermarkUrl;
  }

  /* ---------------- 下载 / 保存 ---------------- */

  Future<DownloadOutcome> saveCurrent() async {
    final r = result;
    if (r == null) return const DownloadOutcome(saved: false, message: '没有可保存的内容');

    if (r.isImages) return saveAllImages();

    downloading = true;
    downloadProgress = 0;
    downloadLabel = '准备下载';
    notifyListeners();

    final url = activeMediaUrl;
    final outcome = await DownloadService.instance.fetchAndSave(
      proxyUrl: url,
      isVideo: true,
      referer: r.referer,
      fileHint: r.title,
      onProgress: (p) {
        downloadProgress = p;
        downloadLabel = '下载中 ${(p * 100).toStringAsFixed(0)}%';
        notifyListeners();
      },
    );

    downloading = false;
    downloadProgress = 0;
    downloadLabel = '';
    notifyListeners();
    return outcome;
  }

  /// 只保存指定的一张 —— 预览大图时「保存这张」用。
  ///
  /// 和批量保存分开是有必要的：用户在预览里看中了某一张，
  /// 不该被迫把整组 46 张都存下来。
  Future<DownloadOutcome> saveSingleImage(int index) async {
    final r = result;
    if (r == null || index < 0 || index >= r.images.length) {
      return const DownloadOutcome(saved: false, message: '这张图不存在');
    }

    downloading = true;
    downloadProgress = 0;
    downloadLabel = '保存中';
    notifyListeners();

    final img = r.images[index];
    // 动图按用户偏好走：存带音轨的短视频，或只存静态封面
    final asVideo = img.isLive && settings.saveLiveAsVideo;

    final outcome = await DownloadService.instance.fetchAndSave(
      proxyUrl: asVideo ? img.videoUrl : img.url,
      isVideo: asVideo,
      referer: r.referer,
      // 用原图序号，和批量保存的命名保持一致
      fileHint: '${r.title}_${index + 1}',
      onProgress: (p) {
        downloadProgress = p;
        notifyListeners();
      },
    );

    downloading = false;
    downloadProgress = 0;
    downloadLabel = '';
    notifyListeners();
    return outcome;
  }

  /// 图文作品逐张保存 —— **只存勾选的那些**。
  ///
  /// 【为什么改成并发】原来是一张接一张串行下，46 张图每张 1–2MB，
  /// 用户得盯着进度条等好几分钟。改成**最多 3 张同时下**：
  /// 网络吞吐能跑满，相册写入（MediaStore）实测扛得住 3 并发。
  ///
  /// 【为什么不更高】并发再往上，平台 CDN 会开始限速，反而更慢；
  /// 而且保存顺序会乱。3 是实测下来最稳的点。
  Future<DownloadOutcome> saveAllImages() async {
    final r = result;
    if (r == null || r.images.isEmpty) {
      return const DownloadOutcome(saved: false, message: '没有可保存的图片');
    }

    // 按原顺序保存，保证「作品里的第几张」和相册里的编号对得上
    final targets = pickedImages.toList()..sort();
    if (targets.isEmpty) {
      return const DownloadOutcome(saved: false, message: '还没选要保存的图片');
    }

    downloading = true;
    downloadProgress = 0;
    downloadLabel = '保存中 0/${targets.length}';
    notifyListeners();

    const maxParallel = 3;
    final total = targets.length;

    // 每张的进度（0–1）。并行时不能再用「第 n 张」算总进度，
    // 否则进度条会来回跳。
    final each = <int, double>{};
    final outcomes = List<DownloadOutcome?>.filled(total, null);

    var nextSlot = 0;
    var finished = 0;

    Future<void> worker() async {
      while (true) {
        final slot = nextSlot++;
        if (slot >= total) return;

        final i = targets[slot] < 0 || targets[slot] >= r.images.length
            ? -1
            : targets[slot];
        if (i < 0) {
          outcomes[slot] =
              const DownloadOutcome(saved: false, message: '这张图不存在');
          finished++;
          continue;
        }

        final img = r.images[i];
        // 动图按用户偏好走：存带音轨的短视频，或只存静态封面
        final asVideo = img.isLive && settings.saveLiveAsVideo;

        outcomes[slot] = await DownloadService.instance.fetchAndSave(
          proxyUrl: asVideo ? img.videoUrl : img.url,
          isVideo: asVideo,
          referer: r.referer,
          // 编号用**原图序号**而不是选中序号 —— 否则保存第 3、7 张时会变成 _1、_2，
          // 回头根本对不上是作品里的哪张。
          fileHint: '${r.title}_${i + 1}',
          onProgress: (p) {
            each[slot] = p;
            final sum = each.values.fold<double>(0, (a, b) => a + b);
            downloadProgress = sum / total;
            notifyListeners();
          },
        );

        each[slot] = 1;
        finished++;
        downloadLabel = '保存中 $finished/$total';
        downloadProgress = finished / total;
        notifyListeners();
      }
    }

    await Future.wait(
      List.generate(maxParallel < total ? maxParallel : total, (_) => worker()),
    );

    var ok = 0;
    var fail = 0;
    var lastMsg = '';
    for (final o in outcomes) {
      if (o == null) continue;
      if (o.saved) {
        ok++;
      } else {
        fail++;
        if (o.message.isNotEmpty) lastMsg = o.message;
      }
    }

    downloading = false;
    downloadProgress = 0;
    downloadLabel = '';
    notifyListeners();

    if (fail == 0) {
      return DownloadOutcome(saved: true, message: '已保存 $ok 张');
    }
    if (ok == 0) {
      return DownloadOutcome(saved: false, message: lastMsg.isEmpty ? '保存失败' : lastMsg);
    }
    return DownloadOutcome(saved: true, message: '成功 $ok 张，失败 $fail 张');
  }

  /* ---------------- 复制 ---------------- */

  Future<void> copyTitle() async {
    final r = result;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r.title));
  }

  Future<void> copyMediaUrl() async {
    final url = activeMediaUrl;
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
  }

  /* ---------------- 设置 ---------------- */

  Future<void> updateSettings(AppSettings next) async {
    settings = await LocalStore.instance.saveSettings(next);
    notifyListeners();
  }

  Future<void> clearLocalData() async {
    await LocalStore.instance.clearHistory();
    await LocalStore.instance.resetStat();
    await refreshDerived();
  }

  /// 服务健康状态（「我的」页展示）
}
