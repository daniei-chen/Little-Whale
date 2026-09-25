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
