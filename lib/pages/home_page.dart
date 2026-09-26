import 'package:flutter/material.dart';

import '../data/platforms.dart';
import '../models/parse_result.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/image_viewer.dart';
import '../widgets/net_image.dart';
import '../widgets/primitives.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    final s = AppState.instance;
    _controller.text = s.rawText;
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
    s.addListener(_onState);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onState);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    if (_controller.text != AppState.instance.rawText) {
      _controller.text = AppState.instance.rawText;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1800),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      ));
  }

  Future<void> _onPaste() async {
    try {
      await AppState.instance.pasteFromClipboard();
      _toast('已粘贴');
    } on ParseFailure catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('读取剪贴板失败');
    }
  }

  Future<void> _onSave() async {
    final s = AppState.instance;
    final r = s.result;
    if (r == null) return;

    final outcome = await s.saveCurrent();
    if (!mounted) return;
    if (outcome.saved) {
      _toast(outcome.message.isNotEmpty ? outcome.message : '已保存到相册');
    } else {
      _toast(outcome.message.isNotEmpty ? outcome.message : '保存失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final s = AppState.instance;
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  const SizedBox(height: 18),
                  _buildBrandCard(s),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      // 必须 stretch：否则纯文字内容的卡片（如《使用须知》）
                      // 会缩成内容宽度、在页面里居中，和上下卡片对不齐。
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildParseCard(s),
                        if (s.error != null) ...[
                          const SizedBox(height: 10),
                          _ErrorBar(message: s.error!),
                        ],
                        if (s.result != null) ...[
                          const SizedBox(height: 10),
                          _ResultCard(
                            result: s.result!,
                            onReplay: s.parse,
                            onSave: _onSave,
                            onCopyTitle: () async {
                              await s.copyTitle();
                              _toast('标题已复制');
                            },
                            onCopyLink: () async {
                              await s.copyMediaUrl();
                              _toast('直链已复制');
                            },
                            onImageTap: _openImagePreview,
                          ),
                        ],
                        const SizedBox(height: 17),
                        _buildGuide(),
                        const SizedBox(height: 17),
                        const _Notice(),
                      ],
                    ),
                  ),
                ],
              ),
              if (s.downloading) _DownloadOverlay(label: s.downloadLabel, progress: s.downloadProgress),
            ],
          ),
        );
      },
    );
  }

  /* ------------------------------------------------------------------ */
  /* 图片预览（全屏大图 + 保存这一张）                                    */
  /* ------------------------------------------------------------------ */

  Future<void> _openImagePreview(int start) async {
    final r = AppState.instance.result;
    if (r == null || r.images.isEmpty) return;

    final saved = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => ImageViewer(result: r, initialIndex: start),
    );
    if (saved == true && mounted) _toast('已保存到相册');
  }

  /* ------------------------------------------------------------------ */
  /* 品牌卡                                                              */
  /* ------------------------------------------------------------------ */

  Widget _buildBrandCard(AppState s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SoftCard(
        radius: 20,
        padding: const EdgeInsets.all(18),
        borderColor: AppColors.brandLine,
        glow: true,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.55, 1.0],
          colors: [Color(0xFFF2F6FF), Color(0xFFFFFFFF), Color(0xFFEEF3FF)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 品牌 Logo：就用应用图标那只鲸鱼
                Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE4EAF6)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.blue.withValues(alpha: 0.16),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                              child: Text('小鲸鱼', style: AppText.brandTitle)),
                          // 标识放在标题这一行、右对齐 ——
                          // 挤在平台标签那排会显得杂乱，也没有呼吸感
                          const _LocalBadge(),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text('粘贴链接，保存无水印原片',
                          style: AppText.brandDesc),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 【为什么只显示 6 个】原来把 18 个平台全铺出来，
            // 品牌卡里挤了三四行小圆点，看着很碎、也不好看。
            // 主页只需要传达「主流平台都支持」——
            // 完整的列表放到「我的 → 支持平台」里，想看的人去看。
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: kPlatforms
                  .take(6)
                  .map((p) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5.5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE8EBF2)),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x0A1F2A44),
                                blurRadius: 4,
                                offset: Offset(0, 1)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Dot(color: p.color, size: 6),
                            const SizedBox(width: 5),
                            Text(p.name, style: AppText.pill),
                          ],
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            // 完整列表放到「我的」页，这里只给一句提示 —— 别让品牌卡太挤
            Text(
              '另有 ${kPlatforms.length - 6} 个平台支持，见「我的 → 支持平台」',
              style: AppText.pill.copyWith(
                  fontSize: 10.5, color: const Color(0xFFA8AEB8)),
            ),
          ],
        ),
      ),
    );
  }

  /* ------------------------------------------------------------------ */
  /* 解析卡                                                              */
  /* ------------------------------------------------------------------ */

  Widget _buildParseCard(AppState s) {
    return SoftCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Dot(color: AppColors.blue, size: 8, glow: 4),
              const SizedBox(width: 8),
              Text('分享链接', style: AppText.cardTitle),
              const Spacer(),
              TextPill(label: '一键粘贴', onTap: _onPaste),
              if (s.rawText.isNotEmpty) ...[
                const SizedBox(width: 6),
                TextPill(
                  label: '清空',
                  onTap: s.clearInput,
                  bg: const Color(0xFFF2F3F5),
                  fg: AppColors.text2,
                ),
              ],
            ],
          ),
          const SizedBox(height: 11),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
            decoration: BoxDecoration(
              color: _focused ? Colors.white : const Color(0xFFFAFBFC),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focused ? const Color(0xFFB9C7FF) : const Color(0xFFDFE4EF),
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.blue.withValues(alpha: 0.07),
                        blurRadius: 0,
                        spreadRadius: 3,
                      )
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    maxLines: null,
                    minLines: 2,
                    maxLength: 1000,
                    style: AppText.body,
                    cursorColor: AppColors.blue,
                    cursorWidth: 1.6,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                      hintText: '粘贴分享文案或完整链接',
                      hintStyle: AppText.hint,
                    ),
                    onChanged: (v) {
                      // 用户手打了，就别再被自动粘贴覆盖
                      s.forgetAutoFill();
                      s.setText(v);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('支持分享文案或完整链接', style: AppText.meta),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE5E8EE)),
                      ),
                      child: Text('LINK', style: AppText.meta.copyWith(fontSize: 10, height: 1.1)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (s.detected != null) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8FA)),
              ),
              child: Row(
                children: [
                  const Dot(color: AppColors.blue, size: 6),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '已识别到 ${s.detected!.name} 链接',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF6673A7), height: 1.2),
                    ),
                  ),
                  const Text('✓',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.blue, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 11),
          PrimaryButton(
            label: s.parsing ? '解析中…' : '开始解析',
            busy: s.parsing,
            onTap: s.parse,
          ),
          if (s.parsing) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: s.progress / 100),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFEDEFF4),
                  valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(s.progressLabel, style: AppText.meta),
                const Spacer(),
                Text('${s.progress}%',
                    style: AppText.meta.copyWith(
                        color: AppColors.blue, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: Text('解析仅用于个人学习与内容备份',
                style: AppText.meta.copyWith(color: const Color(0xFFA5ABB4))),
          ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------------ */
  /* 三步搞定 + 使用须知                                                  */
  /* ------------------------------------------------------------------ */

  Widget _buildGuide() {
    const steps = [
      ['01', '复制链接', '在 App 里点分享，复制作品链接'],
      ['02', '粘贴解析', '回到这里，粘贴后点开始解析'],
      ['03', '保存相册', '选原片版本，一键存进相册'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('三步搞定', style: AppText.sectionTitle),
            const Spacer(),
            Text('简单 · 快速 · 本地保存', style: AppText.meta.copyWith(color: const Color(0xFF9CA2AB))),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: steps
              .map((st) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: st[0] == '03' ? 0 : 7),
                      child: SoftCard(
                        radius: 13,
                        padding: const EdgeInsets.fromLTRB(9, 11, 9, 11),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(st[0],
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF8FA0F4),
                                  letterSpacing: 0.4,
                                  height: 1.1,
                                )),
                            const SizedBox(height: 7),
                            Text(st[1],
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                    height: 1.2)),
                            const SizedBox(height: 5),
                            Text(st[2],
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF9AA1AA),
                                    height: 1.45)),
                          ],
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

