import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../models/parse_result.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primitives.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.onReplay});
  final void Function(ParseResult item) onReplay;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() {
    super.initState();
    AppState.instance.refreshDerived();
  }

  List<ParseResult> get _list => AppState.instance.history;

  Future<void> _confirmDelete(ParseResult item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除这条记录？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('只移除本地记录，已经存到相册的内容不受影响。',
            style: TextStyle(fontSize: 13.5, color: AppColors.text2, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await LocalStore.instance.removeHistory(item.id);
      await AppState.instance.refreshDerived();
      if (mounted) _toast('已删除');
    }
  }

  Future<void> _confirmClear() async {
    if (_list.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空全部记录？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text('共 ${_list.length} 条记录将被移除，无法恢复。已经存到相册的内容不受影响。',
            style: const TextStyle(fontSize: 13.5, color: AppColors.text2, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppState.instance.clearLocalData();
      if (mounted) _toast('已清空');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1600),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final list = _list;
        return ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            const SizedBox(height: 12),
            _buildIntro(list.length),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: list.isEmpty ? _buildEmpty() : _buildList(list),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIntro(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SoftCard(
        radius: 20,
        padding: const EdgeInsets.all(18),
        borderColor: AppColors.brandLine,
        glow: true,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F9FF), Colors.white],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('解析记录', style: AppText.pageTitle),
            const SizedBox(height: 6),
            Text(
              count > 0 ? '共 $count 条 · 仅保存在本机' : '解析过的内容会留在这里',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF878E98), height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return EmptyState(
      icon: AppIcons.history(AppColors.blue, 28),
      title: '还没有解析记录',
      tip: '去首页粘贴一条分享链接试试',
      action: Pressable(
        onTap: () => AppState.instance.requestTab(0),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Text('去解析',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white, height: 1.1)),
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<ParseResult> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 1, 2, 9),
          child: Row(
            children: [
              Text('最近 ${list.length} 条',
                  style: AppText.meta.copyWith(color: const Color(0xFF858D97), fontSize: 11.5)),
              const Spacer(),
              Pressable(
                onTap: _confirmClear,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.redSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFF0DDE0)),
                  ),
                  child: const Text('清空记录',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFFD75B66), height: 1.1)),
                ),
              ),
            ],
          ),
        ),
        ...list.map((e) => _buildRecord(e)),
        const SizedBox(height: 6),
        const Center(
          child: Text('点击任意一条可在首页重新解析 · 长按可删除',
              style: TextStyle(fontSize: 10.5, color: Color(0xFFA4AAB3))),
        ),
      ],
    );
  }

  Widget _buildRecord(ParseResult item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Pressable(
        onTap: () => widget.onReplay(item),
        onLongPress: () => _confirmDelete(item),
        child: SoftCard(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              _cover(item),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? '（无标题）' : item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF30353C),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        PlatformBadge(
                          name: item.platformName,
                          bg: Color(item.platformSoftValue),
                          fg: Color(item.platformColorValue),
                          fontSize: 9.5,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            formatRelative(item.parsedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFA0A6AE), height: 1.1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AppIcons.chevronRight(const Color(0xFFB9BFC8), 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(ParseResult item) {
    final platform = Colors.black;
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 74,
        height: 74,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(item.platformColorValue).withValues(alpha: 0.92),
                    Color(item.platformColorValue),
                  ],
                ),
              ),
            ),
            if (item.coverUrl.isNotEmpty)
              Image.network(
                item.coverUrl,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null ? child : const SizedBox.shrink(),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.48)),
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(12, 12),
                    painter: _MiniPlayPainter(platform),
                  ),
                ),
              ),
            ),
            if (item.duration.isNotEmpty)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(item.duration,
                      style: const TextStyle(fontSize: 8.5, color: Colors.white, height: 1.15)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayPainter extends CustomPainter {
  _MiniPlayPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.28, h * 0.18)
      ..lineTo(w * 0.86, h * 0.50)
      ..lineTo(w * 0.28, h * 0.82)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _MiniPlayPainter old) => old.color != color;
}
