pluginManagement {
    // 【为什么这里手动按 UTF-8 读 local.properties】
    //
    // Flutter tools 在构建时会把 SDK 路径写进 android/local.properties，
    // 写入用的是 **UTF-8**。而 Java 的 java.util.Properties.load(InputStream)
    // 是**固定按 ISO-8859-1 解码**的 —— 两者对不上。
    //
    // 平时没事，因为大家的 SDK 路径里只有 ASCII。但只要 Flutter SDK 装在
    // 含中文（或任何非 Latin-1 字符）的目录下，比如本机的
    //     D:\Flutter\Dart工具链\flutter
    // 就会被解码成 "Dartå·¥å·é¾"，于是 Gradle 直接报：
    //     Included build 'D:\Flutter\Dart?????\flutter\packages\...' does not exist
    //     BUILD FAILED
    // 而且这个报错完全不提"编码"两个字，极难定位。
    //
    // 用 InputStreamReader 显式指定 UTF-8 就绕开了。这同时也让仓库对
    // 「SDK 装在中文路径」的机器可构建 —— 这是真实存在的问题，不是本机特例。
    //
    // 另外补了个 fallback：local.properties 不存在时读 FLUTTER_ROOT 环境变量，
    // 免得新 clone 的人看到一个莫名其妙的 file-not-found。
    val localProperties = file("local.properties")
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            if (localProperties.exists()) {
                localProperties.inputStream().use { stream ->
                    properties.load(java.io.InputStreamReader(stream, Charsets.UTF_8))
                }
            }
            properties.getProperty("flutter.sdk")
                ?: System.getenv("FLUTTER_ROOT")
                ?: error(
                    "拿不到 Flutter SDK 路径：" +
                        "请在 android/local.properties 里设置 flutter.sdk，" +
                        "或设置 FLUTTER_ROOT 环境变量。"
                )
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
