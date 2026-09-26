import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../local/registry.dart';
import '../services/crash_log.dart';
import '../services/installer.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/primitives.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  /// 正在检查更新 —— 按钮显示「检查中…」并禁用，防止连点
  bool _checkingUpdate = false;

  /// 启动后的静默检查用的定时器。
  ///
  /// 【必须可取消】早先用的是 `Future.delayed`，它没法取消 ——
  /// widget 测试里树都销毁了定时器还挂着，直接报
  /// 「A Timer is still pending even after the widget tree was disposed」。
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // 延迟几秒再查，别和首屏渲染抢时间。
    // 只有真发现新版本才弹窗（同一个版本一天最多提醒一次）。
    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _checkUpdate(context);
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final s = AppState.instance;
        return ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            const SizedBox(height: 12),
            _buildProfile(s),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupLabel('常用'),
                  _Group(children: [
                    _cell(
                      context,
                      icon: AppIcons.clock(AppColors.blue, 14),
                      label: '解析记录',
                      value: '${s.stat.total} 条',
                      onTap: () => s.requestTab(1),
                    ),
                    _cell(
                      context,
                      icon: AppIcons.help(AppColors.blue, 14),
                      label: '使用教程',
                      onTap: () => _showTutorial(context),
                    ),
                    _cell(
                      context,
                      icon: AppIcons.doc(AppColors.blue, 14),
                      label: '支持平台',
                      // 首页只放 6 个核心平台（18 个全铺出来太挤），
                      // 完整列表放这里，想看的人自己点
                      value: '${LocalRegistry.all.length} 个',
                      onTap: () => _showPlatforms(context),
                    ),
                  ]),
                  _groupLabel('解析偏好'),
                  _Group(children: [
                    _switchCell(
                      label: '进 App 自动识别剪贴板',
                      icon: AppIcons.clipboard(AppColors.blue, 14),
                      value: s.settings.autoPaste,
                      subtitle: '识别到支持的链接就直接开始解析',
                      onChanged: (v) => s.updateSettings(s.settings.copyWith(autoPaste: v)),
                    ),
                    _switchCell(
                      label: '动图存成视频',
                      icon: AppIcons.link(AppColors.blue, 14),
                      value: s.saveLiveAsVideo,
                      subtitle: s.saveLiveAsVideo
                          ? '保留动效与音效，存成短视频'
                          : '只存静态封面图',
                      onChanged: s.setSaveLiveAsVideo,
                    ),
                  ]),
                  _groupLabel('其他'),
                  _Group(children: [
                    _cell(
                      context,
                      icon: AppIcons.alert(AppColors.amber, 14),
                      label: '错误日志',
                      value: '排查问题用',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CrashLogPage()),
                      ),
                    ),
                    _cell(
                      context,
                      icon: AppIcons.trash(AppColors.blue, 14),
                      label: '清空本地数据',
                      value: '${s.cacheKb} KB',
                      onTap: () => _confirmClear(context),
                    ),
                    _cell(
                      context,
                      icon: AppIcons.refresh(AppColors.blue, 14),
                      label: '检查更新',
                      value: _checkingUpdate ? '检查中…' : 'v$kAppVersion',
                      onTap: _checkingUpdate
                          ? null
                          : () => _checkUpdate(context, manual: true),
                    ),
                    _cell(
                      context,
                      icon: AppIcons.info(AppColors.blue, 14),
                      label: '关于小鲸鱼',
                      value: 'v$kAppVersion',
                      onTap: () => _showAbout(context),
                    ),
                  ]),
                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      '下载内容版权归原作者所有，请勿用于商业传播',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFFB8BDCD)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }


  /* ---------------- 个人卡 ---------------- */

  Widget _buildProfile(AppState s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SoftCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(17, 17, 17, 15),
        borderColor: AppColors.brandLine,
        glow: true,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F9FF), Colors.white],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE4EAF6)),
                  ),
                  child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('小鲸鱼用户',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.2)),
                      const SizedBox(height: 5),
                      Text('解析记录只存在这台手机里',
                          style: AppText.brandDesc.copyWith(fontSize: 11, color: const Color(0xFF858C96))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8EBF2))),
              ),
              child: Row(
                children: [
                  _stat('${s.stat.total}', '累计解析'),
                  _statDivider(),
                  _stat('${s.stat.today}', '今日解析'),
                  _statDivider(),
                  _stat('${s.cacheKb}', '缓存 KB'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String num, String label) => Expanded(
        child: Column(
          children: [
            Text(num, style: AppText.statNum),
            const SizedBox(height: 3),
            Text(label, style: AppText.statLabel),
          ],
        ),
      );

  Widget _statDivider() => Container(width: 1, height: 30, color: const Color(0xFFECEEF2));

  /* ---------------- 单元格 ---------------- */

  Widget _groupLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(3, 13, 3, 6),
        child: Text(t, style: const TextStyle(fontSize: 11, color: Color(0xFF969DA6), height: 1.2)),
      );

  Widget _iconBox(Widget child) => Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6FF),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(child: child),
      );

  Widget _cell(
    BuildContext context, {
    required Widget icon,
    required String label,
    String? value,
    VoidCallback? onTap,
    String? subtitle,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Row(
          children: [
            _iconBox(icon),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppText.cellLabel),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFFA0A6AE), height: 1.2)),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppText.cellValue),
              ),
            ],
            const SizedBox(width: 5),
            AppIcons.chevronRight(const Color(0xFFC2C7CE), 13),
          ],
        ),
      ),
    );
  }


  Widget _switchCell({
    required String label,
    required Widget icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
  }) {
    return Pressable(
      onTap: () => onChanged(!value),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Row(
          children: [
            _iconBox(icon),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppText.cellLabel),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFFA0A6AE), height: 1.25)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppSwitch(value: value),
          ],
        ),
      ),
    );
  }

  /* ---------------- 对话框 ---------------- */

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空本地数据？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('将移除全部解析记录与统计数据（偏好设置会保留）。已经保存到相册的内容不受影响。',
            style: TextStyle(fontSize: 13.5, color: AppColors.text2, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空',
                  style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) await AppState.instance.clearLocalData();
  }

  Future<void> _showTutorial(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('使用教程', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text(
          '1. 在抖音 / 小红书 / B站 / 微博 / 快手 / 知乎 打开想保存的内容\n'
          '2. 点「分享」→「复制链接」\n'
          '3. 回到小鲸鱼，点「一键粘贴」\n'
          '4. 点「开始解析」，等进度走完\n'
          '5. 视频点「保存到相册」；图文先勾选要的图，再保存\n\n'
          '全程在手机本地完成，链接不会上传到任何服务器。\n'
          '首次保存会请求相册权限，允许即可。\n\n'
          '注：知乎的「回答页」需要登录，请用「专栏文章」的链接。',
          style: TextStyle(fontSize: 13.5, color: AppColors.text2, height: 1.7),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了', style: TextStyle(color: AppColors.blue))),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------------ */
  /* 检查更新                                                            */
  /* ------------------------------------------------------------------ */

  /// 检查更新。
  ///
  /// [manual] = true 是用户主动点的：不管有没有更新都要给个反馈，
  /// 否则点了一下没动静，用户会以为坏了。
  /// [manual] = false 是启动时的静默检查：只在真有新版时才弹窗。
  Future<void> _checkUpdate(BuildContext context, {bool manual = false}) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    final info = await UpdateService.instance.check(ignoreCooldown: manual);

    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    if (info == null) {
      if (manual) {
        if (kUpdateManifestUrl.isEmpty) {
          _toast('还没配置更新地址，暂时无法检查更新');
        } else {
          _toast('已是最新版本 v$kAppVersion');
        }
      }
      return;
    }

    await UpdateService.instance.markNotified(info.build);
    if (!context.mounted) return;

    // 强制更新不给「以后再说」
    final dismissed = await showDialog<bool>(
      context: context,
      barrierDismissible: !info.force,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Expanded(
              child: Text('发现新版本 v${info.version}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本 v$kAppVersion  →  新版本 v${info.version}',
                style: const TextStyle(fontSize: 13, color: AppColors.text2)),
            if (info.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('更新内容',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
              const SizedBox(height: 6),
              Text(info.notes.trim(),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.text2, height: 1.6)),
            ],
            const SizedBox(height: 12),
            const Text('点「立即更新」会打开下载页，装好后数据都会保留。',
                style: TextStyle(fontSize: 12, color: Color(0xFF9AA1AA), height: 1.5)),
          ],
        ),
        actions: [
          if (!info.force)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('以后再说', style: TextStyle(color: AppColors.text2)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('立即更新', style: TextStyle(color: AppColors.blue)),
          ),
        ],
      ),
    );

    // 点了「立即更新」→ **在 App 内下载**，下完拉起系统安装器
    if (dismissed == false) {
      await _downloadAndInstall(context, info);
    }
  }

  /// 应用内下载新版本并安装。
  ///
  /// 【为什么下载放在 App 里】跳浏览器会让用户离开 App、还要自己找文件，
  /// 体验很割裂。这里在 App 内下载（带进度、可断点续传），下完直接拉起
  /// 系统安装器。
  ///
  /// 【安装那一步必须弹系统框】Android 不允许静默安装，这是系统安全设计，
  /// 绕不过去也不该绕。所以用户还是会看到一次确认框。
  Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    // 先看有没有「安装未知应用」的权限；没有就先去设置里开
    final can = await Installer.canInstall();
    if (!can) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('需要开启一个开关',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: const Text(
            '安装新版本需要允许「安装未知应用」。\n\n'
            '点「去开启」会跳到系统设置，找到「小鲸鱼」打开那个开关，然后回来再点一次更新。\n\n'
            '（这是安卓的安全限制，任何 App 自己更新都要走这一步。）',
            style: TextStyle(fontSize: 13, height: 1.7, color: AppColors.text2),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('以后再说', style: TextStyle(color: AppColors.text2))),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Installer.requestInstallPermission();
              },
              child: const Text('去开启', style: TextStyle(color: AppColors.blue)),
            ),
          ],
        ),
      );
      return;
    }

    // 下载进度对话框
    final progress = ValueNotifier<double>(0);
    final label = ValueNotifier<String>('准备下载…');
    var cancelled = false;

    if (!context.mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('正在下载新版本',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: p > 0 ? p : null,
                  minHeight: 6,
                  backgroundColor: AppColors.blueSoft,
                  valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: label,
                builder: (_, t, _) => Text(t,
                    style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: const Text('取消', style: TextStyle(color: AppColors.text2)),
          ),
        ],
      ),
    ));

    String? path;
    try {
      path = await UpdateService.instance.downloadApk(
        info,
        onProgress: (p, got, total) {
          progress.value = p;
          final mb = (got / 1024 / 1024).toStringAsFixed(1);
          label.value = total > 0
              ? '$mb MB / ${(total / 1024 / 1024).toStringAsFixed(1)} MB'
              : '$mb MB';
        },
      );
    } catch (e) {
      if (!mounted || cancelled) return;
      // 应用内下载失败时给一条退路 —— 别让用户卡在「更新不了」。
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('下载失败：$e'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '用浏览器打开',
          onPressed: () async {
            final uri = Uri.tryParse(info.url);
            if (uri == null) return;
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {
              _toast('打不开，请手动访问：${info.url}');
            }
          },
        ),
      ));
      return;
    }

    if (!mounted) return;
    // 关掉进度框（如果用户已经点了取消，这里就不会再有关闭动作）
    if (!cancelled) Navigator.of(context, rootNavigator: true).pop();

    if (cancelled) return;

    try {
      await Installer.install(path);
    } catch (e) {
      _toast('安装包已下载，但打不开安装器：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  /// 「支持平台」对话框 —— 完整的 18 个平台列表。
  ///
  /// 【为什么要有这一页】首页只显示 6 个核心平台（18 个全铺出来品牌卡太挤），
  /// 但用户需要能查到完整列表 —— 尤其想知道「我常用的那个平台支不支持」。
  /// 这里按「能力」分组展示，顺便说明通用适配器的边界。
  Future<void> _showPlatforms(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('支持平台',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('核心平台 · 无水印原片 + 动图',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text)),
                const SizedBox(height: 4),
                Text(
                  LocalRegistry.coreNames.join(' · '),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.text2, height: 1.7),
                ),
                const SizedBox(height: 14),
                const Text('其他主流平台 · 通用解析',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text)),
                const SizedBox(height: 4),
                Text(
                  LocalRegistry.genericNames.join(' · '),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.text2, height: 1.7),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Text(
                    '通用解析靠网页渲染提取，**拿不到无水印原图**，也识别不了动图。\n'
                    '优酷 / 爱奇艺 / 腾讯视频 / 芒果TV 的正片有 DRM 加密，取不到直链。',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.muted, height: 1.6),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('没找到你要的平台？把链接发给作者，我们会评估加入。',
                    style: TextStyle(fontSize: 12, color: AppColors.blue)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了', style: TextStyle(color: AppColors.blue))),
        ],
      ),
    );
  }
  /// 「关于」对话框。
  ///
  /// 【改了什么】原来这里会去探测解析服务、显示「服务已连接 / 未连接」和服务地址 ——
  /// 解析早就不经过服务器了，那段探测和地址展示都是误导。现在只留：
  /// 版本号、能做什么、隐私说明。信息更少，但每一条都是真的。
  Future<void> _showAbout(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('关于小鲸鱼',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本 v$kAppVersion',
                style: const TextStyle(fontSize: 13.5, color: AppColors.text2)),
            const SizedBox(height: 12),
            const Text(
                '粘贴分享链接，保存无水印原片。支持抖音、小红书、B站、微博、快手、知乎。',
                style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.6)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1FBF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD6F0DE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: Color(0xFF2FA05A)),
                    SizedBox(width: 6),
                    Text('解析不经过网络',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF2FA05A),
                            fontWeight: FontWeight.w600)),
                  ]),
                  SizedBox(height: 6),
                  Text('全部在手机里完成，链接不会上传到任何地方，也不需要服务器。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF5A7D68), height: 1.6)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('解析记录只存在你的手机本地。',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了', style: TextStyle(color: AppColors.blue))),
        ],
      ),
    );
  }
}

/// 分组容器：圆角 + 细边框，内部用 1px 分隔线
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Padding(
          padding: EdgeInsets.only(left: 51),
          child: HairLine(color: Color(0xFFEFF1F4)),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// 自定义胶囊开关（39×23），与设计稿一致
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        width: 39,
        height: 23,
        decoration: BoxDecoration(
          color: value ? AppColors.blue : const Color(0xFFDFE3E8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 19,
            height: 19,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x1F1F2329), blurRadius: 5, offset: Offset(0, 2))],
            ),
          ),
        ),
      ),
    );
  }
}
