package cn.flashsave.flashsave.motionphoto

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * 把「静态封面 + 短视频」重新封装成一张 Android **动态照片（Motion Photo）**。
 *
 * 【格式本质】
 * 动态照片不是新发明的图片格式，它就是：
 *
 *     [ JPEG 图片数据 ... EOI ] [ 直接追加的 MP4 视频 ]
 *                              ↑
 *     由 JPEG 里的 XMP 元数据标明「从文件末尾倒数这么多字节开始是视频」
 *
 * 所以在不支持的相册里它就是一张普通 jpg，在支持的相册里长按/点开才会动。
 * 平台给的动图本来就是「静态封面 + 2~3 秒带音轨视频」两段素材，正好就是
 * 这个格式的两种原料 —— 不需要抽帧，也不需要转码，纯粹是字节拼接。
 *
 * 【为什么同时写两套 XMP 字段】
 * Android 动态照片存在两套并行的标准：
 *   旧标准 MicroVideo   —— 小米 MIUI / 早期 Google 用
 *   新标准 MotionPhoto  —— 三星、Pixel、以及小米 HyperOS 3 起
 * 两套字段语义重叠、互不冲突，同时写进去能最大化被识别的概率。
 * 据公开实测，HyperOS 3 只需标准 XMP 即可识别，不需要厂商私有元数据；
 * 更老的机型可能需要额外字段，那种情况我们无能为力，只能退化成静态封面。
 *
 * 【为什么不做 iOS 的 Live Photo】
 * 那是「JPEG + 配对 MOV 两个文件 + assetIdentifier 关联」，Android 相册不认，
 * 而且各厂商实现还在分裂。单文件 Motion Photo 才是 Android 这边的正解。
 */
object MotionPhotoWriter {

