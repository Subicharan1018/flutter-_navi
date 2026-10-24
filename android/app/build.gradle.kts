import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.navivibe.navivibe"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.navivibe.navivibe"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Native libs stay stored (not deflated) and page-aligned inside the APK, so
    // libapp.so / libflutter.so diff well and a release update ships as a small
    // binary patch (see lib/features/updates and docs/RELEASING.md).
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    // Release signing comes from android/key.properties (local, git-ignored) or
    // from NAVI_KEYSTORE_* environment variables (CI). With neither present the
    // release build falls back to the debug key, so `flutter run --release`
    // keeps working on a fresh checkout.
    val releaseKeystore = run {
        val props = Properties()
        val propsFile = rootProject.file("key.properties")
        if (propsFile.exists()) propsFile.inputStream().use { props.load(it) }
        fun pick(prop: String, env: String): String? =
            props.getProperty(prop) ?: System.getenv(env)
        val store = pick("storeFile", "NAVI_KEYSTORE_FILE")
        val storePass = pick("storePassword", "NAVI_KEYSTORE_PASSWORD")
        val alias = pick("keyAlias", "NAVI_KEY_ALIAS")
        val keyPass = pick("keyPassword", "NAVI_KEY_PASSWORD") ?: storePass
        if (store != null && storePass != null && alias != null && keyPass != null) {
            val f = rootProject.file(store).takeIf { it.exists() } ?: file(store)
            if (f.exists()) listOf(f, storePass, alias, keyPass) else null
        } else null
    }

    if (releaseKeystore != null) {
        signingConfigs {
            create("release") {
                storeFile = releaseKeystore[0] as File
                storePassword = releaseKeystore[1] as String
                keyAlias = releaseKeystore[2] as String
                keyPassword = releaseKeystore[3] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeystore != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
