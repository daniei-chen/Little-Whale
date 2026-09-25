import 'package:flutter/material.dart';

import '../local/engine.dart';
import '../models/parse_result.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primitives.dart';
import '../pages/history_page.dart';
import '../pages/home_page.dart';
import '../pages/mine_page.dart';

/// 主框架：IndexedStack 三页 + 自定义底部导航
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 冷启动自动读剪贴板。
    //
    // 为什么要 postFrame + 延迟：Android 10 起，App 必须**拥有窗口焦点**
    // 才允许读剪贴板，否则返回空或直接抛异常。启动瞬间焦点还没拿到，
    // 所以等首帧画完再稍微等一下。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await AppState.instance.tryAutoParseFromClipboard();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 从后台切回来 —— 这大概率是「用户刚在抖音/小红书复制完链接切回来」，
    // 正是这个功能最有价值的时刻。
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      AppState.instance.tryAutoParseFromClipboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onReplay(ParseResult item) {
    final s = AppState.instance;
    if (item.sourceUrl.isEmpty) {
      s.requestTab(0);
      return;
    }
    s.setText(item.sourceUrl);
    s.requestTab(0);
    s.parse();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final s = AppState.instance;
        final index = s.tabIndex;

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            bottom: false,
            // Stack 的层次很关键：
            //   底层 = 隐藏 WebView（要**真实视口**，1×1 会导致懒加载图片
            //          永远不加载、SPA 也不启动 —— 实测踩过）
            //   上层 = 不透明背景 + 页面内容，把 WebView 完全盖住
            child: Stack(
              children: [
                const Positioned(left: 0, top: 0, child: LocalEngineHost()),
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.bg,
                    child: IndexedStack(
                      index: index,
                      children: [
                        const HomePage(),
                        HistoryPage(onReplay: _onReplay),
                        const MinePage(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _TabBar(
            current: index,
            onTap: s.requestTab,
          ),
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onTap});

  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    Widget item(int i, String label, Widget Function(Color) icon) {
      final on = i == current;
      final color = on ? AppColors.blue : const Color(0xFF9AA1AA);
      return Expanded(
        child: Pressable(
          onTap: () => onTap(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon(color),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppText.tabLabel.copyWith(
                  color: color,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: on ? AppColors.blue : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EBEF))),
      ),
      child: SizedBox(
        height: 60 + bottom,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Row(
            children: [
              item(0, '解析', (c) => AppIcons.parse(c, 19)),
              item(1, '记录', (c) => AppIcons.history(c, 19)),
              item(2, '我的', (c) => AppIcons.mine(c, 19)),
            ],
          ),
        ),
      ),
    );
  }
}
