package cn.flashsave.flashsave.gif

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaMetadataRetriever
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 动图视频 → GIF。
 *
 * 【为什么自己写，不用现成插件】
 * pub.dev 上那几个「视频转 GIF」插件（如 video_thumbnail_plugin 0.0.5）都有同一个
 * 致命问题：它们用 `getFrameAtTime(t, OPTION_CLOSEST_SYNC)` 抽帧。
 * `OPTION_CLOSEST_SYNC` 只会返回**关键帧（I 帧）**，而小鲸鱼拿到的动图视频通常
 * 只有 2~3 秒、关键帧间隔 1~2 秒 —— 抽 20 帧的结果是 2~3 张图重复 20 次，
 * 生成的 GIF 看起来"卡住不动"，用户会以为功能坏了。
 * 正确选项是 `OPTION_CLOSEST`（取时间上最接近的帧，可以是 P/B 帧）。
 *
 * 【为什么不用动图 WebP】
 * Android 的 Bitmap.compress 只支持静态 WebP，编码动图 WebP 必须内置 libwebp 的
 * native 库。本项目刚经历过病毒库误报整改（见 docs/SECURITY.md），为一个动图功能
 * 重新引入 .so 不划算。GIF 是唯一零原生依赖、且所有相册/微信都能直接播的格式。
 *
 * 【参数取值的考虑】
 *   maxWidth=400：动图源多是竖屏，400 宽在手机上看够清晰；再高 GIF 体积涨得很快
 *   fps=8        ：GIF 本来就不适合高帧率，8 帧/秒配 125ms 延迟观感自然
 *   maxFrames=24 ：上限 3 秒。再长的动图 GIF 会到 5MB 以上，不值得
 */
object VideoToGif {

    const val DEFAULT_MAX_WIDTH = 400
    const val DEFAULT_FPS = 8
    const val DEFAULT_MAX_FRAMES = 24

    /** 缩放用。双线性 + 抗锯齿，比默认 nearest 明显干净 */
    private val SCALE_PAINT = Paint().apply {
        isFilterBitmap = true
        isAntiAlias = true
        isDither = true
    }

    data class Outcome(
        val ok: Boolean,
        val frames: Int = 0,
        val width: Int = 0,
        val height: Int = 0,
        val bytes: Long = 0,
        val error: String = "",
    )

