plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.linguatrace.lingua_trace"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.linguatrace.lingua_trace"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // NOTE: Flutter's Gradle plugin overrides defaultConfig.ndk.abiFilters
        // for the standard `flutter build apk` task, so setting them here
        // has no effect on a normal Flutter build. To ship an arm64-only APK
        // (cuts size by ~100 MB once flutter_gemma's LiteRT-LM is in the mix),
        // pass `--target-platform android-arm64` to the build command:
        //
        //   flutter build apk --release --target-platform android-arm64
        //
        // For a fat APK that supports x86 emulators too, drop the flag.
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 keep rules — silence warnings about optional MediaPipe deps
            // (pulled in by flutter_gemma) that aren't on the runtime classpath.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
            // Third-party AARs (flutter_gemma, google_mlkit_translation) ship
            // native libs for every ABI. `--target-platform android-arm64` only
            // filters Flutter's own libs, leaving ~60 MB of unused x86 / v7a
            // libs in the APK. Exclude them explicitly to halve the APK size.
            excludes += setOf(
                "lib/x86/**",
                "lib/x86_64/**",
                "lib/armeabi-v7a/**",
            )
        }
    }
}

flutter {
    source = "../.."
}
