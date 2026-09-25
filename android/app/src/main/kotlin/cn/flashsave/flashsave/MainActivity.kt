package cn.flashsave.flashsave

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新安装。
 *
 * 【为什么需要原生代码】
 * Android 不允许一个 App 悄悄安装另一个 APK —— 安装这一步**必须**弹系统的
 * 确认框，这是系统安全设计，绕不过去（也不该绕）。
 *
 * 但「下载」完全可以在 App 里做：带进度条、可断点续传、不用跳浏览器。
 * 下完再通过这里拉起系统安装器，用户点一下「安装」即可。
 * 国内 App 的更新基本都是这个流程。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "xiaojingyu/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 有没有「安装未知来源应用」的权限
                    "canInstall" -> result.success(canRequestInstall())

                    // 跳去系统设置，让用户给这个权限
                    "requestInstall" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                                i.data = Uri.parse("package:$packageName")
                                startActivity(i)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("E_SETTINGS", e.message, null)
                        }
                    }

                    // 拉起系统安装器安装指定路径的 APK
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("E_ARG", "path 为空", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("E_INSTALL", e.message ?: "安装失败", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Android 8.0 起才有「未知来源」这个开关；8.0 以下直接允许 */
    private fun canRequestInstall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) throw IllegalStateException("安装包不存在：$path")

        // 必须走 FileProvider —— Android 7.0 起直接传 file:// 会抛
        // FileUriExposedException。authority 与 AndroidManifest 里声明的一致。
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}