    /**
     * 同步转换。调用方负责放到后台线程（见 MainActivity：
     * 单线程 Executor，避免多张图同时转 GIF 抢内存）。
     */
    fun convert(
        videoPath: String,
        gifPath: String,
        maxWidth: Int = DEFAULT_MAX_WIDTH,
        fps: Int = DEFAULT_FPS,
        maxFrames: Int = DEFAULT_MAX_FRAMES,
    ): Outcome {
        val src = File(videoPath)
        if (!src.isFile) return Outcome(ok = false, error = "视频文件不存在")
        if (src.length() <= 0L) return Outcome(ok = false, error = "视频文件是空的")

        // 参数兜底：外部传 0 / 负数进来也不能把编码器搞崩
        val targetW = maxWidth.coerceIn(64, 1080)
        val targetFps = fps.coerceIn(1, 30)
        val frameCap = maxFrames.coerceIn(2, 120)

        val out = File(gifPath)
        out.parentFile?.mkdirs()

        val retriever = MediaMetadataRetriever()
        var firstFrame: Bitmap? = null
        try {
            retriever.setDataSource(src.absolutePath)

            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.trim()
                ?.toLongOrNull()
                ?: 0L
            if (durationMs <= 0L) {
                return Outcome(ok = false, error = "读不到视频时长，可能不是有效视频")
            }

            // 首帧既用来定尺寸，也直接当 GIF 第一帧（省一次解码）
            val firstRaw = retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: return Outcome(ok = false, error = "无法解码首帧")
            val size = targetSize(firstRaw.width, firstRaw.height, targetW)
            val w = size[0]
            val h = size[1]
            firstFrame = renderFrame(firstRaw, w, h)
            firstRaw.recycle()

            // 帧数按时长 × fps 算，但夹在 [2, frameCap]
            val wanted = (durationMs.toDouble() / 1000.0 * targetFps).roundToInt()
            val frameCount = max(2, min(frameCap, wanted))
            val delayMs = (1000.0 / targetFps).roundToInt().coerceIn(20, 1000)

            val encoder = AnimatedGifEncoder()
            encoder.setRepeat(0) // 0 = 无限循环
            encoder.setDelay(delayMs)
            // NeuQuant 采样间隔：越小颜色越准、越慢。10 是上游默认值，平衡够用
            encoder.setQuality(10)

            var added = 0
            FileOutputStream(out).use { fos ->
                if (!encoder.start(fos)) {
                    return Outcome(ok = false, error = "GIF 编码器初始化失败")
                }

                for (i in 0 until frameCount) {
                    var bmp: Bitmap? = null
                    if (i == 0) {
                        bmp = firstFrame
                    } else {
                        // ★ OPTION_CLOSEST，绝不能用 OPTION_CLOSEST_SYNC（见类注释）
                        val tUs = i * 1_000_000L / targetFps
                        val raw = retriever.getFrameAtTime(tUs, MediaMetadataRetriever.OPTION_CLOSEST)
                        if (raw != null) {
                            bmp = renderFrame(raw, w, h)
                            raw.recycle()
                        }
                    }
                    if (bmp == null) continue

                    val okFrame = encoder.addFrame(bmp)
                    // 首帧留到最后统一回收
                    if (bmp !== firstFrame) {
                        try {
                            bmp.recycle()
                        } catch (_: Throwable) {
                        }
                    }
                    if (okFrame) added++
                }

                encoder.finish()
            }

            if (added < 2) {
                out.delete()
                return Outcome(ok = false, error = "只取到 $added 帧，无法生成动图")
            }
            val bytes = out.length()
            if (bytes <= 0L) {
                out.delete()
                return Outcome(ok = false, error = "生成的 GIF 是空的")
            }
            return Outcome(ok = true, frames = added, width = w, height = h, bytes = bytes)
        } catch (t: Throwable) {
            try {
                out.delete()
            } catch (_: Throwable) {
            }
            return Outcome(ok = false, error = t.message ?: t.javaClass.simpleName)
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
            try {
                firstFrame?.recycle()
            } catch (_: Throwable) {
            }
        }
    }

    /**
     * 把解码出来的原始帧重绘到一张**新的 ARGB_8888 位图**上（顺带缩放）。
     *
     * 【为什么不用 Bitmap.createScaledBitmap】两个坑：
     *   1. 目标尺寸和原帧相同时它直接返回**原对象**，调用方分不清该由谁回收，
     *      一不小心就 double recycle 崩溃；
     *   2. 个别 ROM / 系统版本下 getFrameAtTime 会给出 `Config.HARDWARE` 位图。
     *      硬件位图不支持 `getPixels()`，而 GIF 编码正是靠 getPixels 读像素的，
     *      直接会抛 IllegalStateException。
     * 统一走 Canvas 重绘：结果一定是软件位图、尺寸一定正确、所有权也清楚。
     */
    private fun renderFrame(src: Bitmap, w: Int, h: Int): Bitmap {
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawBitmap(src, null, Rect(0, 0, w, h), SCALE_PAINT)
        return out
    }

    /**
     * 等比缩到 maxWidth 以内，宽高都向下取偶数。
     *
     * GIF 的编码器对奇数宽高不会报错，但部分相册/聊天软件解码时会出细边，
     * 取偶数最省事。
     */
    private fun targetSize(srcW: Int, srcH: Int, maxWidth: Int): IntArray {
        if (srcW <= 0 || srcH <= 0) return intArrayOf(max(2, maxWidth / 2 * 2), 2)
        var w = srcW
        var h = srcH
        if (w > maxWidth) {
            h = (maxWidth.toDouble() * h / w).roundToInt()
            w = maxWidth
        }
        w = max(2, w / 2 * 2)
        h = max(2, h / 2 * 2)
        return intArrayOf(w, h)
    }
}
