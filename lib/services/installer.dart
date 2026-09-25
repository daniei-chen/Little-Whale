import 'dart:io';

import 'package:flutter/services.dart';

/// 调原生去安装 APK。
///
/// 【为什么更新要跳一下系统安装器】
/// Android 不允许一个 App 静默安装另一个 APK —— 安装那一步**必须**弹系统
/// 确认框，这是系统安全设计，绕不过去也不该绕。
///
/// 但下载完全可以在 App 内完成（带进度条、可续传、不用跳浏览器），
/// 下完再拉起系统安装器，用户点一下「安装」就行。国内 App 基本都是这个流程。
class Installer {
  Installer._();

  static const MethodChannel _ch = MethodChannel('xiaojingyu/installer');

  /// 有没有「安装未知来源应用」的权限。
  ///
  /// Android 8.0 起这个权限是**按应用授予**的，没给的话安装器会被系统拦下。
  /// 8.0 以下没有这个概念，直接返回 true。
  static Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳到系统设置，让用户开启「允许安装未知应用」。
  static Future<void> requestInstallPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<bool>('requestInstall');
    } catch (_) {}
  }

  /// 拉起系统安装器
  static Future<void> install(String path) async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod<bool>('install', {'path': path});
  }
}
