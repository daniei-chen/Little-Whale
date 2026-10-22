import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/* ---------------------------------------------------------------------- */
/* 签名                                                                     */
/* ---------------------------------------------------------------------- */
//
// 【为什么不是 signingConfigs.getByName("debug")】
//
// 原来用的是 AGP 的默认 debug 签名，它取的是 $ANDROID_USER_HOME/.android/debug.keystore。
// 有两个要命的问题：
//   1. **换台机器或改个环境变量，签名就变了** —— 而 Android 拒绝用不同密钥
//      覆盖安装。已经装了 App 的用户会看到「应用未安装」，必须先卸载，
//      而卸载会丢掉解析记录。
//   2. 发布用的就是 debug 密钥，密钥文件却躺在机器上的临时目录里，很容易丢。
//
// 所以：**App 从 v0.0.1 起就一直用同一把密钥**（SHA1 244b76...），
// 现在把它复制进项目固定下来，构建时从 key.properties 读路径。
//
// ★ 这把密钥必须一直用下去 ★
// 换了它，所有已安装的用户都无法升级，只能卸载重装。
// 请务必备份 android/keystore/xiaojingyu.jks（连同下面 key.properties 里的密码）。
val keystorePropsFile = rootProject.file("key.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) {
        keystorePropsFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "cn.flashsave.flashsave"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cn.flashsave.flashsave"
        // Android 7.0。我们的解析依赖系统 WebView，太老的系统 WebView 版本
        // 撑不起注入的钩子脚本，与其装上了用不了，不如装不上。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 【修复 ABI 虚标（v0.0.6）】
        //
        // 只发布 arm64-v8a（与 tools/build.ps1 的既定策略一致：2018 年后的
        // 手机基本都是 arm64）。
        //
        // 为什么必须显式处理：`flutter build apk --target-platform android-arm64`
        // 只剔掉 **Flutter 引擎自身** 的 .so，**不会**剔插件 AAR 里预编译的
        // jniLibs。于是 v0.0.5 出现了这种情况（用 ELF 头实测确认）：
        //     lib/arm64-v8a/       libapp.so + libflutter.so + 插件库   ✅
        //     lib/armeabi-v7a/     只有插件库，没有 libflutter.so      ❌
        //     lib/x86_64/          只有插件库，没有 libflutter.so      ❌
        // APK 因此对外声称支持三个 ABI，而 32 位/模拟器设备装上后
        // 一启动就 UnsatisfiedLinkError: couldn't find "libflutter.so" 崩溃。
        //
        // ★ 踩过的坑：先试了 ndk { abiFilters += "arm64-v8a" }，
        //   重新构建后产物 SHA-256 与未加时**完全相同** —— abiFilters 管不到
        //   AAR 里预编译的 jniLibs。真正能把 .so 从 APK 里剔掉的是下面
        //   packaging.jniLibs.excludes。
        //
        // 以后要发 32 位包：调整下面的 excludes，并用
        // `--target-platform android-arm` 构建，两者要对齐。
        packaging {
            jniLibs {
                excludes += setOf("lib/armeabi-v7a/**", "lib/x86_64/**")
            }
        }

        // 保留 abiFilters 作为"意图声明"：告诉 AGP 我们只要 arm64。
        // 它对 externalNativeBuild（CMake/ndk-build）有效，对 AAR 的
        // 预编译库无效 —— 所以真正的过滤靠上面的 packaging.excludes。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreProps.getProperty("storeFile") != null) {
                // 必须用 rootProject.file —— signingConfigs 里的 file() 是相对
                // **模块目录**（android/app/）解析的，而密钥在 android/keystore/，
                // 用 file() 会找成 android/app/keystore/ 然后报「文件不存在」。
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }

            // 【为什么要显式声明签名方案】
            // 原来只签出了 v2（apksigner 实测：v1=false, v2=true, v3=false）。
            // v3 除了支持密钥轮换，还让签名信息本身带更完整的完整性校验 ――
            // 部分安全引擎会把"只有 v2 的旧式签名"记为可疑特征之一。
            // minSdk 24 用不到 v1（那是 Android 6 及以下的 JAR 签名），关掉即可。
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        release {
            // 有 key.properties 就用固定密钥；没有就退回 debug 签名，
            // 这样从仓库 clone 下来的人不配也能跑 `flutter build apk`。
            signingConfig = if (keystoreProps.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // 【R8 不用在这里配】
            // Flutter Gradle 插件（FlutterPlugin.kt）在 configure 阶段会自动：
            //   releaseBuildType.isMinifyEnabled = true
            //   releaseBuildType.isShrinkResources = true
            //   并挂上 proguard-android-optimize.txt + flutter_proguard_rules.pro
            //   + 本模块的 android/app/proguard-rules.pro（存在就加）
            // 所以这里再写一遍反而可能覆盖它的 proguardFiles，导致 Flutter
            // 引擎的 keep 规则丢失、运行时崩。放个空注释占位提醒后来人。
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
