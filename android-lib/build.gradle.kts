plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.ytdlp.ffmpeg"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        targetSdk = 35

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                // -Dmain=ffmpeg_main is set in CMakeLists.txt target_compile_definitions
                cFlags("-std=c11", "-Os", "-ffunction-sections", "-fdata-sections",
                       "-fPIC", "-DANDROID")
                arguments(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_PLATFORM=android-24",
                    // Use clang (NDK default) — never gcc
                    "-DANDROID_TOOLCHAIN=clang"
                )
            }
        }

        consumerProguardFiles("consumer-rules.pro")
    }

    externalNativeBuild {
        cmake {
            // CMakeLists.txt lives in jni/ (sibling of android-lib/)
            path = "../../jni/CMakeLists.txt"
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isJniDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            // Pre-built FFmpeg .so files (from build.sh output, copied here)
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // Do NOT compress .so files in the APK/AAR.
            // Uncompressed .so → faster load time + smaller install on API 23+
            // (Android extracts compressed .so on install, wasting disk space).
            useLegacyPackaging = false
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    // okhttp for FFmpegLoader download mode
    implementation(libs.okhttp)

    testImplementation(libs.junit)
}