/* ==================================================================== */
/* 服务状态小胶囊                                                        */
/* ==================================================================== */

/// 「本地解析」标识。
///
/// 【这里以前是什么】原来是个服务连通性探测，会显示「服务未连接」。
/// 现在解析全在手机里跑，根本没有服务可连 —— 探测那套整个删掉了。
/// 留一个绿点说明「解析不经过网络」，用户一眼就懂。
class _LocalBadge extends StatelessWidget {
  const _LocalBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Dot(color: AppColors.green, size: 5),
        const SizedBox(width: 4),
        Text('解析不上网',
            style: AppText.pill
                .copyWith(fontSize: 10.5, color: const Color(0xFF9AA1AB))),
      ],
    );
  }
}

/* ==================================================================== */
/* 错误条                                                                */
/* ==================================================================== */

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.redSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5DDE0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
            child: const Center(
              child: Text('!',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFC04A56), height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/* ==================================================================== */
/* 结果卡                                                                */
/* ==================================================================== */

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onReplay,
    required this.onSave,
    required this.onCopyTitle,
    required this.onCopyLink,
    required this.onImageTap,
  });

  final ParseResult result;
  final VoidCallback onReplay;
  final VoidCallback onSave;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyLink;
  final ValueChanged<int> onImageTap;

  @override
  Widget build(BuildContext context) {
    final platformColor = Color(result.platformColorValue);
    final platformSoft = Color(result.platformSoftValue);

    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlatformBadge(name: result.platformName, bg: platformSoft, fg: platformColor),
              const SizedBox(width: 7),
              const Dot(color: AppColors.green, size: 6),
              const SizedBox(width: 5),
              const Text('解析成功',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w600, height: 1.1)),
              const Spacer(),
              Pressable(
                onTap: onReplay,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('重新解析',
                      style: AppText.meta.copyWith(color: const Color(0xFF7180C8), fontSize: 11.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (result.isVideo) _buildVideo(platformColor),
          if (result.isImages) _buildImages(),
          const SizedBox(height: 12),
          Text(result.title, style: AppText.resultTitle),
          const SizedBox(height: 9),
          Row(
            children: [
              if (result.authorInitial.isNotEmpty) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(color: Color(0xFFEEF2FF), shape: BoxShape.circle),
                  child: Center(
                    child: Text(result.authorInitial,
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.blue,
                            fontWeight: FontWeight.w700,
                            height: 1.1)),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(result.author,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7F8792), height: 1.2)),
              ),
              const SizedBox(width: 8),
              Text(
                [result.size, result.publishTime].where((e) => e.isNotEmpty).join(' · '),
                style: AppText.meta.copyWith(color: const Color(0xFFA0A6AF), fontSize: 10.5),
              ),
            ],
          ),
          if (result.music.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(result.music,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.meta.copyWith(fontSize: 10.5)),
          ],
          if (result.isVideo) ...[
            const SizedBox(height: 11),
            // 只给原片。以前这里有个「无水印 / 带水印」的二选一开关 ——
            // 用户来这就是为了拿干净原片，再让他手动选一次纯属多余。
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFDCE3FB)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcons.check(AppColors.blue, 12),
                  const SizedBox(width: 5),
                  const Text('原片 · 无水印',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.blue,
                          height: 1.2)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          PrimaryButton(
            label: result.isImages
                ? (AppState.instance.pickedCount == 0
                    ? '请先勾选要保存的图片'
                    : '保存选中的 ${AppState.instance.pickedCount} 张图')
                : '保存到相册',
            showArrow: false,
            height: 44,
            // 一张都没勾时按钮不可点，避免点了没反应还以为是坏了
            onTap: result.isImages && AppState.instance.pickedCount == 0
                ? null
                : onSave,
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(child: _subButton('复制标题', onCopyTitle)),
              if (result.isVideo) ...[
                const SizedBox(width: 7),
                Expanded(child: _subButton('复制直链', onCopyLink)),
              ],
            ],
          ),
          if (result.cached) ...[
            const SizedBox(height: 9),
            const Center(
              child: Text('这条结果来自服务端缓存',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFFA5ABB4))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subButton(String label, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E7F8)),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5269CF),
                  height: 1.1)),
        ),
      ),
    );
  }

  /* ---------------- 视频封面 ---------------- */

  Widget _buildVideo(Color platformColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 浅蓝渐变占位（与设计稿一致），有封面时叠在上面
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [0.0, 0.48, 1.0],
                  colors: [Color(0xFFDCE7FF), Color(0xFFC8D7FB), Color(0xFFB7C8EF)],
                ),
              ),
            ),
            if (result.coverUrl.isNotEmpty)
                  NetImage(
                    result.coverUrl,
                    referer: result.referer,
                    cacheWidth:
                        imageCacheWidth(420),
                    placeholder: const SizedBox.shrink(),
                    error: const SizedBox.shrink(),
                  ),
            // 设计稿里那层很淡的斜向高光
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [0.0, 0.38, 1.0],
                  colors: [Color(0x29FFFFFF), Color(0x00FFFFFF), Color(0x14526AA4)],
                ),
              ),
            ),
            // 播放键：白底圆 + 蓝色三角
            Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF394E7D).withValues(alpha: 0.14),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: CustomPaint(painter: _PlayTrianglePainter(AppColors.blue)),
              ),
            ),
            if (result.resolution.isNotEmpty)
              Positioned(
                left: 10,
                top: 10,
                child: _videoChip(result.resolutionLabel),
              ),
            if (result.duration.isNotEmpty)
              Positioned(
                right: 10,
                bottom: 10,
                child: _videoChip(result.duration),
              ),
          ],
        ),
      ),
    );
  }

  Widget _videoChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x941C222E),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 10.5, color: Colors.white, height: 1.1)),
      );

  /* ---------------- 图文列表 ---------------- */

  Widget _buildImages() {
    final s = AppState.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- 选择状态 + 全选/全不选 ----
        Row(
          children: [
            Text('已选 ${s.pickedCount} / ${result.imageCount} 张',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                    height: 1.2)),
            const Spacer(),
            Pressable(
              onTap: () => s.allPicked ? s.pickNone() : s.pickAll(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Row(
                  children: [
                    Text(s.allPicked ? '取消全选' : '全选',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.blue,
                            height: 1.2)),
                    const SizedBox(width: 3),
                    AppIcons.check(AppColors.blue, 12),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: result.images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final img = result.images[i];
              final on = s.isPicked(i);
              return Pressable(
                onTap: () => onImageTap(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 150,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: AppColors.surfaceSoft),
                        // 没勾选的压暗一点，一眼能看出哪些不下载
                        ColorFiltered(
                          colorFilter: on
                              ? const ColorFilter.mode(
                                  Colors.transparent, BlendMode.dst)
                              : const ColorFilter.mode(
                                  Color(0x66FFFFFF), BlendMode.srcOver),
                          child: NetImage(
                            img.thumb?.isNotEmpty == true ? img.thumb! : img.url,
                            referer: result.referer,
                            // 缩略图只显示 150 逻辑像素宽，按这个尺寸解码 ——
                            // 别把 1440px 的原图整个解进内存（46 张时差别很明显）
                            cacheWidth:
                                imageCacheWidth(150),
                            placeholder: const SizedBox.shrink(),
                            error: const Center(
                              child: Icon(Icons.broken_image_outlined,
                                  color: AppColors.muted, size: 22),
                            ),
                          ),
                        ),
                        // 动图标识：不标的话用户不知道这张存下来会动
                        if (img.isLive)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF5B7CFF), Color(0xFF8A5BFF)],
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x335B7CFF),
                                      blurRadius: 6,
                                      offset: Offset(0, 2)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_arrow_rounded,
                                      size: 11, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Text(
                                    img.durationSec > 0
                                        ? '动图 ${img.durationSec}s'
                                        : '动图',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        height: 1.1,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // 勾选框：整块缩略图负责预览，这个小方块负责勾选，
                        // 两者分开，避免「想预览却勾上了」的误操作
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Pressable(
                            onTap: () => s.togglePick(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: on ? AppColors.blue : const Color(0x8A1C222E),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                    color: on ? AppColors.blue : Colors.white,
                                    width: 1.6),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1)),
                                ],
                              ),
                              child: on
                                  ? const Icon(Icons.check,
                                      size: 14, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                        // 序号
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x941C222E),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white, height: 1.1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text('左右滑动看全部 · 点右上角勾选要保存的',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF9AA1AA))),
        ),
      ],
    );
  }
}

