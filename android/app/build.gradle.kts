import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名放在 android/app/key.properties（已被 .gitignore 忽略）：
//   storeFile=sekainook-release.jks / storePassword=… / keyAlias=… / keyPassword=…
// 换机器或 CI 上想发正式包，把 .jks 和这份 properties 一起拷过去即可 —— 绝不要重新生成，
// 换了密钥的包在手机上覆盖安装会直接失败（签名不一致）。
val keystorePropertiesFile = file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseSigning) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "com.sekainook.sekainook_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 10+ 依赖 Java 8+ API desugaring：
        // 定时通知在旧安卓（API < 26）上的兼容实现走的是 java.time，不开启会在运行期崩。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sekainook.sekainook_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 只有拿到 key.properties 才建这个配置；没有就退回 debug 签名，
        // 这样别的机器上 `flutter run --release` 依旧能跑（但打出来的包不能发版）。
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 正式包用 android/app/sekainook-release.jks 签名；缺 key.properties 时退回 debug 签名，
            // 只够本机调试 —— tool/publish_apk.ps1 会拒绝上传 debug 签名的包。
            signingConfig = if (hasReleaseSigning) {
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

dependencies {
    // 与 flutter_local_notifications 要求的版本一致（见其 README 的 Gradle setup）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
