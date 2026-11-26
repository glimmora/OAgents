plugins {
    id("com.android.application")
    id("kotlin-android")
    // Plugin Flutter Gradle diterapkan dari settings pluginManagement
    // (includeBuild flutter_tools/gradle) — pola template Flutter 2024+.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.glimmora.oagents"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.glimmora.oagents"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // proot hanya dibangun untuk aarch64 — ABI tunggal.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // proot hasil CI disalin ke android/app/libs/arm64-v8a/libproot.so
    // dan dibaca RuntimePlugin dari applicationInfo.nativeLibraryDir.
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("libs")
        }
    }

    buildTypes {
        release {
            // R8 aktif untuk ukuran kecil; keep rules plugin ada di proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // libproot.so dibundel manual dari libs/arm64-v8a — pastikan tidak
    // di-strip/di-repack oleh AGP.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Kotlin stdlib saja + org.json (bundel Android) — tanpa library eksternal.
    // Tidak ada implementasi tambahan (kontrak BRIDGE_CONTRACT.md).
}

// KGP modern: compilerOptions DSL — kotlinOptions(String) kini error
// pada Gradle 8.9 + KGP 1.9.24 (kotl.in/u1r8ln).
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}