    /** APP1 段里 XMP 的识别头，Adobe 规定的固定字符串（含结尾 NUL） */
    private val XMP_NAMESPACE = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.US_ASCII)

    data class Outcome(
        val ok: Boolean,
        val bytes: Long = 0,
        val videoBytes: Long = 0,
        val coverRecoded: Boolean = false,
        val error: String = "",
    )

    /**
     * 同步合成。调用方负责放到后台线程。
     *
     * 封面如果不是 JPEG（平台常给 webp / heic），这里会自动解码并重编码成 JPEG ——
     * 因为 XMP 里声明的 `Item:Mime` 是 `image/jpeg`，容器里就必须真的是 JPEG。
     */
    fun make(
        coverPath: String,
        videoPath: String,
        outPath: String,
        jpegQuality: Int = 95,
    ): Outcome {
        val coverFile = File(coverPath)
        val videoFile = File(videoPath)
        if (!coverFile.isFile) return Outcome(ok = false, error = "封面文件不存在")
        if (!videoFile.isFile) return Outcome(ok = false, error = "视频文件不存在")

        val out = File(outPath)
        out.parentFile?.mkdirs()

        try {
            val videoBytes = videoFile.readBytes()
            if (videoBytes.size < 1024) {
                return Outcome(ok = false, error = "视频太小，可能下载不完整")
            }

            val rawCover = coverFile.readBytes()
            val coverIsJpeg = isJpeg(rawCover)
            val jpegBytes: ByteArray = if (coverIsJpeg) {
                rawCover
            } else {
                // webp / heic / png → 重编码成 JPEG（顺带保证是标准 baseline/progressive）
                val bmp = BitmapFactory.decodeByteArray(rawCover, 0, rawCover.size)
                    ?: return Outcome(ok = false, error = "封面不是可识别的图片")
                val bos = ByteArrayOutputStream()
                // 用 quality 而不是「动态照片主图应该无损」：JPEG 本来就是有损，
                // 95 在肉眼和原图无差别，同时避免文件过大
                bmp.compress(Bitmap.CompressFormat.JPEG, jpegQuality.coerceIn(60, 100), bos)
                bmp.recycle()
                bos.toByteArray()
            }

            val xmp = buildXmp(videoBytes.size.toLong()).toByteArray(Charsets.UTF_8)
            val withXmp = insertXmpSegment(jpegBytes, xmp)

            out.outputStream().use { fos ->
                fos.write(withXmp)
                fos.write(videoBytes)
                fos.flush()
            }

            val total = out.length()
            if (total <= 0L) {
                out.delete()
                return Outcome(ok = false, error = "写出的文件是空的")
            }
            return Outcome(
                ok = true,
                bytes = total,
                videoBytes = videoBytes.size.toLong(),
                coverRecoded = !coverIsJpeg,
            )
        } catch (t: Throwable) {
            try {
                out.delete()
            } catch (_: Throwable) {
            }
            return Outcome(ok = false, error = t.message ?: t.javaClass.simpleName)
        }
    }

    /** JPEG 一定以 SOI（FF D8）开头 */
    private fun isJpeg(b: ByteArray): Boolean =
        b.size > 4 && b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte()

    /**
     * 构造 APP1（XMP）段并插到 JPEG 里。
     *
     * JPEG 结构：SOI(FFD8) + [APP0 JFIF] + [APP1 XMP] + ... + SOS + 数据 + EOI(FFD9)
     * XMP 必须落在 SOS 之前，所以我们插在「SOI + 可能的 JFIF APP0」之后 ——
     * JFIF 规范要求 APP0 紧跟 SOI，把 XMP 塞在 SOI 和 APP0 中间虽然多数解析器
     * 能忍，但没必要冒险。
     */
    private fun insertXmpSegment(jpeg: ByteArray, xmp: ByteArray): ByteArray {
        require(isJpeg(jpeg)) { "不是 JPEG 数据" }

        var pos = 2
        // 跳过紧跟 SOI 的 APP0（JFIF / JFXX）
        if (pos + 3 < jpeg.size &&
            jpeg[pos] == 0xFF.toByte() &&
            (jpeg[pos + 1].toInt() and 0xFF) == 0xE0
        ) {
            val segLen = ((jpeg[pos + 2].toInt() and 0xFF) shl 8) or (jpeg[pos + 3].toInt() and 0xFF)
            if (segLen in 2..(jpeg.size - pos)) pos += 2 + segLen
        }

        val app1 = buildApp1(xmp)
        val out = ByteArray(jpeg.size + app1.size)
        System.arraycopy(jpeg, 0, out, 0, pos)
        System.arraycopy(app1, 0, out, pos, app1.size)
        System.arraycopy(jpeg, pos, out, pos + app1.size, jpeg.size - pos)
        return out
    }

    /** FF E1 + 2 字节长度（含长度字段本身）+ 命名空间 + XMP 本体 */
    private fun buildApp1(xmp: ByteArray): ByteArray {
        val payloadLen = XMP_NAMESPACE.size + xmp.size
        val segLen = payloadLen + 2 // 长度字段自身也要算进去
        require(segLen <= 0xFFFF) { "XMP 太大（$segLen 字节），超出 APP1 单段上限 65535" }

        val out = ByteArray(2 + segLen)
        out[0] = 0xFF.toByte()
        out[1] = 0xE1.toByte()
        out[2] = ((segLen shr 8) and 0xFF).toByte()
        out[3] = (segLen and 0xFF).toByte()
        System.arraycopy(XMP_NAMESPACE, 0, out, 4, XMP_NAMESPACE.size)
        System.arraycopy(xmp, 0, out, 4 + XMP_NAMESPACE.size, xmp.size)
        return out
    }

    /**
     * 生成 XMP packet。新旧两套字段同时写。
     *
     * [videoSize] 就是「视频字节数」，也就是两个标准里 offset 字段要填的值 ——
     * 因为视频是追加在文件末尾的，从末尾倒数这么多字节正好是视频起点。
     */
    private fun buildXmp(videoSize: Long): String {
        val size = videoSize.toString()
        return buildString {
            append("<?xpacket begin=\"\uFEFF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n")
            append("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"XiaoJingYu\">\n")
            append(" <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n")
            append("  <rdf:Description rdf:about=\"\"\n")
            append("    xmlns:GCamera=\"http://ns.google.com/photos/1.0/camera/\"\n")
            append("    xmlns:Container=\"http://ns.google.com/photos/1.0/container/\"\n")
            append("    xmlns:Item=\"http://ns.google.com/photos/1.0/container/item/\"\n")
            // ---- 新标准（MotionPhoto）：三星 / Pixel / HyperOS 3 ----
            append("    GCamera:MotionPhoto=\"1\"\n")
            append("    GCamera:MotionPhotoVersion=\"1\"\n")
            append("    GCamera:MotionPhotoPresentationTimestampUs=\"0\"\n")
            // ---- 旧标准（MicroVideo）：MIUI 等 ----
            append("    GCamera:MicroVideo=\"1\"\n")
            append("    GCamera:MicroVideoVersion=\"1\"\n")
            append("    GCamera:MicroVideoOffset=\"$size\"\n")
            append("    GCamera:MicroVideoPresentationTimestampUs=\"0\">\n")
            // ---- 容器目录：告诉解析器文件里有两段 Item ----
            append("   <Container:Directory>\n")
            append("    <rdf:Seq>\n")
            append("     <rdf:li rdf:parseType=\"Resource\">\n")
            append("      <Container:Item Item:Mime=\"image/jpeg\" Item:Semantic=\"Primary\"")
            append(" Item:Length=\"0\" Item:Padding=\"0\"/>\n")
            append("     </rdf:li>\n")
            append("     <rdf:li rdf:parseType=\"Resource\">\n")
            append("      <Container:Item Item:Mime=\"video/mp4\" Item:Semantic=\"MotionPhoto\"")
            append(" Item:Length=\"$size\" Item:Padding=\"0\"/>\n")
            append("     </rdf:li>\n")
            append("    </rdf:Seq>\n")
            append("   </Container:Directory>\n")
            append("  </rdf:Description>\n")
            append(" </rdf:RDF>\n")
            append("</x:xmpmeta>\n")
            append("<?xpacket end=\"w\"?>")
        }
    }
}