class _PlayTrianglePainter extends CustomPainter {
  _PlayTrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.40, h * 0.30)
      ..lineTo(w * 0.72, h * 0.50)
      ..lineTo(w * 0.40, h * 0.70)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _PlayTrianglePainter old) => old.color != color;
}

/* ==================================================================== */
/* 使用须知                                                              */
/* ==================================================================== */

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('使用须知',
              style: AppText.cardTitle.copyWith(fontSize: 12.5, color: AppColors.text2)),
          const SizedBox(height: 6),
          ...const [
            '本工具仅用于个人学习与内容备份',
            '请勿用于商业传播或二次分发他人作品',
            '所下载内容的版权均归原作者所有',
          ].map((t) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(t,
                    style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.8)),
              )),
        ],
      ),
    );
  }
}

/* ==================================================================== */
/* 下载进度浮层                                                          */
/* ==================================================================== */

class _DownloadOverlay extends StatelessWidget {
  const _DownloadOverlay({required this.label, required this.progress});
  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final showBar = progress > 0.001;
    return Positioned.fill(
      child: Container(
        color: const Color(0x331F2329),
        alignment: Alignment.center,
        child: Container(
          width: 190,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  value: showBar ? progress : null,
                  backgroundColor: const Color(0xFFEDEFF4),
                  valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                ),
              ),
              const SizedBox(height: 14),
              Text(label.isEmpty ? '处理中' : label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.text2, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}
