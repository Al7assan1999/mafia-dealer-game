import java.util.Properties

// The upload key signs every build (debug too), so Google sign-in sees one SHA-1 everywhere. Locally it comes from
// android/key.properties (git-ignored), in CI from the ANDROID_KEYSTORE_FILE / ANDROID_KEYSTORE_PASSWORD env vars.
val keyProps = Properties().apply { rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) } }
val keyFile: String? = keyProps.getProperty("storeFile") ?: System.getenv("ANDROID_KEYSTORE_FILE")
val keyPass: String? = keyProps.getProperty("password") ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
// Push (Firebase) only when google-services.json is here: locally put there by hand, in CI written from the
// GOOGLE_SERVICES_JSON secret. Without it the app builds and runs with push switched off.
if (file("google-services.json").exists()) apply(plugin = "com.google.gms.google-services")

android {
    namespace = "com.mafiadealer.game"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mafiadealer.game"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24  // Android 7.0
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyFile != null && keyPass != null) {
            create("upload") { storeFile = file(keyFile); storePassword = keyPass; keyAlias = "upload"; keyPassword = keyPass }
        }
    }
    val signing = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")  // no key (a fork): debug key

    buildTypes {
        debug { signingConfig = signing }
        release { signingConfig = signing }
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
