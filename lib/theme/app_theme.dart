import 'package:flutter/material.dart';

/// 设计 token —— 与小程序端「新设计稿（DeepSeek 高级版）」完全对齐。
///
/// 设计稿的手机屏幕宽 374px，真机逻辑宽度约 375dp，
/// 所以设计稿里的 px 数值可以**直接当作 dp 用**，不需要换算。
class AppColors {
  AppColors._();

  // 背景与表面
  static const bg = Color(0xFFF3F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF7F8FA);
  static const surfaceBlue = Color(0xFFF4F7FF);

  // 文字
  static const text = Color(0xFF1F2329);
  static const text2 = Color(0xFF4F5660);
  static const muted = Color(0xFF9299A3);

  // 描边
  static const line = Color(0xFFE8EAEE);
  static const lineStrong = Color(0xFFDFE3E9);

  // 主色
  static const blue = Color(0xFF4D6BFE);
  static const blue2 = Color(0xFF6480FF);
  static const blueSoft = Color(0xFFEDF1FF);
  static const bluePressed = Color(0xFF425EE8);

  // 语义色
  static const green = Color(0xFF16A36F);
  static const greenSoft = Color(0xFFEEF9F5);
  static const red = Color(0xFFE65C68);
  static const redSoft = Color(0xFFFFF5F6);
  static const amber = Color(0xFF9C7830);

  // 卡片边框（品牌卡专用，比普通描边略蓝）
  static const brandLine = Color(0xFFE1E6F3);
}

/// 圆角
class AppRadius {
  AppRadius._();
  static const double xl = 22; // 品牌卡、个人卡
  static const double lg = 16; // 普通卡片
  static const double md = 12; // 输入框、按钮
  static const double sm = 10;
}

/// 文字样式
///
/// 设计稿里有大量 8.5 / 9px 的小字。真机上 9sp 偏小，
/// 按小程序端的同一原则统一提到 **11** 起步，可读性优先于像素级还原。
class AppText {
  AppText._();

  static const brandTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const brandDesc = TextStyle(
    fontSize: 11.5,
    color: Color(0xFF7F8792),
    height: 1.3,
  );

  static const pill = TextStyle(
    fontSize: 11,
    color: Color(0xFF626A75),
    height: 1.1,
  );

  static const cardTitle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
    height: 1.2,
  );

  static const body = TextStyle(
    fontSize: 13,
    color: Color(0xFF343941),
    height: 1.58,
  );

  static const hint = TextStyle(
    fontSize: 12,
    color: Color(0xFFA8AEB8),
    height: 1.5,
  );

  static const meta = TextStyle(
    fontSize: 11,
    color: Color(0xFF9AA1AA),
    height: 1.3,
  );

  static const button = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const resultTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFF252A31),
    height: 1.48,
  );

  static const badge = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  static const sectionTitle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    height: 1.2,
  );

  static const statNum = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    height: 1.15,
  );

  static const statLabel = TextStyle(
    fontSize: 10.5,
    color: Color(0xFF969DA7),
    height: 1.2,
  );

  static const cellLabel = TextStyle(
    fontSize: 14,
    color: Color(0xFF363B42),
    height: 1.2,
  );

  static const cellValue = TextStyle(
    fontSize: 11.5,
    color: Color(0xFFA0A6AE),
    height: 1.2,
  );

  static const pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
    letterSpacing: -0.4,
    height: 1.2,
  );

  static const tabLabel = TextStyle(fontSize: 10.5, height: 1.1);
}

/// 常用阴影 —— 新设计稿整体**不用阴影**，只保留一处极轻的浮起感
class AppShadow {
  AppShadow._();
  static const none = <BoxShadow>[];
  static const soft = [
    BoxShadow(color: Color(0x0F1F2329), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        primary: AppColors.blue,
        surface: AppColors.surface,
        brightness: Brightness.light,
      ),
    );

    return base.copyWith(
      // 去掉 Material 默认的水波纹，改用自绘的按下反馈，
      // 这样才和设计稿「克制的蓝白体系」一致
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2B3038),
        contentTextStyle: TextStyle(fontSize: 13, color: Colors.white),
      ),
    );
  }
}
