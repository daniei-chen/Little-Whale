package cn.flashsave.flashsave.hls

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * 把拼接好的 MPEG-TS 文件重新封装成 MP4。
 *
 * 【为什么需要这一步】HLS 的媒体本体是几十个 `.ts` 分片，顺序拼接起来就是一条
 * 合法的 MPEG-TS 流（实测 ffprobe 认得出 h264 + aac、时长也对）。但：
 *   · 相册不显示 `.ts`（MediaStore 的 video 分类只收 mp4/3gp 等）
 *   · 用户拿到 `.ts` 也没法直接发给别人
 * 所以必须换容器。**这里只换容器，不重编码** —— 视频/音频的码流原样搬过去，
 * 所以速度很快（十几秒的片子通常 1~2 秒出结果），画质零损失。
 *
 * 【为什么用系统 API 而不是塞一个 ffmpeg】
 * 小鲸鱼刚经历过病毒库误报整改（见 docs/SECURITY.md）：多一个第三方 `.so`
 * 就多一份静态扫描的可疑特征。MediaExtractor / MediaMuxer 是系统组件，
 * 不增大 APK，也不引入新的二进制。
 *
 * 【两个必须自己处理的坑】
 * 1. **AAC 的 ADTS 头**：TS 里的 AAC 每帧前面带 7 字节 ADTS 头；MP4 里不能有，
 *    但需要一份 AudioSpecificConfig（ASC）写进 `csd-0`。不处理的话成品
 *    「有声音轨但没声」或直接播不了。见 [buildAsc]。
 * 2. **重复的 track**：实测 AcFun 的 TS 里 ffprobe 会列出两组 h264+aac
 *    （每个分片各自带 PMT/SPS）。MediaExtractor 可能报出多余 track，
 *    这里按 mime 只取第一条 video + 第一条 audio。
 */
object TsRemuxer {

    data class Outcome(
        val ok: Boolean,
        val videoTracks: Int = 0,
        val audioTracks: Int = 0,
        val durationMs: Long = 0,
        val bytes: Long = 0,
        val width: Int = 0,
        val height: Int = 0,
        val error: String = "",
    )

    /** 读一帧需要的缓冲区：4K 视频关键帧可能 >2MB，给足一点 */
    private const val SAMPLE_BUFFER = 4 * 1024 * 1024

