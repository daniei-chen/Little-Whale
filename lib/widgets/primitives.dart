import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// 设计稿里的 SVG 图标。
///
/// 设计稿给的就是 SVG 路径（`04-UI设计稿` 与 `UI改造规格.md` 第 4.3 节的表格），
/// 所以这里原样搬运，保证和小程序端、设计稿三边一致。
class AppIcons {
  AppIcons._();

  static String _svg(String body, Color color, double stroke) {
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' "
        "stroke='$hex' stroke-width='$stroke' stroke-linecap='round' stroke-linejoin='round'>"
        "$body</svg>";
  }

  // ---- tabBar 三个 ----
  static const _parseBody =
      "<path d='M5 4h14v5H5zM5 13h14v7H5z'/><path d='M8 6.5h8M8 16.5h8'/>";
  static const _historyBody =
      "<path d='M4 6h16M4 12h16M4 18h10'/><circle cx='18' cy='18' r='2'/>";
  static const _mineBody =
      "<circle cx='12' cy='8' r='4'/><path d='M5 20c1.2-4 3.6-6 7-6s5.8 2 7 6'/>";

  // ---- 设置项 ----
  static const _clockBody =
      "<path d='M4 12a8 8 0 1 0 2.3-5.7L4 8'/><path d='M4 4v4h4'/><path d='M12 8v4l3 2'/>";
  static const _helpBody =
      "<circle cx='12' cy='12' r='9'/><path d='M9.8 9a2.4 2.4 0 1 1 3.6 2.1c-.9.5-1.4 1-1.4 2'/><path d='M12 17h.01'/>";
  static const _checkBody = "<path d='m5 12 4 4L19 6'/>";
  static const _clipboardBody =
      "<path d='M9 5h6a2 2 0 0 1 2 2v12H7V7a2 2 0 0 1 2-2Z'/><path d='M9 5V3h6v2'/><path d='M10 10h4M10 14h4'/>";
  static const _trashBody =
      "<path d='M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13M10 11v5M14 11v5'/>";
  static const _docBody =
      "<path d='M4 19.5V6a2 2 0 0 1 2-2h9l5 5v10.5a.5.5 0 0 1-.5.5H4.5a.5.5 0 0 1-.5-.5Z'/><path d='M14 4v6h6M8 14h8M8 17h5'/>";
  static const _infoBody = "<circle cx='12' cy='12' r='9'/><path d='M12 10v6M12 7h.01'/>";

  // ---- 功能性 ----
  static const _arrowRightBody = "<path d='M5 12h14M13 6l6 6-6 6'/>";
  static const _chevronRightBody = "<path d='m9 6 6 6-6 6'/>";
  static const _serverBody =
      "<rect x='3' y='4' width='18' height='7' rx='2'/><rect x='3' y='13' width='18' height='7' rx='2'/><path d='M7 7.5h.01M7 16.5h.01'/>";
  static const _linkBody =
      "<path d='M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7'/><path d='M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7'/>";
  static const _playBody = "<path d='M8 5.5v13l11-6.5z'/>";

  static Widget parse(Color c, double size, {double stroke = 1.8}) =>
      _icon(_parseBody, c, size, stroke);
  static Widget history(Color c, double size, {double stroke = 1.8}) =>
      _icon(_historyBody, c, size, stroke);
  static Widget mine(Color c, double size, {double stroke = 1.8}) =>
      _icon(_mineBody, c, size, stroke);
  static Widget clock(Color c, double size, {double stroke = 1.8}) =>
      _icon(_clockBody, c, size, stroke);
  static Widget help(Color c, double size, {double stroke = 1.8}) =>
      _icon(_helpBody, c, size, stroke);
  static Widget check(Color c, double size, {double stroke = 2.0}) =>
      _icon(_checkBody, c, size, stroke);
  static Widget clipboard(Color c, double size, {double stroke = 1.8}) =>
      _icon(_clipboardBody, c, size, stroke);
  static Widget trash(Color c, double size, {double stroke = 1.8}) =>
      _icon(_trashBody, c, size, stroke);
  static Widget doc(Color c, double size, {double stroke = 1.8}) =>
      _icon(_docBody, c, size, stroke);
  static Widget info(Color c, double size, {double stroke = 1.8}) =>
      _icon(_infoBody, c, size, stroke);
  static Widget arrowRight(Color c, double size, {double stroke = 2.0}) =>
      _icon(_arrowRightBody, c, size, stroke);
  static Widget chevronRight(Color c, double size, {double stroke = 2.0}) =>
      _icon(_chevronRightBody, c, size, stroke);
  static Widget server(Color c, double size, {double stroke = 1.8}) =>
      _icon(_serverBody, c, size, stroke);
  static Widget link(Color c, double size, {double stroke = 1.8}) =>
      _icon(_linkBody, c, size, stroke);
  static Widget play(Color c, double size, {double stroke = 1.8}) =>
      _icon(_playBody, c, size, stroke);

