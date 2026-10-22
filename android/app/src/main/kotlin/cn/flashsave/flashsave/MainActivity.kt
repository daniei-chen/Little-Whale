package cn.flashsave.flashsave

import io.flutter.embedding.android.FlutterActivity

/**
 * 主 Activity —— 现在只是一个干净的 Flutter 宿主。
 *
 * 【为什么变简单了】
 * v0.0.5 及以前这里挂了一条 MethodChannel（xiaojingyu/installer），
 * 用于「应用内下载新版本 APK → FileProvider 转 content:// → 拉起系统安装器」。
 * 这套能力本身是合规的（安装仍需用户手动确认，Android 不允许静默安装），
 * 但它在静态扫描里表现为：
 *
 *   REQUEST_INSTALL_PACKAGES + 下载 .apk + ACTION_VIEW
 *   + application/vnd.android.package-archive + FileProvider
 *
 * 这套特征和「推广/捆绑/自我更新的灰色软件」完全重合，是 v0.0.5 被
 * 腾讯病毒库判成 a.gray.BulimiaTGen.f 的最大单一原因，也直接引发了
 * MIUI 的高危拦截和反诈中心来电核实。
 *
 * v0.0.6 起彻底移除：更新检查只负责「告诉你有没有新版」，点更新就打开
 * 浏览器下载页，交给系统下载器和系统安装流程。App 自己不再碰任何
 * APK 文件，也不再有安装别的东西的能力。
 *
 * 对应地，AndroidManifest 里的 REQUEST_INSTALL_PACKAGES 权限、
 * FileProvider 声明、res/xml/file_paths.xml 一并删除。
 * 不要为了「体验流畅」把它们加回来 —— 那会把整个包重新推回高危名单。
 */
class MainActivity : FlutterActivity()
