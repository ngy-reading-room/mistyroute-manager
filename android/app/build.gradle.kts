plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ngy.mistyroutemanager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ngy.mistyroutemanager"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 23: flutter_secure_storage v11 needs Android 6.0+.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The debug keystore lives in the PERSISTENT workspace (not
    // /root/.android): the VM is replaced from time to time and /root is
    // wiped, which regenerates the debug key and changes the APK's SHA-1
    // — breaking Google sign-in (DEVELOPER_ERROR, status 10) until the new
    // fingerprint is registered. Same keystore as NGY Reading Room, so
    // the APK signature (and its SHA-1) stays stable across rebuilds.
    // SHA-1: 2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6
    // (register this fingerprint for the Google Sheets OAuth client).
    signingConfigs {
        getByName("debug") {
            storeFile = file("/home/hatch/workspace/tools/android-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
