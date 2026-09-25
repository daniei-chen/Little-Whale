import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 状态栏：白底深色图标，和设计稿的白色导航栏一致
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await AppState.instance.bootstrap();

  runApp(const FlashSaveApp());
}

class FlashSaveApp extends StatelessWidget {
  const FlashSaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小鲸鱼',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const AppShell(),
      builder: (context, child) {
        // 锁住文字缩放范围，避免用户把系统字号调到极端值后布局被撑坏
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
