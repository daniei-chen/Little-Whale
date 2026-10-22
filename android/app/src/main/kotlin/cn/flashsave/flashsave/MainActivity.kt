package cn.flashsave.flashsave

import android.os.Handler
import android.os.Looper
import cn.flashsave.flashsave.gif.VideoToGif
import cn.flashsave.flashsave.motionphoto.MotionPhotoWriter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * 主 Activity —— 只负责两件「本地媒体转换」的事：
 *
 *   videoToGif      动图视频 → GIF（图片格式动图，能直接发微信）
 *   makeMotionPhoto 静态封面 + 短视频 → 动态照片（单文件 .jpg，相册里是照片，长按会动）
 *
 * 【注意和 v0.0.5 的区别】
 * v0.0.6 拆掉的那条通道是 `xiaojingyu/installer`（下载 APK → FileProvider →
 * 拉起系统安装器），它需要 REQUEST_INSTALL_PACKAGES 权限，是当初被判
 * a.gray.BulimiaTGen.f 高危的最大单一原因，**绝对不要加回来**
 * （见 docs/SECURITY.md）。
 *
 * 现在的 `xiaojingyu/media` 是纯本地媒体处理：
 *   · 无任何新权限（只读写自己缓存在私有目录里的临时文件）
 *   · 无网络、无外部 Intent、无进程间通信
 *   · 只用公开的 MediaMetadataRetriever / BitmapFactory + 纯字节拼接
 * 这类「读本地媒体做格式转换」在当前启发式画像里是中性的，不影响报毒判定。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "xiaojingyu/media"

    /**
     * 单线程队列。
     *
     * 转 GIF 是 CPU + 内存密集型（每帧都要做 NeuQuant 256 色量化），
     * 动态照片合成是 IO 密集型。两者都用同一个队列串行执行：
     * 用户一次保存十几张动图时，并行会把内存打爆，排队最稳。
     */
    private val mediaWorker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "videoToGif" -> handleVideoToGif(call, result)
                    "makeMotionPhoto" -> handleMakeMotionPhoto(call, result)
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

        mediaWorker.execute {
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

    private fun handleMakeMotionPhoto(call: MethodCall, result: MethodChannel.Result) {
        val coverPath = call.argument<String>("coverPath")
        val videoPath = call.argument<String>("videoPath")
        val outPath = call.argument<String>("outPath")
        if (coverPath.isNullOrEmpty() || videoPath.isNullOrEmpty() || outPath.isNullOrEmpty()) {
            result.error("E_ARG", "coverPath / videoPath / outPath 不能为空", null)
            return
        }
        val quality = call.argument<Int>("quality") ?: 95

        mediaWorker.execute {
            val outcome = MotionPhotoWriter.make(coverPath, videoPath, outPath, quality)
            mainHandler.post {
                if (outcome.ok) {
                    result.success(
                        mapOf(
                            "bytes" to outcome.bytes,
                            "videoBytes" to outcome.videoBytes,
                            "coverRecoded" to outcome.coverRecoded,
                        )
                    )
                } else {
                    result.error("E_MOTION", outcome.error, null)
                }
            }
        }
    }

    override fun onDestroy() {
        mediaWorker.shutdownNow()
        super.onDestroy()
    }
}
