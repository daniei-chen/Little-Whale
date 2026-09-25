import 'package:flutter/material.dart';

import '../models/parse_result.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 全屏图片预览。
///
/// 两个诉求：
///   1. 看清楚 —— 可缩放拖动，左右滑动翻页
///   2. **单独保存当前这张** —— 不必为了某一张把整组都存下来
///
/// 返回 true 表示「保存成功了」，让调用方弹个提示。
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.result,
    required this.initialIndex,
  });

  final ParseResult result;
  final int initialIndex;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _pc;
  late int _index;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.result.images.length - 1);
    _pc = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _saveThis() async {
    if (_saving) return;
    setState(() => _saving = true);

    final outcome = await AppState.instance.saveSingleImage(_index);

    if (!mounted) return;
    setState(() => _saving = false);

    if (outcome.saved) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(outcome.message.isEmpty ? '保存失败' : outcome.message),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.result.images;
    final s = AppState.instance;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ---- 顶栏：计数 + 关闭 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  Text('${_index + 1} / ${images.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const SizedBox(width: 46), // 和左边关闭按钮对称，让计数居中
                ],
              ),
            ),

            // ---- 大图 ----
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  // 预览一定要用**大图** url，不能用 thumb ——
                  // 缩略图放大看就是一团糊，那就失去「看清楚」的意义了。
                  final url = images[i].url;
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, p) {
                          if (p == null) return child;
                          final total = p.expectedTotalBytes;
                          return Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white.withValues(alpha: 0.85),
                                value: total == null
                                    ? null
                                    : p.cumulativeBytesLoaded / total,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, _, _) => const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image_outlined,
                                  color: Colors.white38, size: 40),
                              SizedBox(height: 10),
                              Text('这张图加载失败',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ---- 底栏：保存这一张 + 是否在批量勾选内 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Column(
                children: [
                  if (s.downloading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: s.downloadProgress == 0 ? null : s.downloadProgress,
                        minHeight: 3,
                        backgroundColor: const Color(0x33FFFFFF),
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFF7C93FF)),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      // 顺手也能在这里改批量勾选，不用退出去
                      _ToggleChip(
                        on: s.isPicked(_index),
                        onTap: () => s.togglePick(_index),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: _saving || s.downloading ? null : _saveThis,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.blue,
                              disabledBackgroundColor: const Color(0xFF3A4356),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13)),
                              elevation: 0,
                            ),
                            child: _saving || s.downloading
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                            Colors.white)),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.download_rounded,
                                          color: Colors.white, size: 18),
                                      SizedBox(width: 7),
                                      Text('保存这一张',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('左右滑动切换 · 双指缩放看细节',
                      style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部那个「加入批量下载」的小胶囊
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF243056) : const Color(0xFF1A1F2B),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: on ? const Color(0xFF4E63C8) : const Color(0xFF2C3444),
              width: 1.2),
        ),
        child: Row(
          children: [
            Icon(on ? Icons.check_circle : Icons.circle_outlined,
                size: 16, color: on ? const Color(0xFF8FA5FF) : Colors.white38),
            const SizedBox(width: 6),
            Text(on ? '已选' : '未选',
                style: TextStyle(
                    color: on ? const Color(0xFFB9C6FF) : Colors.white54,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
