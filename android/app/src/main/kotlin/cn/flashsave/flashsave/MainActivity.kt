package cn.flashsave.flashsave

import android.os.Handler
import android.os.Looper
import cn.flashsave.flashsave.gif.VideoToGif
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * 主 Activity。
 *
 * 【这里只剩一件事：把动图视频转成 GIF】
 *
 * 注意和 v0.0.5 的区别 —— v0.0.6 拆掉的那条通道是
 * `xiaojingyu/installer`（下载 APK → FileProvider → 拉起系统安装器），
 * 它需要 REQUEST_INSTALL_PACKAGES 权限，是当初被判 a.gray.BulimiaTGen.f
 * 高危的最大单一原因，**绝对不要加回来**（见 docs/SECURITY.md）。
 *
 * 现在的 `xiaojingyu/gif` 是纯本地媒体转换：
 *   · 无任何新权限（只读自己写进缓存目录的临时视频）
 *   · 无网络、无外部 Intent、无进程间通信
 *   · 只用公开的 MediaMetadataRetriever + 项目内置的 GIF 编码器
 * 这类「读本地媒体文件做格式转换」在当前的启发式画像里是中性的，
 * 不影响报毒判定。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "xiaojingyu/gif"

    /**
     * 单线程：转 GIF 是 CPU + 内存密集型（每帧都要做 NeuQuant 256 色量化）。
     * 用户一次保存十几张动图时，并行转换会把内存打爆 —— 排队一个个来，
     * 单张 2~4 秒，总时长可以接受。
     */
    private val gifWorker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "videoToGif" -> handleVideoToGif(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleVideoToGif(call: MethodCall, result: MethodChannel.Result) {
        val videoPath = call.argument<String>("videoPath")
        val gifPath = call.argument<String>("gifPath")
        if (videoPath.isNullOrEmpty() || gifPath.isNullOrEmpty()) {
            result.error("E_ARG", "videoPath / gifPath 不能为空", null)
            return
        }
        val maxWidth = call.argument<Int>("maxWidth") ?: VideoToGif.DEFAULT_MAX_WIDTH
        val fps = call.argument<Int>("fps") ?: VideoToGif.DEFAULT_FPS
        val maxFrames = call.argument<Int>("maxFrames") ?: VideoToGif.DEFAULT_MAX_FRAMES

        gifWorker.execute {
            val outcome = VideoToGif.convert(videoPath, gifPath, maxWidth, fps, maxFrames)
            mainHandler.post {
                if (outcome.ok) {
                    result.success(
                        mapOf(
                            "frames" to outcome.frames,
                            "width" to outcome.width,
                            "height" to outcome.height,
                            "bytes" to outcome.bytes,
                        )
                    )
                } else {
                    result.error("E_GIF", outcome.error, null)
                }
            }
        }
    }

    override fun onDestroy() {
        gifWorker.shutdownNow()
        super.onDestroy()
    }
}
