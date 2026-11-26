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

    // KGP modern: compilerOptions DSL — kotlinOptions(String) kini error
    // pada Gradle 8.9 + KGP 1.9.24 (kotl.in/u1r8ln).
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    defaultConfig {
        applicationId = "com.glimmora.oagents"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ABI ditata oleh splits di bawah + --split-per-abi Flutter;
        // ndk abiFilters TIDAK bo dipakai bersamaan (konflik AGP).
    }

    // proot hasil CI disalin ke android/app/libs/arm64-v8a/libproot.so
    // dan dibaca RuntimePlugin dari applicationInfo.nativeLibraryDir.
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("libs")
        }
    }

    // ---- Signing rilis ---------------------------------------------------
    // Keystore didecode workflow release.yml dari secret KEYSTORE_BASE64 ke
    // android/app/keystore.jks; password/alias lewat env vars yang dibaca
    // gradle langsung. Lokal tanpa env → fallback debug key (tetap buildable).
    val keystoreFile = rootProject.file("app/keystore.jks")
    val storePass = System.getenv("KEYSTORE_PASSWORD") ?: ""
    val alias = System.getenv("KEY_ALIAS") ?: ""
    val keyPass = System.getenv("KEY_PASSWORD") ?: ""
    val hasReleaseKeystore = keystoreFile.exists() && storePass.isNotEmpty()

    if (hasReleaseKeystore) {
        signingConfigs {
            create("release") {
                storeFile = keystoreFile
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass
            }
        }
    }

    // ---- Signing debug deterministik -------------------------------------
    // Keystore debug di-repo (bukan ~/.android/debug.keystore per-runner):
    // job build (pembuat artefak APK debug) dan job e2e berada di runner
    // BERBEDA — tanpa pin, signature tidak pernah cocok antar-runner.
    val debugKeystore = rootProject.file("app/debug/app-debug.keystore")
    if (debugKeystore.exists()) {
        signingConfigs {
            create("debugPinned") {
                storeFile = debugKeystore
                storePassword = "oagents-debug-2026"
                keyAlias = "oagents-debug"
                keyPassword = "oagents-debug-2026"
            }
        }
    }

    buildTypes {
        debug {
            if (debugKeystore.exists()) {
                signingConfig = signingConfigs.getByName("debugPinned")
            }
        }
        release {
            // R8 aktif untuk ukuran kecil; keep rules plugin ada di proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Tanpa keystore (build lokal tanpa env) → debug key supaya
                // tetap bisa dibangun; CI rilis selalu menyediakan keystore.
                signingConfigs.getByName("debugPinned")
            }
        }
    }

    // ---- Split per ABI ----------------------------------------------------
    // flutter build apk --split-per-abi mengirim -Psplit-per-abi=true;
    // buat APK per ABI (arm64-v8a, armeabi-v7a, x86_64) + universal.
    splits {
        abi {
            isEnable = gradle.startParameter.projectProperties["split-per-abi"] == "true"
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
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
    // Kotlin stdlib + org.json (bundel Android) — tanpa library eksternal
    // (kontrak BRIDGE_CONTRACT.md). io.flutter.embedding datang dari
    // subproject plugin via flutter-plugin-loader di settings.gradle.kts.
}