  static Widget _icon(String body, Color color, double size, double stroke) {
    return SvgPicture.string(
      _svg(body, color, stroke),
      width: size,
      height: size,
    );
  }
}

/// 按下时轻微缩小的包装器。
///
/// Material 的 InkWell 水波纹和设计稿「克制的蓝白体系」气质不符，
/// 所以统一用这种更安静的反馈。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.985,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 普通卡片：白底 + 1px 细边框 + **无阴影**
/// 这是新设计稿和旧版视觉差异最明显的一点。
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.radius = AppRadius.lg,
    this.background = AppColors.surface,
    this.borderColor = AppColors.line,
    this.margin,
    this.gradient,
    this.glow = false,
    this.glowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color background;
  final Color borderColor;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;

  /// 右上角径向光斑（品牌卡 / 个人卡 / 页面头部用的就是这个）
  final bool glow;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        if (glow)
          Positioned(
            right: -74,
            top: -88,
            child: IgnorePointer(
              child: Container(
                width: 156,
                height: 156,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (glowColor ?? AppColors.blue).withValues(alpha: 0.10),
                      (glowColor ?? AppColors.blue).withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.72],
                  ),
                ),
              ),
            ),
          ),
        Padding(padding: padding, child: child),
      ],
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? background : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// 主按钮：**纯蓝 #4D6BFE，不是渐变**，右侧可带一个箭头图标
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.busy = false,
    this.showArrow = true,
    this.icon,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool showArrow;
  final Widget? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onTap != null;

    return Pressable(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: height,
        decoration: BoxDecoration(
          // 顶部略亮的竖向渐变 + 一层柔和的蓝影。
          // 纯色平涂在高饱和蓝上会显得像色块；加上这两点，成本极低但立刻有立体感。
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: busy
                ? const [Color(0xFFA7B5FC), Color(0xFF93A4FA)]
                : const [Color(0xFF5E79FF), Color(0xFF4356F0)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.md - 1),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.blue.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(width: 9),
            ] else if (icon != null) ...[
              icon!,
              const SizedBox(width: 8),
            ],
            Text(label,
                style: AppText.button.copyWith(
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
                  ],
                )),
            if (showArrow && !busy) ...[
              const SizedBox(width: 8),
              AppIcons.arrowRight(Colors.white, 15),
            ],
          ],
        ),
      ),
    );
  }
}

/// 次级文字按钮（浅蓝底 + 蓝字）
class TextPill extends StatelessWidget {
  const TextPill({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.bg = const Color(0xFFF2F5FF),
    this.fg = AppColors.blue,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 5)],
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

/// 平台徽章
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({
    super.key,
    required this.name,
    required this.bg,
    required this.fg,
    this.fontSize = 10.5,
  });

  final String name;
  final Color bg;
  final Color fg;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        name,
        style: AppText.badge.copyWith(color: fg, fontSize: fontSize),
      ),
    );
  }
}

/// 小圆点
class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 6, this.glow = 0});
  final Color color;
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow > 0
            ? [BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 0, spreadRadius: glow)]
            : null,
      ),
    );
  }
}

/// 一像素分隔线
class HairLine extends StatelessWidget {
  const HairLine({super.key, this.color = AppColors.line, this.indent = 0});
  final Color color;
  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: Container(height: 1, color: color),
      );
}

/// 空状态
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.tip,
    this.action,
  });

  final Widget icon;
  final String title;
  final String tip;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 56),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.blueSoft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 20),
          Text(title, style: AppText.sectionTitle),
          const SizedBox(height: 7),
          Text(tip, style: AppText.meta),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    );
  }
}
