plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.loriek.onlystream"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.loriek.onlystream"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
    val keystorePass = System.getenv("ANDROID_KEYSTORE_PASS")?.takeIf { it.isNotBlank() }
    val keystoreAlias = System.getenv("ANDROID_KEY_ALIAS")?.takeIf { it.isNotBlank() }
    val keystoreKeyPass = System.getenv("ANDROID_KEY_PASS")?.takeIf { it.isNotBlank() } ?: keystorePass
    val keystoreFile = keystorePath?.let { file(it) }?.takeIf { it.exists() }

    signingConfigs {
        if (keystoreFile != null && keystorePass != null && keystoreAlias != null && keystoreKeyPass != null) {
            create("release") {
                storeFile = keystoreFile
                storePassword = keystorePass
                keyAlias = keystoreAlias
                keyPassword = keystoreKeyPass
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