    fun remux(tsPath: String, mp4Path: String): Outcome {
        val src = File(tsPath)
        if (!src.isFile) return Outcome(ok = false, error = "TS 文件不存在")
        if (src.length() <= 0L) return Outcome(ok = false, error = "TS 文件是空的")

        val out = File(mp4Path)
        out.parentFile?.mkdirs()

        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false
        try {
            extractor.setDataSource(src.absolutePath)
            val count = extractor.trackCount
            if (count <= 0) return Outcome(ok = false, error = "TS 里没有找到任何轨道")

            muxer = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            // 已添加的轨道：srcIndex -> (dstIndex, isAudio)
            val chosen = mutableListOf<Triple<Int, Int, Boolean>>()
            var sawVideo = false
            var sawAudio = false

            for (i in 0 until count) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                val isVideo = mime.startsWith("video/")
                val isAudio = mime.startsWith("audio/")
                if (!isVideo && !isAudio) continue
                // 只取第一条 video / 第一条 audio（见类注释第 2 点）
                if (isVideo && sawVideo) continue
                if (isAudio && sawAudio) continue

                if (isAudio && mime == MediaFormat.MIMETYPE_AUDIO_AAC) {
                    // 没有 csd-0 的话，MediaMuxer 写出来的 MP4 是无声的
                    // Android 没有公开的 KEY_CSD 常量（KEY_CSD_0 要 API 30+），直接用字符串
                    if (!fmt.containsKey("csd-0")) {
                        val asc = buildAscFromTs(extractor, i)
                        if (asc != null) fmt.setByteBuffer("csd-0", ByteBuffer.wrap(asc))
                    }
                }

                val dst = muxer.addTrack(fmt)
                chosen.add(Triple(i, dst, isAudio))
                if (isVideo) sawVideo = true
                if (isAudio) sawAudio = true
            }

            if (chosen.isEmpty()) return Outcome(ok = false, error = "TS 里没有可用的音视频轨道")

            muxer.start()
            started = true

            val buffer = ByteBuffer.allocateDirect(SAMPLE_BUFFER)
            val info = MediaCodec.BufferInfo()
            var maxPtsUs = 0L
            var written = 0

            for ((srcIdx, dstIdx, isAudio) in chosen) {
                extractor.selectTrack(srcIdx)
                extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

                var basePts = -1L
                var skipped = 0
                while (true) {
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break
                    val pts = extractor.sampleTime
                    if (pts < 0) {
                        // 时间戳读不到的样本直接丢，MediaMuxer 会拒绝负时间戳
                        if (!extractor.advance()) break
                        continue
                    }
                    if (basePts < 0) basePts = pts

                    var offset = 0
                    var payload = size
                    if (isAudio) {
                        // 剥掉 ADTS 头（7 或 9 字节），见 [adtsHeaderLength]
                        val hdr = adtsHeaderLength(buffer, size)
                        if (hdr > 0) {
                            offset = hdr
                            payload = size - hdr
                        }
                        if (payload <= 0) {
                            if (!extractor.advance()) break
                            continue
                        }
                    }

                    info.offset = offset
                    info.size = payload
                    info.presentationTimeUs = pts - basePts
                    info.flags = extractor.sampleFlags
                    try {
                        muxer.writeSampleData(dstIdx, buffer, info)
                        written++
                        if (info.presentationTimeUs > maxPtsUs) maxPtsUs = info.presentationTimeUs
                    } catch (_: Throwable) {
                        // 单帧写失败不该让整条片子失败（TS 尾部常有残缺帧）
                        skipped++
                    }
                    if (!extractor.advance()) break
                }
                extractor.unselectTrack(srcIdx)
            }

            if (written <= 0) return Outcome(ok = false, error = "一帧都没写进去，TS 可能已损坏")

            muxer.stop()
            started = false
            val bytes = out.length()
            if (bytes <= 0L) return Outcome(ok = false, error = "转出来的 MP4 是空的")

            // 【复核：不信任自己算出来的时长 —— 但只在可疑时才复核】
            //
            // 上面的 `maxPtsUs` 是从样本时间戳累出来的，如果时间戳处理有偏差
            // （basePts 归一化不对、或丢了几帧），它和真实时长会对不上 ——
            // 那种情况下视频能播，但进度条错乱、系统播放器可能显示 0:00。
            //
            // 不过 MediaMetadataRetriever 很贵：实测在模拟器上让一条 20 秒的片子
            // 从 3.2s 变成 8.2s（+5s）。所以只在**自算值可疑**时才去读产物：
            //   自算 <= 0（完全算不出来），或 自算 < 500ms（几乎是空壳，必然不对）
            // 正常结果直接用自算值 —— 实测它和 ffprobe 差不到 0.3%。
            val selfMs = maxPtsUs / 1000
            val needProbe = selfMs <= 0L || selfMs < 500L
            val probed = if (needProbe) probeMp4(out.absolutePath) else null
            val realDuration = if (probed != null && probed.durationMs > 0) {
                probed.durationMs
            } else {
                selfMs
            }

            return Outcome(
                ok = true,
                videoTracks = if (sawVideo) 1 else 0,
                audioTracks = if (sawAudio) 1 else 0,
                durationMs = realDuration,
                bytes = bytes,
                width = probed?.width ?: 0,
                height = probed?.height ?: 0,
            )
        } catch (t: Throwable) {
            try {
                out.delete()
            } catch (_: Throwable) {
            }
            return Outcome(ok = false, error = t.message ?: t.javaClass.simpleName)
        } finally {
            try {
                if (started) muxer?.stop()
            } catch (_: Throwable) {
            }
            try {
                muxer?.release()
            } catch (_: Throwable) {
            }
            try {
                extractor.release()
            } catch (_: Throwable) {
            }
        }
    }

    /** 用系统解析器把产物读一遍，拿到真实时长与分辨率 */
    private fun probeMp4(path: String): Probed {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            val ms = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            Probed(ms, w, h)
        } catch (_: Throwable) {
            Probed(0, 0, 0)
        } finally {
            try { r.release() } catch (_: Throwable) {}
        }
    }

    private data class Probed(val durationMs: Long, val width: Int, val height: Int)

    /**
     * ADTS 头长度：protect_absent=1 时 7 字节，否则 9 字节（带 CRC）。
     * 头不是 `0xFFFx` 就返回 0（说明不是 ADTS，别乱剥）。
     */
    private fun adtsHeaderLength(buf: ByteBuffer, size: Int): Int {
        if (size < 7) return 0
        val b0 = buf.get(0).toInt() and 0xFF
        val b1 = buf.get(1).toInt() and 0xFF
        if (b0 != 0xFF || (b1 and 0xF0) != 0xF0) return 0
        val protectionAbsent = b1 and 0x01
        return if (protectionAbsent == 1) 7 else 9
    }

    /**
     * 从 TS 的 AAC 首帧 ADTS 头推出 AudioSpecificConfig（ASC）。
     *
     * ADTS 头里：`profile`(2bit, 值 0 表示 AAC-LC，写进 ASC 要 +1)、
     * `sampling_frequency_index`(4bit)、`channel_configuration`(3bit)。
     * ASC（2 字节）布局：
     *   [0..4] audioObjectType(5)  [5..8] freqIndex(4)  [9..12] channelConfig(4)
     *   [13..15] 其余为 0
     */
    private fun buildAscFromTs(extractor: MediaExtractor, trackIndex: Int): ByteArray? {
        return try {
            extractor.selectTrack(trackIndex)
            extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            val buf = ByteBuffer.allocateDirect(1024)
            val n = extractor.readSampleData(buf, 0)
            var asc: ByteArray? = null
            if (n >= 7) {
                val b2 = buf.get(2).toInt() and 0xFF
                val b3 = buf.get(3).toInt() and 0xFF
                val profile = (b2 shr 6) and 0x03      // 0=AAC-LC(MAIN?) 实际是 object type -1
                val freqIdx = (b2 shr 2) and 0x0F
                val chanCfg = ((b2 and 0x01) shl 2) or ((b3 shr 6) and 0x03)
                if (freqIdx in 0..12 && chanCfg in 1..7) {
                    val audioObjectType = profile + 1
                    val v = ((audioObjectType and 0x1F) shl 11) or
                        ((freqIdx and 0x0F) shl 7) or
                        ((chanCfg and 0x0F) shl 3)
                    asc = byteArrayOf(((v shr 8) and 0xFF).toByte(), (v and 0xFF).toByte())
                }
            }
            extractor.unselectTrack(trackIndex)
            asc
        } catch (_: Throwable) {
            try {
                extractor.unselectTrack(trackIndex)
            } catch (_: Throwable) {
            }
            null
        }
    }
}
